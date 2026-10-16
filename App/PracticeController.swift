import UIKit
import GameController
#if SWIFT_PACKAGE
import ZoneNative
#endif

final class PracticeController: UIViewController {
    private let controls = TouchControlsView(frame: .zero)
    private let status = UILabel()
    private var displayLink: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var observers: [NSObjectProtocol] = []
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override func viewDidLoad() {
        super.viewDidLoad()
        let background = Theme.dimmedBackdrop(image: "ZoneBackdrop"); background.frame = view.bounds
        background.autoresizingMask = [.flexibleWidth, .flexibleHeight]; view.addSubview(background)
        status.textAlignment = .center; status.textColor = .white; status.numberOfLines = 0; status.font = Theme.body(14, .medium)
        status.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(status)
        let crosshair = UIImageView(image: UIImage(systemName: "plus")); crosshair.tintColor = Theme.accent
        crosshair.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(crosshair)
        NSLayoutConstraint.activate([
            crosshair.centerXAnchor.constraint(equalTo: view.centerXAnchor), crosshair.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            crosshair.widthAnchor.constraint(equalToConstant: 22), crosshair.heightAnchor.constraint(equalToConstant: 22),
            status.centerXAnchor.constraint(equalTo: view.centerXAnchor), status.topAnchor.constraint(equalTo: crosshair.bottomAnchor, constant: 12),
            status.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.55)
        ])
        controls.frame = view.bounds; controls.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controls.onPause = { [weak self] in self?.pause() }; view.addSubview(controls)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.reset() })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in self?.reset() })
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        displayLink?.invalidate(); lastTime = 0
        let link = CADisplayLink(target: self, selector: #selector(tick(_:))); link.add(to: .main, forMode: .common); displayLink = link
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); displayLink?.invalidate(); displayLink = nil; reset() }
    deinit { displayLink?.invalidate(); for observer in observers { NotificationCenter.default.removeObserver(observer) } }
    private func reset() { controls.reset(); InputHub.shared.reset() }
    @objc private func tick(_ link: CADisplayLink) {
        let dt = lastTime == 0 ? 1.0 / 60 : min(0.05, link.timestamp - lastTime); lastTime = link.timestamp
        if UIApplication.shared.applicationState != .active { reset(); return }
        if presentedViewController != nil { reset(); return }
        let pad = GCController.controllers().first?.extendedGamepad
        if let pad {
            InputHub.shared.move(CGPoint(x: CGFloat(pad.leftThumbstick.xAxis.value), y: CGFloat(pad.leftThumbstick.yAxis.value)), source: "controller")
            InputHub.shared.look(CGPoint(x: CGFloat(pad.rightThumbstick.xAxis.value) * 240 * CGFloat(dt), y: -CGFloat(pad.rightThumbstick.yAxis.value) * 240 * CGFloat(dt)))
            let mapping: [(GCControllerButtonInput?, StalkerAction)] = [
                (pad.rightTrigger, .fire), (pad.leftTrigger, .aim), (pad.buttonA, .jump), (pad.buttonB, .crouch),
                (pad.buttonX, .reload), (pad.buttonY, .use), (pad.leftShoulder, .weaponNext), (pad.rightShoulder, .detector),
                (pad.buttonOptions, .inventory), (pad.dpad.up, .pda), (pad.dpad.down, .torch),
                (pad.dpad.left, .medkit), (pad.dpad.right, .bandage), (pad.leftThumbstickButton, .sprint)
            ]
            for (button, action) in mapping { InputHub.shared.button(action, down: button?.isPressed == true, source: "controller") }
            pad.buttonMenu.pressedChangedHandler = { [weak self] _, _, down in if down { DispatchQueue.main.async { self?.pause() } } }
        } else { InputHub.shared.clear(source: "controller") }
        let input = ZHostReadInput()
        // Drain the edge queue in practice; the engine adapter will own it in gameplay.
        var edge = ZButtonEvent(); while ZHostPollButton(&edge) {}
        let pressed = StalkerAction.allCases.filter { input.held & (UInt64(1) << $0.rawValue) != 0 }.map(\.title)
        status.text = "CONTROLS PRACTICE\n" + (pressed.isEmpty ? "Move with your left thumb · swipe to look" : pressed.joined(separator: " · "))
            + String(format: "\nMove %.2f, %.2f   Look %.0f, %.0f", input.move_x, input.move_y, input.look_x, input.look_y)
    }
    private func pause() {
        guard presentedViewController == nil else { return }; reset()
        let alert = UIAlertController(title: "Controls practice", message: "This screen tests input; the game engine is not running.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Resume", style: .cancel))
        alert.addAction(UIAlertAction(title: "Edit controls", style: .default) { [weak self] _ in
            let editor = ControlsEditorController(); editor.modalPresentationStyle = .fullScreen
            editor.onDone = { [weak self] in self?.controls.setNeedsLayout() }; self?.present(editor, animated: true)
        })
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { [weak self] _ in
            let settings = SettingsController(style: .insetGrouped); settings.onChange = { [weak self] in self?.controls.reset(); self?.controls.setNeedsLayout() }
            let navigation = UINavigationController(rootViewController: settings); Theme.styleNavigation(navigation); self?.present(navigation, animated: true)
        })
        alert.addAction(UIAlertAction(title: "Back to launcher", style: .destructive) { [weak self] _ in self?.dismiss(animated: true) })
        present(alert, animated: true)
    }
}
