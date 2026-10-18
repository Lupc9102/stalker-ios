import Foundation
import CryptoKit

/// Private prepared files stay in the selected game folder. The native file
/// layer opens originals read-only and keeps saves in the app's data folder.
struct PreparedGameProfile: Decodable {
    struct File: Decodable { let bytes: Int; let sha256: String }
    let version: Int
    let kind: String
    let supportManifestSHA256: String
    let files: [String: File]
    static let filename = "zone-mobile-profile.json"

    static func validPath(_ name: String) -> Bool {
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        return name.utf8.count <= 512 && parts.count >= 3 && parts[0] == "gamedata"
            && ["configs", "scripts", "textures", "levels", "shaders"].contains(String(parts[1]))
            && !parts.contains(where: { $0.isEmpty || $0.hasPrefix(".") })
            && !name.contains(where: { $0 == "\\" || $0 == ":" || $0 == "\0" })
    }
    static func read(from root: URL) throws -> PreparedGameProfile? {
        let url = root.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? 0) <= 4 * 1024 * 1024 else { throw invalid() }
        let profile = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard profile.version == 1, profile.kind == "cop-ee-classic-compat",
              !profile.files.isEmpty, profile.files.count <= 12000,
              profile.files.keys.allSatisfy(validPath),
              profile.files.values.allSatisfy({ $0.bytes > 0 && $0.bytes <= 256 * 1024 * 1024
                  && $0.sha256.count == 64 && $0.sha256.allSatisfy({ "0123456789abcdef".contains($0) }) })
        else { throw invalid() }
        return profile
    }
    func verify(in root: URL, support: URL) throws {
        let manifest = try Data(contentsOf: support.appendingPathComponent("support-manifest.json"))
        guard Self.hash(manifest) == supportManifestSHA256 else {
            throw NSError(domain: "ZonePort", code: 12, userInfo: [NSLocalizedDescriptionKey:
                "These prepared game files are for a different app build. Prepare them again with the current tools."])
        }
        for (name, record) in files {
            var url = root
            for part in name.split(separator: "/") {
                url.appendPathComponent(String(part))
                let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw Self.invalid() }
            }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, values.fileSize == record.bytes else { throw Self.invalid() }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hash = SHA256(), count = 0
            while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
                count += data.count
                guard count <= record.bytes else { throw Self.invalid() }
                hash.update(data: data)
            }
            guard count == record.bytes, Self.hex(hash.finalize()) == record.sha256 else {
                throw NSError(domain: "ZonePort", code: 13, userInfo: [NSLocalizedDescriptionKey:
                    "A prepared game file is incomplete or changed: \(url.lastPathComponent). Copy the prepared files again."])
            }
        }
    }
    private static func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }
    private static func hash(_ data: Data) -> String { hex(SHA256.hash(data: data)) }
    private static func invalid() -> NSError {
        NSError(domain: "ZonePort", code: 11, userInfo: [NSLocalizedDescriptionKey:
            "The prepared game files are missing or invalid. Copy the full gamedata folder and its profile file again."])
    }
}
