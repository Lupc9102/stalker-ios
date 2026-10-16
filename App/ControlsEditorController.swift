import UIKit
import UniformTypeIdentifiers

final class ControlsEditorController: UIViewController, UIGestureRecognizerDelegate, UIDocumentPickerDelegate {
    var onDone: (() -> Void)?
    private let controls = TouchControlsView(frame: .zero)
    private let toolbar = UIStackView()
    private let hint = UILabel()
    private let size = UISlider(), opacity = UISlider()
    private let hide = UIButton(type: .system), binding = UIButton(type: .system)
    private let profiles = UISegmentedControl(items: ControlsLayout.profiles)
    private var selected: String? { didSet { refresh() } }
    private var offset = CGPoint.zero, pinchScale = 1.0
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override func viewDidLoad() {
        super.viewDidLoad()
        let background = Theme.dimmedBackdrop(image: "ZoneBackdrop"); background.frame = view.bounds
        background.autoresizingMask = [.flexibleWidth, .flexibleHeight]; view.addSubview(background)
        controls.frame = view.bounds; controls.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controls.editing = true; controls.toolsVisible = true; controls.isUserInteractionEnabled = false; view.addSubview(controls)
        hint.font = Theme.body(13, .semibold); hint.textColor = .white
        hint.textAlignment = .center; hint.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(hint)
        profiles.selectedSegmentIndex = ControlsLayout.profile
        profiles.addAction(UIAction { [weak self] _ in
            guard let self else { return }; ControlsLayout.profile = self.profiles.selectedSegmentIndex
            self.selected = nil; self.controls.setNeedsLayout()
        }, for: .valueChanged)
        size.minimumValue = 0.6; size.maximumValue = 1.8; size.accessibilityLabel = "Button size"
        opacity.minimumValue = 0.2; opacity.maximumValue = 1; opacity.accessibilityLabel = "Button opacity"
        for slider in [size, opacity] {
            slider.widthAnchor.constraint(equalToConstant: 85).isActive = true
            slider.addAction(UIAction { [weak self] _ in self?.changed() }, for: .valueChanged)
        }
        hide.addAction(UIAction { [weak self] _ in self?.toggleHidden() }, for: .touchUpInside)
        binding.showsMenuAsPrimaryAction = true
        let more = UIButton(type: .system); more.setTitle("More", for: .normal); more.showsMenuAsPrimaryAction = true
        more.menu = UIMenu(children: [
            UIAction(title: "Export layout", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in self?.exportLayout() },
            UIAction(title: "Import layout", image: UIImage(systemName: "square.and.arrow.down")) { [weak self] _ in self?.importLayout() },
            UIAction(title: "Reset this layout", image: UIImage(systemName: "arrow.counterclockwise"), attributes: .destructive) { [weak self] _ in self?.resetLayout() }
        ])
        let done = UIButton(type: .system); done.setTitle("Done", for: .normal)
        done.titleLabel?.font = Theme.body(15, .bold)
        done.addAction(UIAction { [weak self] _ in self?.onDone?(); self?.dismiss(animated: true) }, for: .touchUpInside)
        let sizeLabel = UILabel(); sizeLabel.text = "Size"; sizeLabel.textColor = .white; sizeLabel.font = Theme.body(12)
        let opacityLabel = UILabel(); opacityLabel.text = "Opacity"; opacityLabel.textColor = .white; opacityLabel.font = Theme.body(12)
        let row = UIStackView(arrangedSubviews: [sizeLabel, size, opacityLabel, opacity, hide, binding, more, done]); row.spacing = 10; row.alignment = .center
        toolbar.axis = .vertical; toolbar.spacing = 7
        toolbar.addArrangedSubview(profiles); toolbar.addArrangedSubview(row)
        toolbar.isLayoutMarginsRelativeArrangement = true; toolbar.directionalLayoutMargins = .init(top: 8, leading: 12, bottom: 8, trailing: 12)
        toolbar.backgroundColor = UIColor.black.withAlphaComponent(0.82); toolbar.layer.cornerRadius = 16; toolbar.tintColor = Theme.accent
        toolbar.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(toolbar)
        NSLayoutConstraint.activate([
            toolbar.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            toolbar.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            toolbar.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            hint.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor), hint.bottomAnchor.constraint(equalTo: toolbar.topAnchor, constant: -6)
        ])
        let panelToggle = Theme.glassButton("Hide panel", symbol: "slider.horizontal.3")
        panelToggle.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(panelToggle)
        NSLayoutConstraint.activate([
            panelToggle.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            panelToggle.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8)
        ])
        panelToggle.addAction(UIAction { [weak self, weak panelToggle] _ in
            guard let self else { return }
            self.toolbar.isHidden.toggle(); self.hint.isHidden = self.toolbar.isHidden
            panelToggle?.configuration?.title = self.toolbar.isHidden ? "Show panel" : "Hide panel"
        }, for: .touchUpInside)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:))); pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        for recognizer in [tap, pan, pinch] as [UIGestureRecognizer] { recognizer.delegate = self; view.addGestureRecognizer(recognizer) }
        refresh()
    }
    private var spec: ControlSpec? { ControlSpec.all.first { $0.id == selected } }
    private func refresh() {
        guard isViewLoaded else { return }
        controls.highlighted = selected
        size.isEnabled = spec != nil; opacity.isEnabled = spec != nil
        guard let spec else {
            hint.text = "Tap a control · drag to move · pinch to resize"; hide.isEnabled = false; hide.setTitle("Hide", for: .normal)
            binding.isEnabled = false; binding.setTitle("Action", for: .normal); return
        }
        let entry = ControlsLayout.entry(for: spec)
        size.value = Float(entry.scale); opacity.value = Float(entry.opacity)
        hint.text = "\(entry.action?.title ?? spec.title) · \(Int(entry.scale * 100))% size · \(Int(entry.opacity * 100))% opacity"
        hide.setTitle(entry.hidden ? "Show" : "Hide", for: .normal); hide.isEnabled = !ControlsLayout.essential.contains(spec.id)
        binding.isEnabled = spec.action != nil && spec.id != "pause"
        binding.setTitle("Action", for: .normal)
        binding.menu = UIMenu(title: "Assign action", children: StalkerAction.allCases.filter { $0 != .pause }.map { action in
            UIAction(title: action.title, image: UIImage(systemName: action.symbol), state: entry.action == action ? .on : .off) { [weak self] _ in
                var value = ControlsLayout.entry(for: spec); value.action = action; ControlsLayout.set(value, id: spec.id)
                self?.controls.setNeedsLayout(); self?.refresh()
            }
        })
    }
    private func changed() {
        guard let spec else { return }; var entry = ControlsLayout.entry(for: spec)
        entry.scale = Double(size.value); entry.opacity = Double(opacity.value)
        ControlsLayout.set(entry, id: spec.id); controls.setNeedsLayout(); refresh()
    }
    private func toggleHidden() {
        guard let spec, !ControlsLayout.essential.contains(spec.id) else { return }
        var entry = ControlsLayout.entry(for: spec); entry.hidden.toggle(); ControlsLayout.set(entry, id: spec.id)
        controls.setNeedsLayout(); refresh()
    }
    @objc private func tapped(_ recognizer: UITapGestureRecognizer) { selected = controls.selected(at: recognizer.location(in: controls)) }
    @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
        let point = recognizer.location(in: controls)
        if recognizer.state == .began {
            let t = recognizer.translation(in: controls); selected = controls.selected(at: CGPoint(x: point.x - t.x, y: point.y - t.y))
            if let id = selected, let frame = controls.frame(for: id) { offset = CGPoint(x: frame.midX - point.x, y: frame.midY - point.y) }
        }
        if recognizer.state == .changed, let id = selected, let entry = controls.entry(at: CGPoint(x: point.x + offset.x, y: point.y + offset.y), for: id) {
            ControlsLayout.set(entry, id: id); controls.setNeedsLayout()
        }
    }
    @objc private func pinched(_ recognizer: UIPinchGestureRecognizer) {
        if recognizer.state == .began {
            if selected == nil { selected = controls.selected(at: recognizer.location(in: controls)) }
            pinchScale = spec.map { ControlsLayout.entry(for: $0).scale } ?? 1
        }
        if recognizer.state == .changed, let spec {
            var entry = ControlsLayout.entry(for: spec); entry.scale = max(0.6, min(1.8, pinchScale * Double(recognizer.scale)))
            ControlsLayout.set(entry, id: spec.id); controls.setNeedsLayout(); refresh()
        }
    }
    private func resetLayout() {
        let alert = UIAlertController(title: "Reset \(ControlsLayout.profiles[ControlsLayout.profile])?", message: "The other layouts are kept.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { [weak self] _ in ControlsLayout.reset(); self?.controls.setNeedsLayout(); self?.selected = nil })
        present(alert, animated: true)
    }
    private func exportLayout() {
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("STALKER-controls.json")
            try ControlsLayout.exported().write(to: url, options: .atomic)
            let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            share.popoverPresentationController?.sourceView = toolbar; share.popoverPresentationController?.sourceRect = toolbar.bounds
            present(share, animated: true)
        } catch { show(error) }
    }
    private func importLayout() { let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json]); picker.delegate = self; present(picker, animated: true) }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }; let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do { try ControlsLayout.imported(Data(contentsOf: url)); selected = nil; controls.setNeedsLayout() } catch { show(error) }
    }
    private func show(_ error: Error) {
        let alert = UIAlertController(title: "Couldn’t load layout", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default)); present(alert, animated: true)
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let touched = touch.view else { return true }
        return !touched.isDescendant(of: toolbar) && !(touched is UIControl) && !(touched.superview is UIControl)
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { gestureRecognizer is UIPinchGestureRecognizer || other is UIPinchGestureRecognizer }
}
