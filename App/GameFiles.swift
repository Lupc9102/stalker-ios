import Foundation

struct GameFilesReport {
    let root: URL
    let archiveCount: Int
    let bytes: Int64
    let problems: [String]
    var detected: Bool { archiveCount > 0 && problems.isEmpty }
    var summary: String {
        detected ? "\(archiveCount) archives · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) · contents not yet verified"
                 : problems.joined(separator: "\n")
    }
}
enum GameFiles {
    /// Presence checks only. These cannot establish archive integrity or game
    /// compatibility; do not describe them as a completed content validation.
    static func inspect(_ root: URL) -> GameFilesReport {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey, .ubiquitousItemDownloadingStatusKey]
        var count = 0, bytes: Int64 = 0, problems: [String] = []
        var directories = ["resources", "levels", "localization"]
        // EE embeds localization in configs.db. Its experimental prepared layer
        // is required; archive presence alone does not establish compatibility.
        if !manager.fileExists(atPath: root.appendingPathComponent("localization").path),
           manager.fileExists(atPath: root.appendingPathComponent("resources/configs.db").path) {
            directories.removeAll { $0 == "localization" }
            do {
                if try PreparedGameProfile.read(from: root) == nil {
                    problems.append("These Enhanced Edition files need the prepared gamedata folder and zone-mobile-profile.json. Copy them beside resources/ and levels/ first.")
                }
            } catch { problems.append(error.localizedDescription) }
        }
        for directory in directories {
            let url = root.appendingPathComponent(directory, isDirectory: true)
            guard let enumerator = manager.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else {
                problems.append("Missing \(directory)/ folder."); continue
            }
            var found = 0
            for case let file as URL in enumerator {
                if enumerator.level > 3 { enumerator.skipDescendants(); continue }
                guard let values = try? file.resourceValues(forKeys: keys) else { continue }
                if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                guard values.isRegularFile == true, file.lastPathComponent.range(of: #"\.db[0-9]*$"#, options: [.regularExpression, .caseInsensitive]) != nil else { continue }
                found += 1; count += 1; bytes += Int64(values.fileSize ?? 0)
                if values.fileSize == 0 { problems.append("Empty archive: \(file.lastPathComponent)") }
                if let status = values.ubiquitousItemDownloadingStatus, status != .current {
                    problems.append("Download \(file.lastPathComponent) to this iPhone first.")
                }
            }
            if found == 0 { problems.append("No game archives in \(directory)/.") }
        }
        return GameFilesReport(root: root, archiveCount: count, bytes: bytes, problems: problems)
    }
    static func find(in root: URL) -> GameFilesReport? {
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("resources").path) { return inspect(root) }
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in enumerator {
            if enumerator.level > 3 { enumerator.skipDescendants(); continue }
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { continue }
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values.isDirectory == true && url.lastPathComponent.lowercased() == "resources" { return inspect(url.deletingLastPathComponent()) }
        }
        return nil
    }
    static var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    static func remember(_ root: URL) throws {
        let bookmark = try root.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: "zone.gameFolder")
    }
    static func saved() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: "zone.gameFolder") else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            try? remember(url)
        }
        return url
    }
}
