import AppKit
import ApplicationServices
import Darwin
import os

/// A process using a file or folder, and how.
struct FileUser: Sendable, Equatable, Identifiable {
    enum Use: Int, Sendable, Comparable {
        /// It's the app itself, running. Ranked first: the strongest sense of "using".
        case running
        /// An app has it open in a window, as document apps do without keeping the file open.
        case window
        /// The process's working folder is this folder.
        case workingFolder
        /// The process holds it open or has it mapped in memory.
        case open
        /// The process has files open on this volume.
        case onVolume

        static func < (lhs: Use, rhs: Use) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let pid: pid_t
    let name: String
    /// The executable's path.
    let executable: String?
    let use: Use

    var id: pid_t { pid }
}

/// Finds who's using a file or folder, and quits them.
enum FileUsers {
    /// Everyone using the item at `url`, apart from `ownPID`. Asks every app about its windows and looks
    /// through every process's open files, which takes a few hundred milliseconds.
    static func find(_ url: URL, excluding ownPID: pid_t = getpid()) async -> [FileUser] {
        let path = FileCard.path(of: url)
        async let windows = Task.detached { appsShowing(path) }.value
        async let holders = Task.detached { processesUsing(path) }.value
        var uses = await holders
        for (pid, use) in await windows { uses[pid] = min(uses[pid] ?? use, use) }
        for app in runningApps(at: path) { uses[app] = .running }
        uses[ownPID] = nil
        return uses.map { FileUser(pid: $0.key, name: name(of: $0.key), executable: executable(of: $0.key), use: $0.value) }
            .sorted { ($0.use, $0.name.lowercased(), $0.pid) < ($1.use, $1.name.lowercased(), $1.pid) }
    }

    /// The app at `path` (an .app bundle), if it's running.
    private static func runningApps(at path: String) -> [pid_t] {
        guard path.hasSuffix(".app") else { return [] }
        let target = canonical(path)
        return NSWorkspace.shared.runningApplications
            .filter { $0.bundleURL.map { canonical(FileCard.path(of: $0)) } == target }
            .map(\.processIdentifier)
    }

    /// Apps with a window whose document is `path`. Document apps such as Preview and TextEdit read a
    /// file and close it, so only their windows tell that it's open.
    private static func appsShowing(_ path: String) -> [pid_t: FileUser.Use] {
        let target = canonical(path)
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map(\.processIdentifier)
        let found = OSAllocatedUnfairLock<[pid_t: FileUser.Use]>(initialState: [:])
        // Each app answers on its own, and a busy one only holds up its own question.
        DispatchQueue.concurrentPerform(iterations: apps.count) { index in
            let app = AXElement.application(pid: apps[index])
            app.setMessagingTimeout(0.25)
            guard let windows = app.attribute(kAXWindowsAttribute) as? [AXUIElement] else { return }
            for window in windows {
                guard let document = AXElement(ref: window).attribute(kAXDocumentAttribute) as? String,
                      let url = URL(string: document), url.isFileURL,
                      canonical(FileCard.path(of: url)) == target else { continue }
                found.withLock { $0[apps[index]] = .window }
                return
            }
        }
        return found.withLock { $0 }
    }

    /// Processes with `path` open, mapped, or as their working folder; for a volume other than the
    /// startup disk, those with anything open on it.
    private static func processesUsing(_ path: String) -> [pid_t: FileUser.Use] {
        let values = try? URL(filePath: path).resourceValues(forKeys: [.isDirectoryKey, .isVolumeKey, .volumeIsRootFileSystemKey])
        let isVolume = values?.isVolume == true && values?.volumeIsRootFileSystem != true
        // Watchers such as Finder's open files only to hear about changes; they don't count.
        var flags = UInt32(PROC_LISTPIDSPATH_EXCLUDE_EVTONLY)
        if isVolume { flags |= UInt32(PROC_LISTPIDSPATH_PATH_IS_VOLUME) }

        var pids = [pid_t](repeating: 0, count: 8192)
        let bytes = proc_listpidspath(UInt32(PROC_ALL_PIDS), 0, path, flags, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return [:] }
        var info = stat()
        let isFolder = values?.isDirectory == true && stat(path, &info) == 0

        var uses: [pid_t: FileUser.Use] = [:]
        for pid in pids.prefix(Int(bytes) / MemoryLayout<pid_t>.size) where pid > 0 {
            if isVolume {
                uses[pid] = .onVolume
            } else if isFolder, workingFolder(of: pid).map({ $0.dev == UInt32(bitPattern: info.st_dev) && $0.inode == info.st_ino }) == true {
                uses[pid] = .workingFolder
            } else {
                uses[pid] = .open
            }
        }
        return uses
    }

    private static func workingFolder(of pid: pid_t) -> (dev: UInt32, inode: UInt64)? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let stat = info.pvi_cdir.vip_vi.vi_stat
        return (stat.vst_dev, stat.vst_ino)
    }

    /// An app's name, or the name a command was started under, which is what `ps` shows: Claude
    /// Code's executable is named for its version ("2.1.296"), but it runs as "claude".
    static func name(of pid: pid_t) -> String {
        let app = NSRunningApplication(processIdentifier: pid)
        if app?.bundleURL != nil, let name = app?.localizedName { return name }
        return commandName(of: pid) ?? app?.localizedName ?? executable(of: pid).map { URL(filePath: $0).lastPathComponent } ?? "Process \(pid)"
    }

    /// The process's first argument, from the kernel's copy of its arguments: the argument count,
    /// the executable's path, padding, then the arguments themselves.
    static func commandName(of pid: pid_t) -> String? {
        var request = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&request, 3, nil, &size, nil, 0) == 0, size > 4 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&request, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        var index = 4
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        let start = index
        while index < size, buffer[index] != 0 { index += 1 }
        guard index > start else { return nil }
        var name = String(decoding: buffer[start..<index], as: UTF8.self)
        // Login shells start as "-zsh", or "-/bin/zsh".
        if name.hasPrefix("-") { name.removeFirst() }
        // A path names its program by the last part; a title a process gave itself ("npm exec …") stays whole.
        if name.hasPrefix("/") { name = URL(filePath: name).lastPathComponent }
        return name.isEmpty ? nil : name
    }

    static func executable(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(4 * MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(decoding: buffer.prefix(Int(length)), as: UTF8.self) : nil
    }

    /// `path` with symbolic links resolved (/tmp → /private/tmp), so two spellings of one file match.
    private static func canonical(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    // MARK: - Quitting

    /// Asks it to quit, as ⌘Q or `kill` would: apps can still ask to save. `force` doesn't ask.
    @MainActor
    static func quit(_ pid: pid_t, force: Bool) -> Bool {
        if !force, let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy != .prohibited {
            return app.terminate()
        }
        return kill(pid, force ? SIGKILL : SIGTERM) == 0
    }

    static func isRunning(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
