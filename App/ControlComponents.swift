import UIKit

// Adapted from GTA V iOS Port (MIT); see Licenses/GTA-iOS-MIT.txt.
final class ControlButton: UIView {
    let name: String
    var isPedal = false
    /// A finger already down may slide onto this control (pedals).
    var slideTarget = false
    private let icon = UIImageView()
    private let halo = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let progress = CAShapeLayer()
    private(set) var pressed = false
    var active = false { didSet { if active != oldValue { updateAppearance() } } }

    init(_ name: String, icon iconName: String, label: String) {
        self.name = name
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityLabel = label
        accessibilityTraits = .button
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 6
        layer.shadowOffset = .zero
        for shape in [halo, ring, progress] { shape.fillColor = nil; layer.addSublayer(shape) }
        halo.strokeColor = UIColor.white.withAlphaComponent(0.35).cgColor
        halo.lineWidth = 2
        halo.opacity = 0
        ring.strokeColor = ControlStyle.accent.cgColor
        ring.lineWidth = 2.5
        progress.strokeColor = UIColor.white.withAlphaComponent(0.9).cgColor
        progress.lineWidth = 3
        progress.lineCap = .round
        progress.strokeEnd = 0
        icon.contentMode = .scaleAspectFit
        addSubview(icon)
        setIcon(iconName)
        updateAppearance()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setIcon(_ iconName: String) {
        let image = UIImage(named: "icon_" + iconName)
            ?? UIImage(systemName: ControlStyle.fallbackSymbol[iconName] ?? "circle", withConfiguration: UIImage.SymbolConfiguration(weight: .bold))
            ?? UIImage(systemName: ControlStyle.olderSymbol[iconName] ?? "circle", withConfiguration: UIImage.SymbolConfiguration(weight: .bold))
        icon.image = image?.withRenderingMode(.alwaysTemplate)
    }

    private var cornerRadius: CGFloat { isPedal ? 18 : bounds.width / 2 }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = cornerRadius
        let side = min(bounds.width, bounds.height) * 0.56
        icon.bounds.size = CGSize(width: side, height: side)
        icon.center = CGPoint(x: bounds.midX, y: bounds.midY)
        let path = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath
        halo.path = UIBezierPath(roundedRect: bounds.insetBy(dx: -5, dy: -5), cornerRadius: cornerRadius + 5).cgPath
        ring.path = path
        progress.path = path
        layer.shadowPath = path
    }

    private func updateAppearance() {
        let base = UIColor.black.withAlphaComponent(UIAccessibility.isReduceTransparencyEnabled ? 0.7 : 0.3)
        backgroundColor = pressed ? UIColor.white.withAlphaComponent(0.85) : base
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(pressed ? 0.9 : 0.28).cgColor
        icon.tintColor = pressed ? UIColor.black.withAlphaComponent(0.9) : UIColor.white.withAlphaComponent(0.92)
        ring.opacity = active && !pressed ? 1 : 0
        accessibilityValue = pressed ? AppLanguage.choose("Held") : active ? AppLanguage.choose("On") : nil
    }

    func setPressed(_ value: Bool) {
        guard value != pressed else { return }
        pressed = value
        updateAppearance()
        let reduce = UIAccessibility.isReduceMotionEnabled
        UIView.animate(withDuration: reduce ? 0 : 0.12, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.transform = value && !reduce ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity
        }
        if value {
            halo.removeAllAnimations(); halo.opacity = 1
        } else {
            let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 1; fade.toValue = 0; fade.duration = 0.2
            halo.add(fade, forKey: "fade"); halo.opacity = 0
        }
    }

    /// 0...1 ring around the edge, e.g. hold-to-exit in the air.
    func setProgress(_ value: CGFloat) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        progress.strokeEnd = max(0, min(1, value))
        CATransaction.commit()
    }

    func contains(point: CGPoint, slop: CGFloat) -> Bool {
        frame.insetBy(dx: -slop, dy: -slop).contains(point)
    }
}

final class FloatingStick: UIView {
    private let base = UIView()
    private let knob = UIView()
    private let sprintHalo = UIView()
    var baseDiameter: CGFloat = 120
    var travel: CGFloat = 48
    private(set) var origin = CGPoint.zero
    private(set) var value = CGPoint.zero
    private var engaged = false
    var idleOrigin: CGPoint? { didSet { if !engaged { showIdle() } } }
    private func showIdle() {
        if let idleOrigin { origin = idleOrigin; layoutParts(); alpha = 0.55 }
        else { alpha = 0 }
    }
    var sprinting = false { didSet { if sprinting != oldValue { sprintHalo.alpha = sprinting ? 1 : 0 } } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        for view in [sprintHalo, base, knob] { addSubview(view) }
        base.layer.borderWidth = 2
        base.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        base.backgroundColor = UIColor.black.withAlphaComponent(0.12)
        sprintHalo.layer.borderWidth = 3
        sprintHalo.layer.borderColor = ControlStyle.accent.withAlphaComponent(0.85).cgColor
        sprintHalo.alpha = 0
        knob.backgroundColor = UIColor.white.withAlphaComponent(0.45)
        knob.layer.shadowColor = UIColor.black.cgColor
        knob.layer.shadowOpacity = 0.25
        knob.layer.shadowRadius = 6
        alpha = 0
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func begin(at point: CGPoint) {
        engaged = true
        origin = point
        value = .zero
        layoutParts()
        UIView.animate(withDuration: 0.08) { self.alpha = 1 }
    }
    /// The base stays where the thumb landed until it lifts; dragging past
    /// the edge holds full deflection in that direction.
    func move(to point: CGPoint, horizontalOnly: Bool = false) {
        let dx = point.x - origin.x, dy = horizontalOnly ? 0 : point.y - origin.y
        let length = max(1, hypot(dx, dy) / travel)
        value = CGPoint(x: dx / travel / length, y: -dy / travel / length)
        layoutParts()
    }
    func end() {
        engaged = false
        value = .zero
        sprinting = false
        UIView.animate(withDuration: 0.15) { self.showIdle() }
    }
    private func layoutParts() {
        base.bounds.size = CGSize(width: baseDiameter, height: baseDiameter)
        base.layer.cornerRadius = baseDiameter / 2
        base.center = origin
        sprintHalo.bounds.size = CGSize(width: baseDiameter + 12, height: baseDiameter + 12)
        sprintHalo.layer.cornerRadius = (baseDiameter + 12) / 2
        sprintHalo.center = origin
        let knobSize = baseDiameter * 0.43
        knob.bounds.size = CGSize(width: knobSize, height: knobSize)
        knob.layer.cornerRadius = knobSize / 2
        knob.center = CGPoint(x: origin.x + value.x * travel, y: origin.y - value.y * travel)
    }
}
