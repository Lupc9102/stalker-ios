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
        window.rootViewController = LauncherController(); window.makeKeyAndVisible(); self.window = window
        return true
    }
    func applicationWillResignActive(_ application: UIApplication) { InputHub.shared.reset() }
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
        guard mode == .practice else { return }
        let practice = PracticeController(); practice.modalPresentationStyle = .fullScreen; present(practice, animated: true)
    }
    private func help() {
        let alert = UIAlertController(title: "Welcome to the Zone", message: "Controls practice works without game files.\n\nMove: left thumb area. Look: swipe the right side. Tap Tools for more actions. Pause opens the editor and Settings.\n\nFor future gameplay, copy your installed original CoP folder into Files → On My iPhone → STALKER Port, or select it with Game files. The GOG installer itself isn’t a game folder.\n\nThis development build does not run CoP yet.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Got it", style: .default)); present(alert, animated: true)
    }
}
