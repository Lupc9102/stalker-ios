import UIKit

/// STALKER controls using the licensed GTA port's circular buttons and floating
/// stick. Touch identity is retained until release, including drags off a button.
final class TouchControlsView: UIView {
    var onPause: (() -> Void)?
    var onInput: (() -> Void)?
    var editing = false { didSet { reset(); setNeedsLayout() } }
    var highlighted: String? { didSet { updateAppearance() } }
    var toolsVisible = false { didSet { updateAppearance() } }
    private(set) var buttons: [String: ControlButton] = [:]
    private let captions: [String: UILabel]
    private let stick = FloatingStick(frame: .zero)
    private var aimLatched = false
    private enum Role {
        case move, look(CGPoint), action(StalkerAction, String), utility
    }
    private var fingers: [UITouch: Role] = [:]
    private var heldCounts: [StalkerAction: Int] = [:]
    private var visualCounts: [String: Int] = [:]

    override init(frame: CGRect) {
        var labels: [String: UILabel] = [:]
        for spec in ControlSpec.all {
            let label = UILabel(); label.font = .systemFont(ofSize: 10, weight: .semibold)
            label.textColor = .white; label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true; label.minimumScaleFactor = 0.8
            label.layer.shadowColor = UIColor.black.cgColor; label.layer.shadowOpacity = 1; label.layer.shadowRadius = 3
            label.text = spec.title; label.isUserInteractionEnabled = false; labels[spec.id] = label
        }
        captions = labels
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        stick.frame = bounds; stick.autoresizingMask = [.flexibleWidth, .flexibleHeight]; addSubview(stick)
        for spec in ControlSpec.all {
            let button = ControlButton(spec.id, icon: spec.id, label: spec.title)
            buttons[spec.id] = button; addSubview(button); addSubview(captions[spec.id]!)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    private var safe: CGRect { bounds.inset(by: safeAreaInsets).insetBy(dx: 9, dy: 7) }
    func action(for spec: ControlSpec) -> StalkerAction? { ControlsLayout.entry(for: spec).action ?? spec.action }
    func frame(for id: String) -> CGRect? { buttons[id]?.frame }
    func selected(at point: CGPoint) -> String? {
        ControlSpec.all.reversed().first { buttons[$0.id]?.frame.insetBy(dx: -5, dy: -5).contains(point) == true && !(buttons[$0.id]?.isHidden ?? true) }?.id
    }
    func entry(at point: CGPoint, for id: String) -> LayoutEntry? {
        guard let spec = ControlSpec.all.first(where: { $0.id == id }), let frame = buttons[id]?.frame else { return nil }
        let sx = max(1, safe.width), sy = max(1, safe.height)
        var entry = ControlsLayout.entry(for: spec)
        let x = min(safe.maxX - frame.width / 2, max(safe.minX + frame.width / 2, point.x))
        let y = min(safe.maxY - frame.height / 2 - 12, max(safe.minY + frame.height / 2, point.y))
        let nx = (x - safe.minX) / sx
        entry.x = Double(GameSettings.shared.leftHanded ? 1 - nx : nx)
        entry.y = Double((y - safe.minY) / sy)
        return entry
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let baseScale = max(0.72, min(1.2, safe.height / 365))
        for spec in ControlSpec.all {
            guard let button = buttons[spec.id] else { continue }
            let entry = ControlsLayout.entry(for: spec)
            let d = spec.diameter * CGFloat(entry.scale) * baseScale
            let fx = GameSettings.shared.leftHanded ? 1 - CGFloat(entry.x) : CGFloat(entry.x)
            let center = CGPoint(x: min(safe.maxX - d / 2, max(safe.minX + d / 2, safe.minX + fx * safe.width)),
                                 y: min(safe.maxY - d / 2 - 12, max(safe.minY + d / 2, safe.minY + CGFloat(entry.y) * safe.height)))
            button.frame = CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)
            let binding = action(for: spec)
            button.setIcon(binding.flatMap { action in ControlSpec.all.first { $0.action == action }?.id } ?? spec.id)
            captions[spec.id]?.frame = CGRect(x: center.x - d * 0.7, y: button.frame.maxY + 2, width: d * 1.4, height: 13)
            captions[spec.id]?.text = action(for: spec)?.title ?? spec.title
            if spec.id == "move" { stick.idleOrigin = center; stick.baseDiameter = d; stick.travel = d * 0.4 }
        }
        updateAppearance()
    }
    func updateAppearance() {
        for spec in ControlSpec.all {
            guard let button = buttons[spec.id] else { continue }
            let entry = ControlsLayout.entry(for: spec)
            let hidden = !editing && ((entry.hidden && !ControlsLayout.essential.contains(spec.id)) || (spec.utility && !toolsVisible))
            button.isHidden = hidden || (spec.id == "move" && !editing)
            button.alpha = editing ? (entry.hidden ? 0.28 : 0.85) : CGFloat(GameSettings.shared.controlOpacity * entry.opacity)
            button.active = highlighted == spec.id || (action(for: spec) == .aim && aimLatched)
            button.accessibilityLabel = action(for: spec)?.title ?? spec.title
            captions[spec.id]?.isHidden = hidden || (!editing && !GameSettings.shared.showLabels)
            captions[spec.id]?.alpha = button.alpha
        }
        stick.isHidden = editing
        if let move = ControlSpec.all.first(where: { $0.id == "move" }) {
            stick.displayOpacity = CGFloat(GameSettings.shared.controlOpacity * ControlsLayout.entry(for: move).opacity)
        }
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !editing else { return }
        for touch in touches {
            let point = touch.location(in: self)
            if let id = selected(at: point), let spec = ControlSpec.all.first(where: { $0.id == id }), id != "move" {
                if id == "pause" { reset(); onPause?(); return }
                if id == "tools" { toolsVisible.toggle(); fingers[touch] = .utility; continue }
                guard let action = action(for: spec) else { continue }
                if action == .aim && GameSettings.shared.toggleAim {
                    aimLatched.toggle(); InputHub.shared.button(.aim, down: aimLatched, source: "aim-toggle")
                    updateAppearance(); fingers[touch] = .utility
                } else {
                    fingers[touch] = .action(action, id)
                    heldCounts[action, default: 0] += 1; visualCounts[id, default: 0] += 1
                    InputHub.shared.button(action, down: true, source: "touch")
                    buttons[id]?.setPressed(true)
                }
            } else {
                let leftSide = point.x < bounds.midX
                let moveSide = GameSettings.shared.leftHanded ? !leftSide : leftSide
                if moveSide && point.y > safe.minY + safe.height * 0.30 && !fingers.values.contains(where: { if case .move = $0 { return true }; return false }) {
                    fingers[touch] = .move; stick.begin(at: point)
                } else if !fingers.values.contains(where: { if case .look = $0 { return true }; return false }) {
                    fingers[touch] = .look(point)
                }
            }
        }
        onInput?()
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let role = fingers[touch] else { continue }
            let point = touch.location(in: self)
            switch role {
            case .move:
                stick.move(to: point); InputHub.shared.move(stick.value, source: "touch")
            case .look(let last):
                InputHub.shared.look(CGPoint(x: point.x - last.x, y: point.y - last.y)); fingers[touch] = .look(point)
            default: break
            }
        }
        onInput?()
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches) }
    private func finish(_ touches: Set<UITouch>) {
        for touch in touches {
            guard let role = fingers.removeValue(forKey: touch) else { continue }
            switch role {
            case .move: stick.end(); InputHub.shared.move(.zero, source: "touch")
            case .action(let action, let id):
                heldCounts[action] = max(0, (heldCounts[action] ?? 1) - 1)
                visualCounts[id] = max(0, (visualCounts[id] ?? 1) - 1)
                if heldCounts[action] == 0 { InputHub.shared.button(action, down: false, source: "touch") }
                buttons[id]?.setPressed((visualCounts[id] ?? 0) > 0)
            default: break
            }
        }
        onInput?()
    }
    func reset() {
        fingers.removeAll(); heldCounts.removeAll(); visualCounts.removeAll(); aimLatched = false
        InputHub.shared.clear(source: "touch"); InputHub.shared.clear(source: "aim-toggle"); stick.end()
        for button in buttons.values { button.setPressed(false); button.active = false }
    }
}
