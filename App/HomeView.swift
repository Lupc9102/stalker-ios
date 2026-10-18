import UIKit

/// The start screen: background art, the game's title, where the game files are, the mode choice,
/// Play, and the way into Settings and the controls layout. The view controller keeps the logic;
/// this view only lays things out and reports taps.
final class HomeView: UIView {
    enum FilesState { case ready, attention, problem, busy }

    let playButton = Theme.primaryButton(AppLanguage.choose("Play"), symbol: "play.fill")
    let settingsButton = Theme.glassButton(AppLanguage.choose("Settings"), symbol: "gearshape.fill")
    let layoutButton = Theme.glassButton(AppLanguage.choose("Controls layout"), symbol: "hand.tap.fill")
    let helpButton = Theme.glassButton(AppLanguage.choose("Help"), symbol: "paperplane.fill")
    let preloadLabel = UILabel()
    let controllerLabel = UILabel()
    /// Taps on the game files card.
    var onFiles: (() -> Void)?
    /// A mode card was tapped (index into GameMode.allCases).
    var onMode: ((Int) -> Void)?

    private let filesCard = UIControl()
    private let filesIcon = UIImageView()
    private let filesTitle = UILabel()
    private let filesDetail = UILabel()
    private let filesSpinner = UIActivityIndicatorView(style: .medium)
    private var modeCards: [ModeCard] = []
    private let modeDetail = UILabel()
    private let brandTitle = UILabel()
    private let brandSubtitle = UILabel()
    init(modes: [(title: String, symbol: String)], log: UIView) {
        super.init(frame: .zero)
        let backdrop = Theme.backdrop(image: "StartBackground")
        pin(backdrop, to: self)

        let icon = UIImageView(image: UIImage(systemName: "sun.haze.fill"))
        icon.tintColor = Theme.accent
        icon.contentMode = .scaleAspectFit
        icon.layer.cornerRadius = 14
        icon.layer.cornerCurve = .continuous
        icon.clipsToBounds = true
        icon.widthAnchor.constraint(equalToConstant: 52).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 52).isActive = true
        let title = brandTitle
        title.text = AppLanguage.choose("S.T.A.L.K.E.R.")
        title.font = Theme.display(30)
        title.textColor = Theme.text
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.7
        let subtitle = brandSubtitle
        subtitle.text = AppLanguage.choose("Call of Pripyat · bring your own files") + " · \(Theme.appVersion)"
        subtitle.font = Theme.body(14, .medium)
        subtitle.textColor = Theme.secondaryText
        let titles = UIStackView(arrangedSubviews: [title, subtitle])
        titles.axis = .vertical
        titles.spacing = 2
        let header = UIStackView(arrangedSubviews: [icon, titles])
        header.spacing = 14
        header.alignment = .center

        buildFilesCard()

        for (index, mode) in modes.enumerated() {
            let card = ModeCard(title: mode.title, symbol: mode.symbol)
            card.addAction(UIAction { [weak self] _ in self?.onMode?(index) }, for: .touchUpInside)
            modeCards.append(card)
        }
        let modes = UIStackView(arrangedSubviews: modeCards)
        modes.spacing = 10
        modes.distribution = .fillEqually
        modeDetail.font = Theme.body(13)
        modeDetail.textColor = Theme.secondaryText
        modeDetail.numberOfLines = 1
        modeDetail.adjustsFontSizeToFitWidth = true
        modeDetail.minimumScaleFactor = 0.8

        helpButton.accessibilityLabel = AppLanguage.choose("Help and controls")
        let secondary = UIStackView(arrangedSubviews: [helpButton, layoutButton, settingsButton])
        secondary.spacing = 10
        secondary.translatesAutoresizingMaskIntoConstraints = false
        for label in [preloadLabel, controllerLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            label.textColor = Theme.tertiaryText
            label.numberOfLines = 0
        }
        preloadLabel.isHidden = true

        let column = UIStackView(arrangedSubviews: [header, filesCard, modes, modeDetail, playButton, preloadLabel, controllerLabel])
        column.axis = .vertical
        column.spacing = 12
        column.setCustomSpacing(18, after: header)
        column.setCustomSpacing(12, after: filesCard)
        column.setCustomSpacing(6, after: modes)
        column.setCustomSpacing(14, after: modeDetail)
        column.setCustomSpacing(10, after: playButton)
        column.alignment = .fill

        let scroll = UIScrollView()
        scroll.showsVerticalScrollIndicator = false
        scroll.alwaysBounceVertical = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        scroll.addSubview(column)
        log.translatesAutoresizingMaskIntoConstraints = false
        addSubview(log)
        addSubview(secondary)
        let guide = safeAreaLayoutGuide
        let width = column.widthAnchor.constraint(equalTo: guide.widthAnchor, multiplier: 0.46)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 28),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: column.widthAnchor),
            column.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            column.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            column.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -12),
            // Centred vertically when there's room, scrolling when there isn't.
            column.heightAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.heightAnchor, constant: -24),
            width,
            column.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
            column.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
            secondary.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
            secondary.topAnchor.constraint(equalTo: guide.topAnchor, constant: 14),
            log.leadingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: 20),
            log.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            log.topAnchor.constraint(equalTo: secondary.bottomAnchor, constant: 12),
            log.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -16)
        ])
        column.distribution = .fill
        // Spare height goes above and below the column's content rather than into it.
        let topSpace = UIView(), bottomSpace = UIView()
        column.insertArrangedSubview(topSpace, at: 0)
        column.addArrangedSubview(bottomSpace)
        topSpace.heightAnchor.constraint(equalTo: bottomSpace.heightAnchor).isActive = true
        for view in column.arrangedSubviews where view !== topSpace && view !== bottomSpace {
            view.setContentHuggingPriority(.required, for: .vertical)
            view.setContentCompressionResistancePriority(.required, for: .vertical)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Update language-specific titles in place without touching downloaded game files or layout.
    func refreshLanguage() {
        brandTitle.text = AppLanguage.choose("S.T.A.L.K.E.R.")
        brandSubtitle.text = AppLanguage.choose("Call of Pripyat · bring your own files") + " · \(Theme.appVersion)"
        playButton.configuration?.title = AppLanguage.choose("Play")
        settingsButton.configuration?.title = AppLanguage.choose("Settings")
        layoutButton.configuration?.title = AppLanguage.choose("Controls layout")
        helpButton.configuration?.title = AppLanguage.choose("Help")
        for (index, card) in modeCards.enumerated() {
            card.setTitle(GameMode.allCases[index].title)
        }

    }

    private func buildFilesCard() {
        let panel = Theme.panel(cornerRadius: 16)
        panel.isUserInteractionEnabled = false
        pin(panel, to: filesCard)
        filesIcon.contentMode = .scaleAspectFit
        filesIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        filesIcon.widthAnchor.constraint(equalToConstant: 30).isActive = true
        filesTitle.font = Theme.body(16, .semibold)
        filesTitle.textColor = Theme.text
        filesDetail.font = Theme.body(13)
        filesDetail.textColor = Theme.secondaryText
        filesDetail.numberOfLines = 3
        let texts = UIStackView(arrangedSubviews: [filesTitle, filesDetail])
        texts.axis = .vertical
        texts.spacing = 2
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)))
        chevron.tintColor = Theme.tertiaryText
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        filesSpinner.color = Theme.text
        let iconHolder = UIView()
        for view in [filesIcon, filesSpinner] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            iconHolder.addSubview(view)
            NSLayoutConstraint.activate([view.centerXAnchor.constraint(equalTo: iconHolder.centerXAnchor), view.centerYAnchor.constraint(equalTo: iconHolder.centerYAnchor)])
        }
        iconHolder.widthAnchor.constraint(equalToConstant: 30).isActive = true
        let row = UIStackView(arrangedSubviews: [iconHolder, texts, chevron])
        row.spacing = 12
        row.alignment = .center
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        filesCard.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: filesCard.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: filesCard.trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: filesCard.topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: filesCard.bottomAnchor, constant: -12)
        ])
        filesCard.accessibilityTraits = .button
        filesCard.isAccessibilityElement = true
        filesCard.addAction(UIAction { [weak self] _ in self?.onFiles?() }, for: .touchUpInside)
        filesCard.addAction(UIAction { [weak self] _ in self?.filesCard.alpha = 0.7 }, for: [.touchDown, .touchDragEnter])
        filesCard.addAction(UIAction { [weak self] _ in self?.filesCard.alpha = 1 }, for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    /// Shows where the game files are and whether they're ready.
    func setFiles(_ state: FilesState, title: String, detail: String) {
        filesTitle.text = title
        filesDetail.text = detail
        filesDetail.isHidden = detail.isEmpty
        filesSpinner.isHidden = state != .busy
        filesIcon.isHidden = state == .busy
        if state == .busy { filesSpinner.startAnimating() } else { filesSpinner.stopAnimating() }
        let (symbol, color): (String, UIColor) = switch state {
        case .ready: ("checkmark.circle.fill", Theme.ok)
        case .attention: ("folder.badge.plus", Theme.warning)
        case .problem: ("exclamationmark.triangle.fill", Theme.problem)
        case .busy: ("", Theme.text)
        }
        filesIcon.image = symbol.isEmpty ? nil : UIImage(systemName: symbol)
        filesIcon.tintColor = color
        filesCard.accessibilityLabel = AppLanguage.interpolate(AppLanguage.choose("Game files: {arg0}. {arg1}"), [title, detail])
    }

    func setMode(_ index: Int?, detail: String, enabled: Bool) {
        for (i, card) in modeCards.enumerated() { card.isSelected = i == index; card.isEnabled = enabled }
        modeDetail.text = detail
    }

    private func pin(_ view: UIView, to parent: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: parent.leadingAnchor), view.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            view.topAnchor.constraint(equalTo: parent.topAnchor), view.bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])
    }
}

/// A campaign or controls-practice mode card.
private final class ModeCard: UIControl {
    private let panel = Theme.panel(cornerRadius: 14)
    private let icon = UIImageView()
    private let label = UILabel()

    init(title: String, symbol: String) {
        super.init(frame: .zero)
        panel.isUserInteractionEnabled = false
        panel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panel)
        icon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
        label.text = title
        label.font = Theme.body(15, .semibold)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        let row = UIStackView(arrangedSubviews: [icon, label])
        row.spacing = 8
        row.alignment = .center
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: leadingAnchor), panel.trailingAnchor.constraint(equalTo: trailingAnchor),
            panel.topAnchor.constraint(equalTo: topAnchor), panel.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.centerXAnchor.constraint(equalTo: centerXAnchor), row.centerYAnchor.constraint(equalTo: centerYAnchor),
            row.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 10),
            heightAnchor.constraint(equalToConstant: 44)
        ])
        isAccessibilityElement = true
        accessibilityLabel = title
        update()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setTitle(_ title: String) {
        label.text = title
        accessibilityLabel = title
    }

    override var isSelected: Bool { didSet { update() } }
    override var isEnabled: Bool { didSet { update() } }
    override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.75 : 1 } }

    private func update() {
        let color = isSelected ? Theme.accent : Theme.text
        icon.tintColor = color
        label.textColor = isEnabled ? color : Theme.tertiaryText
        panel.layer.borderColor = (isSelected ? Theme.accent : Theme.panelStroke).cgColor
        panel.layer.borderWidth = isSelected ? 2 : 1
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}
