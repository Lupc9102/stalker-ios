#if ZONE_WITH_ENGINE
import UIKit
import QuartzCore
import OpenGLES
import GameController

private enum EngineFiles {
    // The first native session owns its grant for the app process, matching
    // the native host's process-owned shared heap and file descriptors.
    static var grant: URL?
    static func hold(_ root: URL) { _ = root.startAccessingSecurityScopedResource(); grant = root }
    static func prepare() throws -> URL {
        let manager = FileManager.default
        let overlay = GameFiles.documents.appendingPathComponent("ZonePortData", isDirectory: true)
        try manager.createDirectory(at: overlay, withIntermediateDirectories: true)
        guard let support = Bundle.main.url(forResource: "SupportData", withExtension: nil),
              let files = manager.enumerator(at: support, includingPropertiesForKeys: [.isRegularFileKey]) else {
            throw NSError(domain: "ZonePort", code: 1, userInfo: [NSLocalizedDescriptionKey: "This build is missing its engine support files. Reinstall the native engine build."])
        }
        for case let source as URL in files {
            guard try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let relative = String(source.path.dropFirst(support.path.count + 1))
            let target = overlay.appendingPathComponent(relative)
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contentsOf: source).write(to: target, options: .atomic)
        }
        let settings = overlay.appendingPathComponent("user.ltx")
        if !manager.fileExists(atPath: settings.path) {
            guard let mobile = Bundle.main.url(forResource: "Mobile", withExtension: nil)?.appendingPathComponent("user.ltx") else {
                throw NSError(domain: "ZonePort", code: 2, userInfo: [NSLocalizedDescriptionKey: "The mobile game profile is missing from this build."])
            }
            try Data(contentsOf: mobile).write(to: settings, options: .atomic)
        }
        return overlay
    }
}

private final class EngineSurface: UIView {
    override class var layerClass: AnyClass { CAEAGLLayer.self }
    var gameSize = CGSize(width: 1280, height: 720)
    private var finger: UITouch?
    private var lastPoint = CGPoint.zero
    private var pressTask: DispatchWorkItem?, releaseTask: DispatchWorkItem?
    private var isDown = false
    var gameRect: CGRect {
        guard bounds.width > 0, bounds.height > 0, gameSize.width > 0, gameSize.height > 0 else { return bounds }
        let scale = min(bounds.width / gameSize.width, bounds.height / gameSize.height)
        let size = CGSize(width: gameSize.width * scale, height: gameSize.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }
    override init(frame: CGRect) {
        super.init(frame: frame); isOpaque = true; backgroundColor = .black
        contentScaleFactor = UIScreen.main.scale
        let drawable = layer as! CAEAGLLayer; drawable.isOpaque = true
        drawable.drawableProperties = [kEAGLDrawablePropertyRetainedBacking: false, kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    private func send(_ point: CGPoint, down: Bool) {
        lastPoint = point; let rect = gameRect
        guard rect.width > 0, rect.height > 0 else { return }
        ZEnginePointer(Float((point.x - rect.minX) / rect.width), Float((point.y - rect.minY) / rect.height), down)
    }
    func reset() {
        pressTask?.cancel(); releaseTask?.cancel(); pressTask = nil; releaseTask = nil
        if finger != nil || isDown { send(lastPoint, down: false) }; finger = nil; isDown = false
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard finger == nil, pressTask == nil, !isDown, let touch = touches.first, gameRect.contains(touch.location(in: self)) else { return }
        finger = touch; send(touch.location(in: self), down: false)
        // CoP's moving menu selector accepts a press only after reaching the
        // hovered row (100–300 ms). Touch has no preceding mouse hover, so
        // supply that hover before clicking. Gameplay thumb buttons bypass
        // this surface and retain their immediate press/release behavior.
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }; self.pressTask = nil
            guard UIApplication.shared.applicationState == .active, self.window != nil else { self.reset(); return }
            self.isDown = true; self.send(self.lastPoint, down: true)
            if self.finger == nil {
                let release = DispatchWorkItem { [weak self] in
                    guard let self else { return }; self.releaseTask = nil
                    self.send(self.lastPoint, down: false); self.isDown = false
                }
                self.releaseTask = release; DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: release)
            }
        }
        pressTask = task; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: task)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let finger, touches.contains(finger) { send(finger.location(in: self), down: isDown) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let finger, touches.contains(finger) {
            send(finger.location(in: self), down: false); self.finger = nil
            if isDown { isDown = false }
        }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { reset() }
}

final class EngineController: UIViewController {
    private let root: URL
    private let surface = EngineSurface(frame: .zero)
    private let controls = TouchControlsView(frame: .zero)
    private let information = UILabel()
    private var loading: UIView!
    private var displayLink: CADisplayLink?
    private var started = false, finished = false, lastMenu = true
    private var gameplayControls = false
    private var lastTime: CFTimeInterval = 0
    private var padPoint = CGPoint(x: 0.5, y: 0.5)
    private var openGameMenuWhenReady = false, inputSuppressed = false
    private var overlayToStart: URL?
    private var observers: [NSObjectProtocol] = []
    #if DEBUG
    private var smokeTicks = 0
    private func reportSmoke(_ info: ZEngineInfo) {
        guard ProcessInfo.processInfo.arguments.contains("--engine-smoke-test") else { return }
        smokeTicks += 1; guard smokeTicks % 15 == 0 else { return }
        let report: [String: Any] = ["phase": Int(info.phase), "frames": info.frames, "width": info.width, "height": info.height, "cursor": info.cursor, "status": engineStatus()]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
            try? data.write(to: GameFiles.documents.appendingPathComponent("engine-smoke.json"), options: .atomic)
        }
    }
    #endif
    init(root: URL) { self.root = root; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        surface.frame = view.bounds; surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]; view.addSubview(surface)
        controls.frame = view.bounds; controls.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controls.onPause = { [weak self] in self?.pause() }; controls.isHidden = true; view.addSubview(controls)
        loading = Theme.dimmedBackdrop(image: "ZoneBackdrop"); loading.frame = view.bounds
        loading.autoresizingMask = [.flexibleWidth, .flexibleHeight]; loading.isUserInteractionEnabled = false; view.addSubview(loading)
        information.text = "Preparing the engine…"; information.font = Theme.body(18, .medium)
        information.textColor = .white; information.textAlignment = .center; information.numberOfLines = 0
        information.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(information)
        let menu = UIButton(type: .system); menu.setTitle("  Controls", for: .normal)
        menu.setImage(UIImage(systemName: "slider.horizontal.3"), for: .normal); menu.tintColor = .white
        menu.backgroundColor = UIColor.black.withAlphaComponent(0.65); menu.layer.cornerRadius = 16
        menu.accessibilityLabel = "Game menu and controls"; menu.translatesAutoresizingMaskIntoConstraints = false
        menu.addAction(UIAction { [weak self] _ in self?.pause() }, for: .touchUpInside); view.addSubview(menu)
        NSLayoutConstraint.activate([
            information.centerXAnchor.constraint(equalTo: view.centerXAnchor), information.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            information.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.7),
            menu.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            menu.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            menu.widthAnchor.constraint(equalToConstant: 115), menu.heightAnchor.constraint(equalToConstant: 34)
        ])
        for name in [UIApplication.willResignActiveNotification, Notification.Name.GCControllerDidDisconnect] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.reset() })
        }
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); ZEngineSetPaused(false)
        displayLink?.invalidate(); lastTime = 0
        let link = CADisplayLink(target: self, selector: #selector(tick(_:))); link.add(to: .main, forMode: .common); displayLink = link
        guard !started else { return }; started = true; EngineFiles.hold(root)
        information.text = "Preparing shaders and mobile settings…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let overlay = try EngineFiles.prepare()
                DispatchQueue.main.async { [weak self] in self?.start(overlay: overlay) }
            } catch { DispatchQueue.main.async { [weak self] in self?.showFailure(error.localizedDescription) } }
        }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated); reset(); ZEngineSetPaused(true); displayLink?.invalidate(); displayLink = nil
    }
    deinit { displayLink?.invalidate(); for observer in observers { NotificationCenter.default.removeObserver(observer) } }
    private func start(overlay: URL) {
        guard UIApplication.shared.applicationState == .active, view.window != nil else { overlayToStart = overlay; return }
        let rect = surface.gameRect
        let success = root.path.withCString { game in overlay.path.withCString { data in
            ZEngineStart(Unmanaged.passUnretained(surface.layer).toOpaque(), game, data, Double(rect.width), Double(rect.height))
        } }
        if !success { showFailure("The native engine could not start. Relaunch the app and try again.") }
    }
    private func reset() { controls.reset(); surface.reset(); InputHub.shared.reset() }
    private func resume() { reset(); controls.setNeedsLayout(); ZEngineSetPaused(false) }
    private func engineStatus() -> String {
        var bytes = [CChar](repeating: 0, count: 256)
        bytes.withUnsafeMutableBufferPointer { ZEngineCopyStatus($0.baseAddress, $0.count) }
        return String(cString: bytes)
    }
    @objc private func tick(_ link: CADisplayLink) {
        let dt = lastTime == 0 ? 1.0 / 60 : min(0.05, link.timestamp - lastTime); lastTime = link.timestamp
        let info = ZEngineGetInfo()
        #if DEBUG
        reportSmoke(info)
        #endif
        if let overlay = overlayToStart, UIApplication.shared.applicationState == .active, presentedViewController == nil {
            overlayToStart = nil; start(overlay: overlay)
        }
        if info.width > 0 && info.height > 0 { surface.gameSize = CGSize(width: CGFloat(info.width), height: CGFloat(info.height)) }
        let rect = surface.gameRect; ZEngineSetViewSize(Double(rect.width), Double(rect.height))
        if info.phase == ZEngineFailed || info.phase == ZEngineEnded {
            if !finished && presentedViewController == nil { showFailure(engineStatus()) }; return
        }
        if info.phase != ZEngineIdle { information.text = engineStatus() }
        let ready = info.frames >= 30
        loading.isHidden = ready; information.isHidden = ready
        // CoP draws its own UI cursor and can hide the system cursor while
        // its menus are open. Let the player select the touch mode explicitly.
        let menu = !gameplayControls || !ready
        if menu != lastMenu { reset(); lastMenu = menu }
        controls.isHidden = menu
        if UIApplication.shared.applicationState != .active || presentedViewController != nil {
            if !inputSuppressed { reset(); inputSuppressed = true }; return
        }
        inputSuppressed = false
        if openGameMenuWhenReady {
            openGameMenuWhenReady = false
            InputHub.shared.button(.pause, down: true, source: "menu"); InputHub.shared.button(.pause, down: false, source: "menu")
        }
        pollController(dt: dt, menu: menu)
    }
    private func pollController(dt: Double, menu: Bool) {
        guard let pad = GCController.controllers().first?.extendedGamepad else { InputHub.shared.clear(source: "controller"); return }
        pad.buttonMenu.pressedChangedHandler = { [weak self] _, _, down in if down { DispatchQueue.main.async { self?.pause() } } }
        if menu {
            padPoint.x = min(1, max(0, padPoint.x + CGFloat(pad.leftThumbstick.xAxis.value) * CGFloat(dt)))
            padPoint.y = min(1, max(0, padPoint.y - CGFloat(pad.leftThumbstick.yAxis.value) * CGFloat(dt)))
            ZEnginePointer(Float(padPoint.x), Float(padPoint.y), pad.buttonA.isPressed)
            InputHub.shared.button(.pause, down: pad.buttonB.isPressed, source: "controller"); return
        }
        InputHub.shared.move(CGPoint(x: CGFloat(pad.leftThumbstick.xAxis.value), y: CGFloat(pad.leftThumbstick.yAxis.value)), source: "controller")
        InputHub.shared.look(CGPoint(x: CGFloat(pad.rightThumbstick.xAxis.value) * 240 * CGFloat(dt), y: -CGFloat(pad.rightThumbstick.yAxis.value) * 240 * CGFloat(dt)))
        let mapping: [(GCControllerButtonInput?, StalkerAction)] = [
            (pad.rightTrigger, .fire), (pad.leftTrigger, .aim), (pad.buttonA, .jump), (pad.buttonB, .crouch),
            (pad.buttonX, .reload), (pad.buttonY, .use), (pad.leftShoulder, .weaponNext), (pad.rightShoulder, .detector),
            (pad.buttonOptions, .inventory), (pad.dpad.up, .pda), (pad.dpad.down, .torch),
            (pad.dpad.left, .medkit), (pad.dpad.right, .bandage), (pad.leftThumbstickButton, .sprint)
        ]
        for (button, action) in mapping { InputHub.shared.button(action, down: button?.isPressed == true, source: "controller") }
    }
    private func pause() {
        guard presentedViewController == nil, !finished else { return }; reset(); ZEngineSetPaused(true)
        let alert = UIAlertController(title: "Game controls", message: "Tap game menus directly. Once a level has loaded, choose Show game controls for movement and aiming. Choose Use game menus when you need to tap a menu.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Resume", style: .cancel) { [weak self] _ in self?.resume() })
        alert.addAction(UIAlertAction(title: gameplayControls ? "Use game menus" : "Show game controls", style: .default) { [weak self] _ in
            guard let self else { return }; self.gameplayControls.toggle(); self.resume()
        })
        alert.addAction(UIAlertAction(title: "Game menu", style: .default) { [weak self] _ in
            self?.gameplayControls = false; self?.openGameMenuWhenReady = true; self?.resume()
        })
        alert.addAction(UIAlertAction(title: "Edit controls", style: .default) { [weak self] _ in
            guard let self else { return }; let editor = ControlsEditorController(); editor.modalPresentationStyle = .fullScreen
            editor.onDone = { [weak self] in self?.controls.setNeedsLayout() }; self.present(editor, animated: true)
        })
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { [weak self] _ in
            guard let self else { return }; let settings = SettingsController(style: .insetGrouped)
            settings.onChange = { [weak self] in self?.controls.setNeedsLayout() }
            let navigation = UINavigationController(rootViewController: settings); navigation.modalPresentationStyle = .fullScreen
            Theme.styleNavigation(navigation); self.present(navigation, animated: true)
        })
        present(alert, animated: true)
    }
    private func showFailure(_ message: String) {
        guard !finished else { return }; finished = true; reset(); ZEngineStop()
        information.isHidden = false; information.text = message
        let alert = UIAlertController(title: "Engine stopped", message: message + "\n\nEngine logs are in Files → ZonePortData → _appdata_ → logs. This build supports one engine session per app launch.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Back to launcher", style: .default) { [weak self] _ in self?.dismiss(animated: true) })
        present(alert, animated: true)
    }
}
#endif
