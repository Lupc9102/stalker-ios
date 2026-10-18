import Foundation

@main struct LocalGameFilesChecks {
    static func main() throws {
        let manager = FileManager.default
        let documents = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? manager.removeItem(at: documents) }
        let local = try GameFiles.prepareLocalFolder(in: documents)
        precondition(manager.fileExists(atPath: local.appendingPathComponent("START-HERE.txt").path))
        precondition(GameFiles.findLocal(in: documents) == nil)
        // No dummy archive folders: extracting a complete ZIP into GameFiles
        // must discover the nested game, even with an incomplete sibling copy.
        let partial = local.appendingPathComponent("A-incomplete/resources")
        try manager.createDirectory(at: partial, withIntermediateDirectories: true)
        let game = local.appendingPathComponent("CoP-Mobile-Complete/CoP-Mobile")
        for name in ["resources", "levels", "localization"] {
            let dir = game.appendingPathComponent(name)
            try manager.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("presence fixture, not playable data".utf8).write(to: dir.appendingPathComponent(name + ".db0"))
        }
        let detected = GameFiles.findLocal(in: documents)
        precondition(detected?.detected == true && detected?.archiveCount == 3)
        precondition(detected?.root.standardizedFileURL.path == game.standardizedFileURL.path)
        let archive = game.appendingPathComponent("levels/levels.db0")
        let before = try Data(contentsOf: archive)
        try GameFiles.prepareLocalFolder(in: documents)
        let after = try Data(contentsOf: archive)
        precondition(after == before)
        // Moving a fixture away while the app is suspended must be reflected
        // in the next scan, rather than caching a previous successful result.
        try manager.removeItem(at: game)
        precondition(GameFiles.findLocal(in: documents)?.detected != true)
        try manager.removeItem(at: local.appendingPathComponent("A-incomplete"))
        let outside = documents.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: outside) }
        try manager.createSymbolicLink(at: local.appendingPathComponent("Linked"), withDestinationURL: outside)
        precondition(GameFiles.findLocal(in: documents) == nil)
        print("Local game folder: creation, nested ZIP, partial sibling, non-destructive refresh, removal and symlink checks passed.")
    }
}
