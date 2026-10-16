import UIKit

final class SettingsController: UITableViewController {
    var onChange: (() -> Void)?
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Settings"
        tableView.backgroundView = Theme.dimmedBackdrop(image: "ZoneBackdrop")
        tableView.backgroundColor = .clear
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 6 : 1 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { section == 0 ? "Touch controls" : "About" }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 ? "Swipe an empty area on the right to look. Use the left thumb area to move. Open Tools for the detector, healing and leaning. Bluetooth controllers are supported in controls practice."
            : "Early development build. Engine translation is separate from a working game runtime. Original CoP PC files required for future gameplay; Enhanced Edition and Anomaly are not supported yet."
    }
    override func tableView(_ tableView: UITableView, cellForRowAt path: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.backgroundColor = Theme.rowBackground; cell.textLabel?.textColor = Theme.text
        cell.selectionStyle = .none
        guard path.section == 0 else { cell.textLabel?.text = "S.T.A.L.K.E.R. · \(Theme.appVersion)"; return cell }
        let settings = GameSettings.shared
        if path.row < 3 {
            let titles = ["Show button labels", "Tap to toggle aim", "Left-handed layout"]
            let values = [settings.showLabels, settings.toggleAim, settings.leftHanded]
            cell.textLabel?.text = titles[path.row]
            let toggle = UISwitch(); toggle.isOn = values[path.row]
            toggle.addAction(UIAction { [weak self, weak toggle] _ in
                guard let toggle else { return }
                switch path.row {
                case 0: settings.showLabels = toggle.isOn
                case 1: settings.toggleAim = toggle.isOn
                default: settings.leftHanded = toggle.isOn
                }
                self?.onChange?()
            }, for: .valueChanged)
            cell.accessoryView = toggle
        } else if path.row < 5 {
            let sensitivity = path.row == 3
            cell.textLabel?.text = sensitivity ? "Look sensitivity" : "Controls opacity"
            let slider = UISlider(frame: CGRect(x: 0, y: 0, width: 175, height: 32))
            slider.minimumValue = sensitivity ? 0.2 : 0.2; slider.maximumValue = sensitivity ? 3 : 1
            slider.value = Float(sensitivity ? settings.lookSensitivity : settings.controlOpacity)
            slider.accessibilityLabel = cell.textLabel?.text
            slider.addAction(UIAction { [weak self, weak slider] _ in
                guard let slider else { return }
                if sensitivity { settings.lookSensitivity = Double(slider.value) } else { settings.controlOpacity = Double(slider.value) }
                self?.onChange?()
            }, for: .valueChanged)
            cell.accessoryView = slider
        } else {
            cell.textLabel?.text = "Edit controls layout"; cell.accessoryType = .disclosureIndicator; cell.selectionStyle = .default
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt path: IndexPath) {
        tableView.deselectRow(at: path, animated: true)
        guard path.section == 0 && path.row == 5 else { return }
        let editor = ControlsEditorController(); editor.modalPresentationStyle = .fullScreen; editor.onDone = onChange; present(editor, animated: true)
    }
}
