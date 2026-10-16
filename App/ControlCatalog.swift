import UIKit
#if SWIFT_PACKAGE
import ZoneNative
#endif

enum StalkerAction: Int, Codable, CaseIterable, Hashable {
    case fire, aim, use, reload, jump, crouch, sprint, inventory, pda, torch,
         detector, knife, bolt, weaponNext, medkit, bandage, leanLeft, leanRight, pause
    var native: ZAction { ZAction(rawValue: UInt32(rawValue)) }
    var title: String {
        ["Fire", "Aim", "Use", "Reload", "Jump", "Crouch", "Sprint", "Inventory", "PDA", "Torch",
         "Detector", "Knife", "Bolt", "Next weapon", "Medkit", "Bandage", "Lean left", "Lean right", "Pause"][rawValue]
    }
    var symbol: String {
        ["scope", "viewfinder", "hand.point.up.left.fill", "arrow.clockwise", "figure.jumprope", "figure.flexibility", "figure.run",
         "backpack.fill", "map.fill", "flashlight.on.fill", "waveform.path", "scissors", "bolt.fill", "arrow.triangle.2.circlepath",
         "cross.case.fill", "bandage.fill", "arrow.left.to.line", "arrow.right.to.line", "pause.fill"][rawValue]
    }
}
struct ControlSpec {
    let id: String, title: String, symbol: String
    let action: StalkerAction?
    let x: CGFloat, y: CGFloat, diameter: CGFloat
    let utility: Bool
    static let all: [ControlSpec] = [
        .init(id: "move", title: "Move", symbol: "move.3d", action: nil, x: 0.12, y: 0.72, diameter: 112, utility: false),
        .init(id: "fire", title: "Fire", symbol: "scope", action: .fire, x: 0.90, y: 0.48, diameter: 70, utility: false),
        .init(id: "aim", title: "Aim", symbol: "viewfinder", action: .aim, x: 0.78, y: 0.50, diameter: 58, utility: false),
        .init(id: "use", title: "Use", symbol: "hand.point.up.left.fill", action: .use, x: 0.87, y: 0.72, diameter: 56, utility: false),
        .init(id: "reload", title: "Reload", symbol: "arrow.clockwise", action: .reload, x: 0.96, y: 0.72, diameter: 48, utility: false),
        .init(id: "jump", title: "Jump", symbol: "figure.jumprope", action: .jump, x: 0.96, y: 0.91, diameter: 52, utility: false),
        .init(id: "crouch", title: "Crouch", symbol: "figure.flexibility", action: .crouch, x: 0.85, y: 0.91, diameter: 48, utility: false),
        .init(id: "sprint", title: "Sprint", symbol: "figure.run", action: .sprint, x: 0.12, y: 0.43, diameter: 48, utility: false),
        .init(id: "inventory", title: "Inventory", symbol: "backpack.fill", action: .inventory, x: 0.05, y: 0.09, diameter: 46, utility: false),
        .init(id: "pda", title: "PDA", symbol: "map.fill", action: .pda, x: 0.13, y: 0.09, diameter: 46, utility: false),
        .init(id: "torch", title: "Torch", symbol: "flashlight.on.fill", action: .torch, x: 0.21, y: 0.09, diameter: 44, utility: false),
        .init(id: "weaponNext", title: "Weapon", symbol: "arrow.triangle.2.circlepath", action: .weaponNext, x: 0.72, y: 0.91, diameter: 46, utility: false),
        .init(id: "tools", title: "Tools", symbol: "square.grid.2x2.fill", action: nil, x: 0.29, y: 0.09, diameter: 44, utility: false),
        .init(id: "pause", title: "Pause", symbol: "pause.fill", action: .pause, x: 0.96, y: 0.09, diameter: 44, utility: false),
        .init(id: "detector", title: "Detector", symbol: "waveform.path", action: .detector, x: 0.37, y: 0.09, diameter: 44, utility: true),
        .init(id: "knife", title: "Knife", symbol: "scissors", action: .knife, x: 0.45, y: 0.09, diameter: 44, utility: true),
        .init(id: "bolt", title: "Bolt", symbol: "bolt.fill", action: .bolt, x: 0.53, y: 0.09, diameter: 44, utility: true),
        .init(id: "medkit", title: "Medkit", symbol: "cross.case.fill", action: .medkit, x: 0.61, y: 0.09, diameter: 44, utility: true),
        .init(id: "bandage", title: "Bandage", symbol: "bandage.fill", action: .bandage, x: 0.69, y: 0.09, diameter: 44, utility: true),
        .init(id: "leanLeft", title: "Lean L", symbol: "arrow.left.to.line", action: .leanLeft, x: 0.68, y: 0.28, diameter: 42, utility: true),
        .init(id: "leanRight", title: "Lean R", symbol: "arrow.right.to.line", action: .leanRight, x: 0.77, y: 0.28, diameter: 42, utility: true)
    ]
}
enum ControlStyle {
    static let accent = Theme.accent
    static let fallbackSymbol = Dictionary(uniqueKeysWithValues: ControlSpec.all.map { ($0.id, $0.symbol) })
    static let olderSymbol: [String: String] = [:]
}

/// Merge simultaneous input sources so releasing a controller button never
/// releases a finger still holding that same action (and vice versa).
final class InputHub {
    static let shared = InputHub()
    private var held: [String: Set<StalkerAction>] = [:]
    private var movement: [String: CGPoint] = [:]
    private var merged = Set<StalkerAction>()
    func button(_ action: StalkerAction, down: Bool, source: String) {
        if down { held[source, default: []].insert(action) }
        else { held[source]?.remove(action) }
        let next = held.values.reduce(into: Set<StalkerAction>()) { $0.formUnion($1) }
        for action in merged.subtracting(next) { ZHostSetButton(action.native, false) }
        for action in next.subtracting(merged) { ZHostSetButton(action.native, true) }
        merged = next
    }
    func move(_ value: CGPoint, source: String) {
        movement[source] = value
        let best = movement.values.max { hypot($0.x, $0.y) < hypot($1.x, $1.y) } ?? .zero
        ZHostSetMove(Float(best.x), Float(best.y))
    }
    func look(_ delta: CGPoint) {
        ZHostAddLook(Float(delta.x) * Float(GameSettings.shared.lookSensitivity), Float(delta.y) * Float(GameSettings.shared.lookSensitivity))
    }
    func clear(source: String) {
        for action in held[source] ?? [] { button(action, down: false, source: source) }
        movement.removeValue(forKey: source)
        move(.zero, source: source)
    }
    func reset() { held.removeAll(); movement.removeAll(); merged.removeAll(); ZHostResetInput() }
}
