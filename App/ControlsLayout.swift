import UIKit

struct LayoutEntry: Codable, Equatable {
    var x: Double, y: Double, scale: Double, opacity: Double
    var hidden: Bool
    var action: StalkerAction?
}
struct LayoutDocument: Codable {
    var version = 1
    var entries: [String: LayoutEntry]
}
enum ControlsLayout {
    static let profiles = ["Layout 1", "Layout 2", "Layout 3"]
    static let essential: Set<String> = ["move", "pause", "tools"]
    static var profile: Int {
        get { max(0, min(2, UserDefaults.standard.integer(forKey: "zone.layout.profile"))) }
        set { UserDefaults.standard.set(max(0, min(2, newValue)), forKey: "zone.layout.profile") }
    }
    private static var key: String { "zone.layout.\(profile)" }
    static var entries: [String: LayoutEntry] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let document = try? JSONDecoder().decode(LayoutDocument.self, from: data),
                  let valid = try? validate(document) else { return [:] }
            return valid.entries
        }
        set {
            if let data = try? JSONEncoder().encode(LayoutDocument(entries: newValue)) { UserDefaults.standard.set(data, forKey: key) }
        }
    }
    static func entry(for spec: ControlSpec) -> LayoutEntry {
        entries[spec.id] ?? LayoutEntry(x: Double(spec.x), y: Double(spec.y), scale: 1, opacity: 1, hidden: false, action: spec.action)
    }
    static func set(_ entry: LayoutEntry, id: String) {
        var next = entries; next[id] = entry; entries = next
    }
    static func reset() { entries = [:] }
    static func exported() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(LayoutDocument(entries: entries))
    }
    static func imported(_ data: Data) throws {
        guard data.count <= 128 * 1024 else { throw LayoutError.invalid }
        entries = try validate(JSONDecoder().decode(LayoutDocument.self, from: data)).entries
    }
    enum LayoutError: LocalizedError {
        case invalid
        var errorDescription: String? { "This is not a supported controls layout." }
    }
    static func validate(_ doc: LayoutDocument) throws -> LayoutDocument {
        guard doc.version == 1, doc.entries.count <= ControlSpec.all.count else { throw LayoutError.invalid }
        let ids = Set(ControlSpec.all.map(\.id))
        for (id, e) in doc.entries {
            guard ids.contains(id), e.x.isFinite, e.y.isFinite, e.scale.isFinite, e.opacity.isFinite,
                  (0...1).contains(e.x), (0...1).contains(e.y), (0.6...1.8).contains(e.scale),
                  (0.2...1).contains(e.opacity), !essential.contains(id) || !e.hidden,
                  id != "pause" || e.action == .pause else { throw LayoutError.invalid }
        }
        return doc
    }
}
