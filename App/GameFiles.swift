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
        // Walk directories, not thousands of textures. Accept an extracted ZIP's
        // enclosing folders, and prefer a complete installation over a partial copy.
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let excluded: Set<String> = ["gamedata", "levels", "resources", "localization", "zoneportdata", "benchmark", "_appdata_"]
        var pending = [(root, 0)], firstProblem: GameFilesReport?
        var index = 0
        while index < pending.count {
            let (directory, depth) = pending[index]; index += 1
            guard let values = try? directory.resourceValues(forKeys: keys),
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }
            if manager.fileExists(atPath: directory.appendingPathComponent("resources").path) {
                let report = inspect(directory)
                if report.detected { return report }
                if firstProblem == nil { firstProblem = report }
            }
            guard depth < 3, let children = try? manager.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { continue }
            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                if !excluded.contains(child.lastPathComponent.lowercased()) { pending.append((child, depth + 1)) }
            }
        }
        return firstProblem
    }
    static var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    static let localFolderName = "GameFiles"
    static var localFolder: URL { documents.appendingPathComponent(localFolderName, isDirectory: true) }

    /// Creating a real document makes the app's container appear in iOS Files.
    /// Never create dummy resources/levels folders or change the player's data.
    @discardableResult
    static func prepareLocalFolder(in documents: URL = GameFiles.documents) throws -> URL {
        let folder = documents.appendingPathComponent(localFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let readme = folder.appendingPathComponent("START-HERE.txt")
        if !FileManager.default.fileExists(atPath: readme.path) {
            try """
            Move your extracted CoP-Mobile folder here using the Files app.

            On My iPhone > ZonePort > GameFiles > CoP-Mobile

            CoP-Mobile must contain resources, levels, gamedata and zone-mobile-profile.json.
            Return to ZonePort. The app detects the files automatically; no folder picker is needed.
            You can also place resources, levels and the prepared files directly in GameFiles.
            Extract the ZIP first. Wait for the entire copy to finish before pressing Play.
            """.write(to: readme, atomically: true, encoding: .utf8)
        }
        return folder
    }

    static func findLocal(in documents: URL = GameFiles.documents) -> GameFilesReport? {
        let preferred = find(in: documents.appendingPathComponent(localFolderName, isDirectory: true))
        if preferred?.detected == true { return preferred }
        return find(in: documents) ?? preferred
    }
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
