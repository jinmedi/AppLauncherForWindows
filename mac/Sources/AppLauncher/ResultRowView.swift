#if canImport(AppKit)
import AppKit

/// Draws the rounded selection and hover highlight behind a result row.
final class ResultRowView: NSTableRowView {
    private var hovered = false
    private var trackingArea: NSTrackingArea?

    override var isEmphasized: Bool {
        get { true }
        set {}
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard !isSelected, hovered else {
            return
        }
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 0), xRadius: 8, yRadius: 8).fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
    }
}

/// Icon, name, path, "앱"/"폴더" badge and the key that launches the row.
final class ResultCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let kindBadge = NSView()
    private let kindLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        kindBadge.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
    }

    func configure(icon: NSImage, name: String, detail: String, kind: String, shortcut: String) {
        iconView.image = icon
        nameLabel.stringValue = name
        detailLabel.stringValue = detail
        kindLabel.stringValue = kind
        shortcutLabel.stringValue = shortcut
    }

    private func build() {
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 15)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        kindBadge.wantsLayer = true
        kindBadge.layer?.cornerRadius = 4
        kindBadge.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        kindBadge.translatesAutoresizingMaskIntoConstraints = false

        kindLabel.font = .systemFont(ofSize: 10)
        kindLabel.textColor = .secondaryLabelColor
        kindLabel.translatesAutoresizingMaskIntoConstraints = false
        kindBadge.addSubview(kindLabel)

        shortcutLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        shortcutLabel.textColor = .secondaryLabelColor
        shortcutLabel.alignment = .right
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(nameLabel)
        addSubview(detailLabel)
        addSubview(kindBadge)
        addSubview(shortcutLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            nameLabel.bottomAnchor.constraint(equalTo: centerYAnchor, constant: 1),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: kindBadge.leadingAnchor, constant: -10),

            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 2),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: kindBadge.leadingAnchor, constant: -10),

            kindLabel.leadingAnchor.constraint(equalTo: kindBadge.leadingAnchor, constant: 6),
            kindLabel.trailingAnchor.constraint(equalTo: kindBadge.trailingAnchor, constant: -6),
            kindLabel.topAnchor.constraint(equalTo: kindBadge.topAnchor, constant: 2),
            kindLabel.bottomAnchor.constraint(equalTo: kindBadge.bottomAnchor, constant: -2),
            kindBadge.centerYAnchor.constraint(equalTo: centerYAnchor),
            kindBadge.trailingAnchor.constraint(equalTo: shortcutLabel.leadingAnchor, constant: -12),

            shortcutLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            shortcutLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcutLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])

        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
}
#endif
