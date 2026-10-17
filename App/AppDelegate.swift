import UIKit
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
import ZoneNative
#endif

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = LauncherController(); window.makeKeyAndVisible(); self.window = window
        return true
    }
    func applicationWillResignActive(_ application: UIApplication) {
        InputHub.shared.reset()
        #if ZONE_WITH_ENGINE
        ZEngineSetActive(false)
        #endif
    }
    func applicationDidBecomeActive(_ application: UIApplication) {
        #if ZONE_WITH_ENGINE
        ZEngineSetActive(true)
        #endif
    }
    func applicationDidEnterBackground(_ application: UIApplication) { InputHub.shared.reset() }
}

final class LauncherController: UIViewController, UIDocumentPickerDelegate {
    private let information = UILabel()
    private var home: HomeView!
    private var mode = GameMode.practice
    private var report: GameFilesReport?
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersStatusBarHidden: Bool { true }
    override func loadView() {
        information.textColor = Theme.secondaryText; information.font = Theme.body(15); information.numberOfLines = 0
        information.textAlignment = .center
        home = HomeView(modes: GameMode.allCases.map { ($0.title, $0.symbol) }, log: information)
        view = home
    }
    override func viewDidLoad() {
        super.viewDidLoad(); overrideUserInterfaceStyle = .dark
        home.onFiles = { [weak self] in self?.chooseFiles() }
        home.onMode = { [weak self] index in guard let mode = GameMode(rawValue: index) else { return }; self?.mode = mode; self?.refresh() }
        home.playButton.addAction(UIAction { [weak self] _ in self?.play() }, for: .touchUpInside)
        home.layoutButton.addAction(UIAction { [weak self] _ in
            let editor = ControlsEditorController(); editor.modalPresentationStyle = .fullScreen; self?.present(editor, animated: true)
        }, for: .touchUpInside)
        home.settingsButton.addAction(UIAction { [weak self] _ in
            let navigation = UINavigationController(rootViewController: SettingsController(style: .insetGrouped)); Theme.styleNavigation(navigation)
            self?.present(navigation, animated: true)
        }, for: .touchUpInside)
        home.helpButton.addAction(UIAction { [weak self] _ in self?.help() }, for: .touchUpInside)
        refresh(); scan(GameFiles.saved() ?? GameFiles.documents, remember: false)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if presentedViewController == nil && arguments.contains("--controls-editor") {
            let editor = ControlsEditorController(); editor.modalPresentationStyle = .fullScreen
            present(editor, animated: false)
        } else if presentedViewController == nil && arguments.contains("--controls-practice") {
            let practice = PracticeController(); practice.modalPresentationStyle = .fullScreen
            present(practice, animated: false)
        }
        #endif
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); refresh() }
    private func refresh() {
        home.setMode(mode.rawValue, detail: mode.detail, enabled: true)
        home.playButton.configuration?.title = mode == .practice ? "Try controls" : "Play"
        home.playButton.isEnabled = mode == .practice || (report?.detected == true && ZHostEngineAvailable())
        information.text = mode == .practice ? "Make yourself at home.\n\nTry the controls, then move and resize\nthem until they feel right.\n\nGame files are only needed for gameplay."
            : String(cString: ZHostEngineStatus())
        if let report {
            home.setFiles(report.detected ? .ready : .problem, title: report.detected ? "CoP archives detected" : "Game folder needs attention", detail: report.summary)
        } else { home.setFiles(.attention, title: "Choose your game folder", detail: "Original Call of Pripyat PC installation · GOG or Steam") }
    }
    private func chooseFiles() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder]); picker.delegate = self; present(picker, animated: true)
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { if let url = urls.first { scan(url, remember: true) } }
    private func scan(_ root: URL, remember: Bool) {
        home.setFiles(.busy, title: "Checking game folder…", detail: "Looking for the original PC archives.")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let access = root.startAccessingSecurityScopedResource()
            defer { if access { root.stopAccessingSecurityScopedResource() } }
            let report = GameFiles.find(in: root)
            var error: Error?
            if remember, let report, report.detected { do { try GameFiles.remember(report.root) } catch let caught { error = caught } }
            DispatchQueue.main.async {
                guard let self else { return }; self.report = report; self.refresh()
                if remember && report == nil { self.home.setFiles(.problem, title: "No CoP installation found", detail: "Select the folder containing resources/, levels/ and localization/.") }
                if let error { self.home.setFiles(.problem, title: "Couldn’t remember the folder", detail: error.localizedDescription) }
            }
        }
    }
    private func play() {
        if mode == .campaign {
            #if ZONE_WITH_ENGINE
            guard let report, report.detected, ZHostEngineAvailable() else { return }
            let engine = EngineController(root: report.root); engine.modalPresentationStyle = .fullScreen; present(engine, animated: true)
            #endif
            return
        }
        let practice = PracticeController(); practice.modalPresentationStyle = .fullScreen; present(practice, animated: true)
    }
    private func help() {
        #if ZONE_WITH_ENGINE
        let message = "Choose your installed original Call of Pripyat folder using Game files, then select Call of Pripyat and Play. The GOG installer itself isn’t a game folder.\n\nTap game menus directly. During play, move with your left thumb and swipe the right side to look. Controls opens the layout editor and Settings. A connected controller also works.\n\nThis experimental native build supports one engine session per app launch. Relaunch after exiting the game."
        #else
        let message = "Controls practice works without game files.\n\nMove: left thumb area. Look: swipe the right side. Tap Tools for more actions. Pause opens the editor and Settings.\n\nFor future gameplay, copy your installed original CoP folder into Files → On My iPhone → STALKER Port, or select it with Game files. The GOG installer itself isn’t a game folder.\n\nThis development build does not run CoP yet."
        #endif
        let alert = UIAlertController(title: "Welcome to the Zone", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Got it", style: .default)); present(alert, animated: true)
    }
}
