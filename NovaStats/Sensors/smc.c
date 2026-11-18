#include "smc.h"
#include <IOKit/IOKitLib.h>
#include <string.h>

// layout has to match the kernel side exactly (80 bytes)
typedef struct { char major, minor, build, reserved; UInt16 release; } smc_vers;
typedef struct { UInt16 version, length; UInt32 cpu, gpu, mem; } smc_plimit;
typedef struct { UInt32 size; UInt32 type; char attributes; } smc_keyinfo;
typedef struct {
    UInt32 key;
    smc_vers vers;
    smc_plimit plimit;
    smc_keyinfo info;
    char result, status, cmd;
    UInt32 data32;
    unsigned char bytes[32];
} smc_data;

enum { READ_KEY = 5, KEY_AT_INDEX = 8, KEY_INFO = 9 };

static io_connect_t conn = 0;

static UInt32 fourcc(const char *s) {
    return ((UInt32)s[0] << 24) | ((UInt32)s[1] << 16) | ((UInt32)s[2] << 8) | (UInt32)s[3];
}

static int smc_call(smc_data *in, smc_data *out) {
    size_t size = sizeof(smc_data);
    if (IOConnectCallStructMethod(conn, 2, in, sizeof(smc_data), out, &size) != kIOReturnSuccess) return -1;
    return out->result == 0 ? 0 : -1;
}

int smc_open(void) {
    if (conn) return 0;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return -1;
    kern_return_t r = IOServiceOpen(service, mach_task_self(), 0, &conn);
    IOObjectRelease(service);
    return r == KERN_SUCCESS ? 0 : -1;
}

void smc_close(void) {
    if (conn) IOServiceClose(conn);
    conn = 0;
}

// key info never changes, so remember it and save a kernel call per read
static struct { UInt32 key; smc_keyinfo info; } known[256];
static int known_count = 0;

static int key_info(UInt32 key, smc_keyinfo *info) {
    for (int i = 0; i < known_count; i++) {
        if (known[i].key == key) {
            *info = known[i].info;
            return 0;
        }
    }
    smc_data in = {0}, out = {0};
    in.key = key;
    in.cmd = KEY_INFO;
    if (smc_call(&in, &out)) return -1;
    *info = out.info;
    if (known_count < 256) {
        known[known_count].key = key;
        known[known_count].info = out.info;
        known_count++;
    }
    return 0;
}

static int read_raw(UInt32 key, smc_keyinfo *info, unsigned char *bytes) {
    smc_data in = {0}, out = {0};
    if (key_info(key, info)) return -1;

    memset(&in, 0, sizeof in);
    memset(&out, 0, sizeof out);
    in.key = key;
    in.info.size = info->size;
    in.cmd = READ_KEY;
    if (smc_call(&in, &out)) return -1;
    memcpy(bytes, out.bytes, 32);
    return 0;
}

int smc_key_count(void) {
    smc_keyinfo info;
    unsigned char b[32];
    if (read_raw(fourcc("#KEY"), &info, b)) return 0;
    return (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
}

int smc_key_at(int index, char *name) {
    smc_data in = {0}, out = {0};
    in.cmd = KEY_AT_INDEX;
    in.data32 = (UInt32)index;
    if (smc_call(&in, &out)) return -1;
    name[0] = out.key >> 24;
    name[1] = out.key >> 16;
    name[2] = out.key >> 8;
    name[3] = out.key;
    name[4] = 0;
    return 0;
}

int smc_read(const char *name, double *value) {
    smc_keyinfo info;
    unsigned char b[32];
    if (strlen(name) != 4 || read_raw(fourcc(name), &info, b)) return -1;

    UInt32 t = info.type;
    if (t == fourcc("flt ")) {
        float f;
        memcpy(&f, b, 4);
        *value = f;
    } else if (t == fourcc("sp78")) {
        *value = (SInt16)((b[0] << 8) | b[1]) / 256.0;
    } else if (t == fourcc("fpe2")) {
        *value = ((b[0] << 8) | b[1]) / 4.0;
    } else if (t == fourcc("ui8 ")) {
        *value = b[0];
    } else if (t == fourcc("ui16")) {
        *value = (b[0] << 8) | b[1];
    } else {
        return -1;
    }
    return 0;
}
