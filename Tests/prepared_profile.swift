import Foundation
import CryptoKit

@main struct PreparedProfileChecks {
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? manager.removeItem(at: root) }
        let game = root.appendingPathComponent("game"), support = root.appendingPathComponent("support")
        let scripts = game.appendingPathComponent("gamedata/scripts")
        try manager.createDirectory(at: scripts, withIntermediateDirectories: true)
        try manager.createDirectory(at: support, withIntermediateDirectories: true)
        let source = scripts.appendingPathComponent("sample.script"), data = Data("return true\n".utf8)
        let manifest = support.appendingPathComponent("support-manifest.json"), supportData = Data("fixture support\n".utf8)
        func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        func rejected(_ operation: () throws -> Void) {
            do { try operation(); fatalError("Invalid prepared data was accepted") } catch {}
        }
        try data.write(to: source); try supportData.write(to: manifest)
        let record: [String: Any] = ["version": 1, "kind": "cop-ee-classic-compat",
            "supportManifestSHA256": hash(supportData),
            "files": ["gamedata/scripts/sample.script": ["bytes": data.count, "sha256": hash(data)]]]
        let marker = game.appendingPathComponent(PreparedGameProfile.filename)
        try JSONSerialization.data(withJSONObject: record).write(to: marker)
        guard let profile = try PreparedGameProfile.read(from: game) else { fatalError("Missing profile") }
        try profile.verify(in: game, support: support)
        try Data(repeating: 88, count: data.count).write(to: source)
        rejected { try profile.verify(in: game, support: support) }
        try data.write(to: source)
        try Data("different support".utf8).write(to: manifest)
        rejected { try profile.verify(in: game, support: support) }
        try supportData.write(to: manifest)
        try manager.moveItem(at: scripts, to: root.appendingPathComponent("outside"))
        try manager.createSymbolicLink(at: scripts, withDestinationURL: root.appendingPathComponent("outside"))
        rejected { try profile.verify(in: game, support: support) }
        print("Prepared profile: valid copy, same-size corruption, support revision and symlink containment passed.")
    }
}
