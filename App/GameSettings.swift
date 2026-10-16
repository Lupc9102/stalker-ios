import Foundation

enum AppLanguage {
    static func choose(_ value: String) -> String { value }
    static func interpolate(_ value: String, _ arguments: [String]) -> String {
        arguments.enumerated().reduce(value) { $0.replacingOccurrences(of: "{arg\($1.offset)}", with: $1.element) }
    }
}
enum GameMode: Int, CaseIterable {
    case campaign, practice
    var title: String { self == .campaign ? "Call of Pripyat" : "Controls practice" }
    var symbol: String { self == .campaign ? "map.fill" : "hand.tap.fill" }
    var detail: String { self == .campaign ? "Play your own original PC game files." : "Try movement and buttons. No game files needed." }
}
final class GameSettings {
    static let shared = GameSettings()
    private let defaults = UserDefaults.standard
    var lookSensitivity: Double {
        get { defaults.object(forKey: "lookSensitivity") as? Double ?? 1.0 }
        set { defaults.set(max(0.2, min(3, newValue)), forKey: "lookSensitivity") }
    }
    var controlOpacity: Double {
        get { defaults.object(forKey: "controlOpacity") as? Double ?? 0.85 }
        set { defaults.set(max(0.2, min(1, newValue)), forKey: "controlOpacity") }
    }
    var showLabels: Bool {
        get { defaults.object(forKey: "showLabels") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showLabels") }
    }
    var toggleAim: Bool {
        get { defaults.object(forKey: "toggleAim") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "toggleAim") }
    }
    var leftHanded: Bool {
        get { defaults.bool(forKey: "leftHanded") }
        set { defaults.set(newValue, forKey: "leftHanded") }
    }
}
