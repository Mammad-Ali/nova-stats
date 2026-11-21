import Foundation
import Observation

struct StorageEntry: Identifiable {
    var id: String { path }
    let path: String
    let name: String
    let size: Int64
    let folder: Bool
    var locked = false
}

// walks the home folder once and remembers how big every folder is, so
// moving around the result afterwards is instant
@Observable
final class StorageScanner {
    static let shared = StorageScanner()

    enum State: Equatable {
        case idle
        case scanning(files: Int)
        case done
    }

    private(set) var state = State.idle
    private(set) var current: String
    private(set) var scannedAt: Date?
    private(set) var reading = "" // top folder being walked right now
    private(set) var fullAccess = false
    let root: String

    // folders macOS guards with a permission dialog. without full disk access the
    // scan leaves them alone instead of asking, so nobody gets a pile of popups
    static let guarded = ["Desktop", "Documents", "Downloads", "Music", "Pictures", "Movies/TV",
                          "Library/Containers", "Library/Group Containers", "Library/Daemon Containers",
                          "Library/Mobile Documents", "Library/CloudStorage", "Library/Photos",
                          "Library/Caches/com.apple.Music", "Library/Caches/com.apple.TV",
                          "Library/Caches/com.apple.iTunes"]
    // media libraries can sit anywhere, and opening one asks for photos or media access
    static let guardedKinds: Set<String> = ["photoslibrary", "photolibrary", "musiclibrary", "tvlibrary",
                                            "imovielibrary", "theater"]

    @ObservationIgnored private var folderSize: [String: Int64] = [:]
    @ObservationIgnored private var folderChildren: [String: [String]] = [:]
    @ObservationIgnored private var bigFiles: [String: [(path: String, size: Int64)]] = [:]
    @ObservationIgnored private var lockedFolders: [String: [String]] = [:]
    @ObservationIgnored private var cancelled = false

    init() {
        var home = NSHomeDirectory()
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir { home = String(cString: dir) }
        root = home
        current = home
        checkAccess()
    }

    // this file only opens with full disk access, and trying never shows a dialog
    func checkAccess() {
        let fd = Darwin.open(root + "/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
        fullAccess = fd >= 0
        if fd >= 0 { Darwin.close(fd) }
    }

    var scanning: Bool {
        if case .scanning = state { return true }
        return false
    }

    func scan() {
        guard !scanning else { return }
        cancelled = false
        checkAccess()
        state = .scanning(files: 0)
        reading = ""
        current = root
        let root = self.root
        let skip = fullAccess ? [] : Set(Self.guarded.map { root + "/" + $0 })
        let skipKinds = fullAccess ? [] : Self.guardedKinds
        DispatchQueue.global(qos: .utility).async { [self] in
            var own: [String: Int64] = [:] // bytes of files directly inside each folder
            var children: [String: [String]] = [root: []]
            var big: [String: [(path: String, size: Int64)]] = [:]
            var locked: [String: [String]] = [:]
            var files = 0
            var posted = ProcessInfo.processInfo.systemUptime
            func post(_ folder: String? = nil) {
                posted = ProcessInfo.processInfo.systemUptime
                let count = files
                DispatchQueue.main.async {
                    self.state = .scanning(files: count)
                    if let folder { self.reading = folder }
                }
            }
            let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
            let walker = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: keys,
                                                        options: [], errorHandler: { _, _ in true }) // skip what macOS won't let us read
            while let url = walker?.nextObject() as? URL {
                if cancelled { break }
                guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isSymbolicLink != true else { continue }
                let path = url.path
                let parent = (path as NSString).deletingLastPathComponent
                if v.isDirectory == true {
                    if skip.contains(path) || skipKinds.contains(url.pathExtension) {
                        walker?.skipDescendants()
                        locked[parent, default: []].append(path)
                        continue
                    }
                    children[parent, default: []].append(path)
                    if children[path] == nil { children[path] = [] }
                    if parent == root { post(url.lastPathComponent) }
                } else {
                    let size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
                    own[parent, default: 0] += size
                    if size >= 10_000_000 { big[parent, default: []].append((path, size)) }
                    files += 1
                    if files % 256 == 0, ProcessInfo.processInfo.systemUptime - posted > 0.25 { post() }
                }
            }

            // add every folder's size into its parent, deepest folders first
            var total = own
            for path in children.keys.sorted(by: { $0.count > $1.count }) where path != root {
                let parent = (path as NSString).deletingLastPathComponent
                total[parent, default: 0] += total[path, default: 0]
            }
            let finished = !cancelled
            DispatchQueue.main.async {
                self.folderSize = total
                self.folderChildren = children
                self.bigFiles = big
                self.lockedFolders = locked
                self.scannedAt = Date()
                self.state = finished ? .done : .idle
            }
        }
    }

    func cancel() {
        cancelled = true
    }

    func open(_ path: String) {
        guard folderChildren[path] != nil else { return }
        current = path
    }

    func up() {
        guard current != root else { return }
        current = (current as NSString).deletingLastPathComponent
    }

    func size(_ path: String) -> Int64 {
        folderSize[path] ?? 0
    }

    // what's inside the current folder, biggest first: folders, big files, and the rest as one line
    func entries() -> [StorageEntry] {
        var list = (folderChildren[current] ?? []).map {
            StorageEntry(path: $0, name: ($0 as NSString).lastPathComponent, size: folderSize[$0] ?? 0, folder: true)
        }
        list += (bigFiles[current] ?? []).map {
            StorageEntry(path: $0.path, name: ($0.path as NSString).lastPathComponent, size: $0.size, folder: false)
        }
        let shown = list.reduce(0) { $0 + $1.size }
        let rest = size(current) - shown
        if rest > 1_000_000 {
            list.append(StorageEntry(path: current + "/…", name: "Smaller files", size: rest, folder: false))
        }
        list = list.filter { $0.size > 0 }.sorted { $0.size > $1.size }
        // locked folders last, the well known ones like Desktop first
        let order = { (path: String) in Self.guarded.firstIndex(of: String(path.dropFirst(self.root.count + 1))) ?? 99 }
        return list + (lockedFolders[current] ?? []).sorted { order($0) < order($1) }.map {
            StorageEntry(path: $0, name: ($0 as NSString).lastPathComponent, size: 0, folder: false, locked: true)
        }
    }

    // the path from home down to the current folder, for the back button
    var trail: String {
        current == root ? "Home" : "Home" + current.dropFirst(root.count).replacingOccurrences(of: "/", with: " › ")
    }
}
