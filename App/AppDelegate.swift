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
    private var scanGeneration = 0
    private var localFolderError: String?
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
        home.onFiles = { [weak self] in self?.showGameFiles() }
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
        do { try GameFiles.prepareLocalFolder() } catch { localFolderError = error.localizedDescription }
        NotificationCenter.default.addObserver(self, selector: #selector(rescanAfterFiles),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        refresh()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        #if DEBUG || ZONE_SIMULATOR_TESTS
        let arguments = ProcessInfo.processInfo.arguments
        if presentedViewController == nil && arguments.contains("--controls-editor") {
            let editor = ControlsEditorController(); editor.modalPresentationStyle = .fullScreen
            present(editor, animated: false)
        } else if presentedViewController == nil && arguments.contains("--controls-practice") {
            let practice = PracticeController(); practice.modalPresentationStyle = .fullScreen
            present(practice, animated: false)
        }
        #if ZONE_WITH_ENGINE
        if presentedViewController == nil && arguments.contains("--engine-smoke-test") && ZEngineCanStart() {
            let engine = EngineController(root: GameFiles.documents.appendingPathComponent("Benchmark", isDirectory: true))
            engine.modalPresentationStyle = .fullScreen; present(engine, animated: false)
        }
        #endif
        #endif
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); scanPreferredFiles() }
    @objc private func rescanAfterFiles() {
        // Never scan or change engine state while gameplay is presented.
        guard presentedViewController == nil || presentedViewController is UIAlertController else { return }
        scanPreferredFiles()
    }
    private func refresh() {
        home.setMode(mode.rawValue, detail: mode.detail, enabled: true)
        home.playButton.configuration?.title = mode == .practice ? "Try controls" : "Play"
        home.playButton.isEnabled = mode == .practice || (report?.detected == true && ZHostEngineAvailable())
        information.text = mode == .practice ? "Make yourself at home.\n\nTry the controls, then move and resize\nthem until they feel right.\n\nGame files are only needed for gameplay."
            : String(cString: ZHostEngineStatus())
        if let report {
            home.setFiles(report.detected ? .ready : .problem, title: report.detected ? "CoP archives detected" : "Game folder needs attention", detail: report.summary)
        } else if let localFolderError {
            home.setFiles(.problem, title: "Couldn’t create the game folder", detail: localFolderError)
        } else {
            home.setFiles(.attention, title: "Move your game into Files", detail: "On My iPhone → ZonePort → GameFiles\nAdd the extracted CoP-Mobile folder, then return here.")
        }
    }
    private func showGameFiles() {
        let alert = UIAlertController(title: "Add your game in Files", message:
            "Open Files → On My iPhone → ZonePort → GameFiles. Move the extracted CoP-Mobile folder there, then return to this app. Your files are detected automatically.\n\nWait for the full copy to finish. Keep resources, levels, gamedata and zone-mobile-profile.json together.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Check again", style: .default) { [weak self] _ in self?.scanPreferredFiles() })
        alert.addAction(UIAlertAction(title: "Choose another folder…", style: .default) { [weak self] _ in self?.chooseFiles() })
        alert.addAction(UIAlertAction(title: "Done", style: .cancel))
        present(alert, animated: true)
    }
    private func chooseFiles() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false; picker.delegate = self
        present(picker, animated: true)
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { if let url = urls.first { scan(url, remember: true) } }
    private func scanPreferredFiles() { scan(nil, remember: false) }
    private func scan(_ root: URL?, remember: Bool) {
        scanGeneration += 1
        let generation = scanGeneration
        home.setFiles(.busy, title: "Checking game folder…", detail: "Looking for the original PC archives.")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // The local Documents folder needs no file-provider callback or
            // security-scoped permission. A saved external folder is optional.
            let local = root == nil ? GameFiles.findLocal() : nil
            let selected = root ?? (local?.detected == true ? nil : GameFiles.saved())
            let access = selected?.startAccessingSecurityScopedResource() ?? false
            defer { if access { selected?.stopAccessingSecurityScopedResource() } }
            let report = selected.flatMap { GameFiles.find(in: $0) } ?? local
            var error: Error?
            if remember, let report, report.detected { do { try GameFiles.remember(report.root) } catch let caught { error = caught } }
            DispatchQueue.main.async {
                guard let self, self.scanGeneration == generation else { return }
                if self.report?.detected != true && report?.detected == true { self.mode = .campaign }
                self.report = report; self.refresh()
                #if DEBUG || ZONE_SIMULATOR_TESTS
                if ProcessInfo.processInfo.arguments.contains("--files-smoke-test") {
                    let state: [String: Any] = ["ready": report?.detected == true,
                        "root": report?.root.path ?? "", "archives": report?.archiveCount ?? 0,
                        "playEnabled": self.home.playButton.isEnabled, "generation": generation]
                    if let data = try? JSONSerialization.data(withJSONObject: state) {
                        try? data.write(to: GameFiles.documents.appendingPathComponent("local-files-smoke.json"), options: .atomic)
                    }
                }
                #endif
                if remember && report == nil { self.home.setFiles(.problem, title: "No CoP installation found", detail: "Move the extracted CoP-Mobile folder into Files → On My iPhone → ZonePort → GameFiles instead.") }
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
        let message = "In Files, move your extracted CoP-Mobile folder into On My iPhone → ZonePort → GameFiles. Return here and the app detects it automatically. Tap Play once the full copy finishes. The ZIP or GOG installer itself isn’t a game folder.\n\nTap game menus directly. After a level loads, open Controls → Show game controls. Move with your left thumb and swipe the right side to look. Controls → Use game menus lets you tap menus again. You can also edit the layout, change Settings, or use a controller.\n\nThis experimental native build supports one engine session per app launch. Relaunch after exiting the game."
        #else
        let message = "Controls practice works without game files.\n\nMove: left thumb area. Look: swipe the right side. Tap Tools for more actions. Pause opens the editor and Settings.\n\nMove your extracted CoP-Mobile folder into Files → On My iPhone → ZonePort → GameFiles, then return here for automatic detection.\n\nThis controls-only build does not run CoP."
        #endif
        let alert = UIAlertController(title: "Welcome to the Zone", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Got it", style: .default)); present(alert, animated: true)
    }
}
