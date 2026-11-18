#ifndef smc_h
#define smc_h

int smc_open(void);
void smc_close(void);
int smc_key_count(void);
int smc_key_at(int index, char *name);
int smc_read(const char *name, double *value);

#endif
