import AppKit
import QuartzCore
import WatchMyBackCore

@MainActor
final class ScreenRecordingPermissionPresenter {
    static let shared = ScreenRecordingPermissionPresenter()

    private var windowController: ScreenRecordingPermissionWindowController?

    private init() {}

    func present() {
        let controller = windowController ?? ScreenRecordingPermissionWindowController()
        windowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class ScreenRecordingPermissionWindowController: NSWindowController {
    private let contentController = ScreenRecordingPermissionContentController()
    private lazy var helperPanel = ScreenRecordingPermissionHelperPanel { [weak self] in
        self?.handleHelperBack()
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 440),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Enable Screen Recording"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        contentViewController = contentController
        contentController.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func handleHelperBack() {
        helperPanel.hide()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
extension ScreenRecordingPermissionWindowController: ScreenRecordingPermissionContentControllerDelegate {
    func permissionContentControllerDidOpenSettings(
        _ controller: ScreenRecordingPermissionContentController,
        sourceFrameInScreen: CGRect?
    ) {
        ScreenRecordingPermissionSupport.openSystemSettings()
        helperPanel.show(sourceFrameInScreen: sourceFrameInScreen)
    }

    func permissionContentControllerDidRequestRestart(_ controller: ScreenRecordingPermissionContentController) {
        helperPanel.hide()
        ScreenRecordingPermissionSupport.relaunchCurrentAppBundle()
    }
}

@MainActor
private protocol ScreenRecordingPermissionContentControllerDelegate: AnyObject {
    func permissionContentControllerDidOpenSettings(
        _ controller: ScreenRecordingPermissionContentController,
        sourceFrameInScreen: CGRect?
    )
    func permissionContentControllerDidRequestRestart(_ controller: ScreenRecordingPermissionContentController)
}

@MainActor
private final class ScreenRecordingPermissionContentController: NSViewController {
    weak var delegate: ScreenRecordingPermissionContentControllerDelegate?

    private let stackView = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let cardContainer = NSStackView()
    private var requestedAt: Date?
    private var refreshTimer: Timer?
    private var diagnostics = ScreenCapturePermissionDiagnostics.current()

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        refreshUI()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshState()
            }
        }
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        refreshTimer?.invalidate()
    }

    private func configureUI() {
        view.wantsLayer = true

        let background = NSVisualEffectView()
        background.translatesAutoresizingMaskIntoConstraints = false
        background.material = .windowBackground
        background.blendingMode = .behindWindow
        background.state = .active
        view.addSubview(background)

        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Screen Recording")
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 46, weight: .semibold)
        icon.contentTintColor = .systemBlue
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Enable Screen Recording")
        title.font = NSFont.systemFont(ofSize: 30, weight: .bold)
        title.textColor = .labelColor

        let subtitle = NSTextField(wrappingLabelWithString: "Watch My Back classifies temporary screenshots locally during focus hours. Drag the app tile into System Settings if macOS does not already list it.")
        subtitle.font = NSFont.systemFont(ofSize: 14)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitle.maximumNumberOfLines = 3

        statusLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor

        cardContainer.orientation = .vertical
        cardContainer.alignment = .centerX
        cardContainer.spacing = 12
        cardContainer.translatesAutoresizingMaskIntoConstraints = false

        stackView.addArrangedSubview(icon)
        stackView.addArrangedSubview(title)
        stackView.addArrangedSubview(subtitle)
        stackView.addArrangedSubview(cardContainer)
        stackView.addArrangedSubview(statusLabel)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            background.topAnchor.constraint(equalTo: view.topAnchor),
            background.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 44),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -44),
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 34),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -28),

            icon.widthAnchor.constraint(equalToConstant: 64),
            icon.heightAnchor.constraint(equalToConstant: 64),
            cardContainer.widthAnchor.constraint(equalToConstant: 560),
        ])
    }

    private func refreshState() {
        diagnostics = .current()
        if diagnostics.isGranted {
            requestedAt = nil
        }
        refreshUI()
    }

    private func refreshUI() {
        cardContainer.arrangedSubviews.forEach { view in
            cardContainer.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let restartRequired = ScreenCapturePermissionGuidance.restartRequired(requestedAt: requestedAt)
        let card = ScreenRecordingPermissionCard(
            isGranted: diagnostics.isGranted,
            restartRequired: restartRequired
        )
        card.onOpenSettings = { [weak self] sourceFrame in
            guard let self else { return }
            requestedAt = Date()
            delegate?.permissionContentControllerDidOpenSettings(self, sourceFrameInScreen: sourceFrame)
            refreshUI()
        }
        card.onRestart = { [weak self] in
            guard let self else { return }
            delegate?.permissionContentControllerDidRequestRestart(self)
        }
        cardContainer.addArrangedSubview(card)
        card.widthAnchor.constraint(equalToConstant: 560).isActive = true

        statusLabel.stringValue = diagnostics.isGranted
            ? "Done. Screen Recording is enabled."
            : "Waiting for Screen & System Audio Recording permission."
        statusLabel.textColor = diagnostics.isGranted ? .systemGreen : .secondaryLabelColor
    }
}

@MainActor
private final class ScreenRecordingPermissionCard: NSView {
    var onOpenSettings: ((CGRect?) -> Void)?
    var onRestart: (() -> Void)?

    private let isGranted: Bool
    private let restartRequired: Bool
    private weak var actionButton: NSButton?

    init(isGranted: Bool, restartRequired: Bool) {
        self.isGranted = isGranted
        self.restartRequired = restartRequired
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.88).cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor

        let content = NSStackView()
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: isGranted ? "checkmark.seal.fill" : "camera.viewfinder", accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        icon.contentTintColor = isGranted ? .systemGreen : .systemBlue
        icon.translatesAutoresizingMaskIntoConstraints = false

        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3

        let title = NSTextField(labelWithString: "Screen & System Audio Recording")
        title.font = NSFont.systemFont(ofSize: 18, weight: .bold)

        let subtitle = NSTextField(labelWithString: subtitleText)
        subtitle.font = NSFont.systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 2

        labels.addArrangedSubview(title)
        labels.addArrangedSubview(subtitle)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        content.addArrangedSubview(icon)
        content.addArrangedSubview(labels)
        content.addArrangedSubview(spacer)

        if isGranted {
            content.addArrangedSubview(StatusPill(text: "Done"))
        } else {
            let button = PrimaryPermissionButton(
                title: restartRequired ? "Restart" : "Allow",
                target: self,
                action: restartRequired ? #selector(handleRestart) : #selector(handleOpenSettings)
            )
            actionButton = button
            content.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: 104).isActive = true
            button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 104),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            icon.widthAnchor.constraint(equalToConstant: 44),
            icon.heightAnchor.constraint(equalToConstant: 44),
            spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 12),
        ])
    }

    private var subtitleText: String {
        if isGranted {
            return "Watch My Back can classify screenshots locally."
        }
        if restartRequired {
            return "Restart the app if macOS has not refreshed the new permission."
        }
        return "Open System Settings, then enable or drag Watch My Back into the permission list."
    }

    @objc
    private func handleOpenSettings() {
        onOpenSettings?(actionButtonScreenFrame())
    }

    @objc
    private func handleRestart() {
        onRestart?()
    }

    private func actionButtonScreenFrame() -> CGRect? {
        guard let actionButton, let window = actionButton.window else { return nil }
        let frameInWindow = actionButton.convert(actionButton.bounds, to: nil)
        return window.convertToScreen(frameInWindow)
    }
}

@MainActor
private final class ScreenRecordingPermissionHelperPanel {
    private let onBack: () -> Void
    private var panel: NSPanel?
    private var timer: Timer?
    private var sourceFrameInScreen: CGRect?
    private var didAnimateIn = false

    init(onBack: @escaping () -> Void) {
        self.onBack = onBack
    }

    func show(sourceFrameInScreen: CGRect?) {
        self.sourceFrameInScreen = sourceFrameInScreen
        didAnimateIn = false
        let panel = panel ?? makePanel()
        self.panel = panel
        startTimer()
        updateVisibilityAndPosition()
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        didAnimateIn = false
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 112),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.contentView = ScreenRecordingPermissionHelperView(onBack: onBack)
        return panel
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.18, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateVisibilityAndPosition()
            }
        }
        timer.tolerance = 0.04
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func updateVisibilityAndPosition() {
        guard let panel else { return }
        guard ScreenRecordingPermissionSupport.isSystemSettingsFrontmost,
              let context = ScreenRecordingPermissionSupport.systemSettingsWindowContext()
        else {
            panel.orderOut(nil)
            return
        }

        let targetFrame = targetFrame(for: panel.frame.size, settingsWindow: context.bounds)
        if !didAnimateIn, let sourceFrameInScreen, !sourceFrameInScreen.isEmpty {
            didAnimateIn = true
            panel.setFrame(sourceFrameInScreen, display: false)
            panel.order(.above, relativeTo: context.windowNumber)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.38
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            didAnimateIn = true
            panel.setFrame(targetFrame, display: true)
            panel.order(.above, relativeTo: context.windowNumber)
        }
    }

    private func targetFrame(for panelSize: CGSize, settingsWindow: CGRect) -> CGRect {
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(settingsWindow) }) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? settingsWindow
        let sidebarWidth = min(max(settingsWindow.width * 0.29, 214), 272)
        let contentMinX = settingsWindow.minX + sidebarWidth + 24
        let contentMaxX = settingsWindow.maxX - 28
        let contentMidX = (contentMinX + contentMaxX) / 2
        let x = min(max(contentMidX - panelSize.width / 2, visibleFrame.minX + 16), visibleFrame.maxX - panelSize.width - 16)
        let y = max(visibleFrame.minY + 12, settingsWindow.minY - panelSize.height + 8)
        return CGRect(origin: CGPoint(x: x, y: y), size: panelSize)
    }
}

@MainActor
private final class ScreenRecordingPermissionHelperView: NSView {
    private let onBack: () -> Void
    private let tileView = DraggableWatchMyBackTileView()

    init(onBack: @escaping () -> Void) {
        self.onBack = onBack
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func setup() {
        let material = NSVisualEffectView()
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.translatesAutoresizingMaskIntoConstraints = false
        material.wantsLayer = true
        material.layer?.cornerRadius = 18
        material.layer?.masksToBounds = true
        addSubview(material)

        let backButton = NSButton(image: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")!, target: self, action: #selector(handleBack))
        backButton.isBordered = false
        backButton.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(backButton)

        let arrow = NSImageView()
        arrow.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: "Drag upward")
        arrow.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 24, weight: .bold)
        arrow.contentTintColor = .systemBlue
        arrow.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(arrow)

        let label = NSTextField(labelWithString: "Drag Watch My Back above to allow Screen Recording")
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(label)

        tileView.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(tileView)

        NSLayoutConstraint.activate([
            material.leadingAnchor.constraint(equalTo: leadingAnchor),
            material.trailingAnchor.constraint(equalTo: trailingAnchor),
            material.topAnchor.constraint(equalTo: topAnchor),
            material.bottomAnchor.constraint(equalTo: bottomAnchor),

            backButton.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 18),
            backButton.bottomAnchor.constraint(equalTo: material.bottomAnchor, constant: -24),
            backButton.widthAnchor.constraint(equalToConstant: 24),
            backButton.heightAnchor.constraint(equalToConstant: 24),

            arrow.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 34),
            arrow.topAnchor.constraint(equalTo: material.topAnchor, constant: 12),
            arrow.widthAnchor.constraint(equalToConstant: 26),
            arrow.heightAnchor.constraint(equalToConstant: 26),

            label.leadingAnchor.constraint(equalTo: arrow.trailingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: arrow.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: material.trailingAnchor, constant: -20),

            tileView.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 62),
            tileView.trailingAnchor.constraint(equalTo: material.trailingAnchor, constant: -20),
            tileView.topAnchor.constraint(equalTo: material.topAnchor, constant: 52),
            tileView.heightAnchor.constraint(equalToConstant: 42),
        ])
    }

    @objc
    private func handleBack() {
        onBack()
    }
}

@MainActor
private final class DraggableWatchMyBackTileView: NSView, NSDraggingSource {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let iconRect = CGRect(x: 11, y: 7, width: 28, height: 28)
        NSWorkspace.shared.icon(forFile: ScreenRecordingPermissionSupport.currentAppBundleURL()?.path ?? Bundle.main.bundleURL.path)
            .draw(in: iconRect)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        ScreenRecordingPermissionSupport.currentBundleDisplayName.draw(
            at: CGPoint(x: 50, y: 12),
            withAttributes: attributes
        )
    }

    override func mouseDragged(with event: NSEvent) {
        guard let bundleURL = ScreenRecordingPermissionSupport.currentAppBundleURL() else {
            NSSound.beep()
            return
        }

        let item = NSDraggingItem(pasteboardWriter: bundleURL as NSURL)
        item.setDraggingFrame(bounds, contents: snapshotImage())
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    private func snapshotImage() -> NSImage {
        let bitmap = bitmapImageRepForCachingDisplay(in: bounds)
            ?? NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(bounds.width),
                pixelsHigh: Int(bounds.height),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )!
        cacheDisplay(in: bounds, to: bitmap)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmap)
        return image
    }
}

@MainActor
private final class StatusPill: NSView {
    init(text: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.13).cgColor

        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .systemGreen
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
private final class PrimaryPermissionButton: NSButton {
    init(title: String, target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        self.title = title
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        isBordered = false
        focusRingType = .none
        setButtonType(.momentaryPushIn)
        updateTitle()
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isHighlighted: Bool {
        didSet { updateAppearance() }
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    private func updateTitle() {
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
        )
    }

    private func updateAppearance() {
        layer?.backgroundColor = (isHighlighted ? NSColor.systemBlue.blended(withFraction: 0.18, of: .black) ?? .systemBlue : .systemBlue).cgColor
    }
}

private enum ScreenRecordingPermissionSupport {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    static var currentBundleDisplayName: String {
        let bundle = Bundle.main
        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String)
            ?? "Watch My Back"
    }

    @MainActor
    static func openSystemSettings() {
        NSWorkspace.shared.open(settingsURL)
    }

    @MainActor
    static func relaunchCurrentAppBundle() {
        guard let appURL = currentAppBundleURL() else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in }
        NSApp.terminate(nil)
    }

    @MainActor
    static func currentAppBundleURL() -> URL? {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        if bundleURL.pathExtension == "app" {
            return bundleURL
        }

        guard let executableURL = Bundle.main.executableURL?.standardizedFileURL else {
            return nil
        }

        var directory = executableURL.deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory
                .appendingPathComponent("dist", isDirectory: true)
                .appendingPathComponent("WatchMyBack.app", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Contents/Info.plist").path) {
                return candidate
            }
            let parent = directory.deletingLastPathComponent()
            if parent == directory { break }
            directory = parent
        }

        return bundleURL
    }

    @MainActor
    static var isSystemSettingsFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.systempreferences"
    }

    struct SystemSettingsWindowContext {
        let bounds: CGRect
        let windowNumber: Int
    }

    @MainActor
    static func systemSettingsWindowContext() -> SystemSettingsWindowContext? {
        guard let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.systempreferences" }),
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else {
            return nil
        }

        let candidates = windows.compactMap { info -> (SystemSettingsWindowContext, CGFloat)? in
            guard
                let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                ownerPID == runningApp.processIdentifier,
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0,
                let windowNumber = info[kCGWindowNumber as String] as? Int,
                let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
            else {
                return nil
            }

            let appKitBounds = appKitRect(fromQuartzBounds: bounds)
            return (SystemSettingsWindowContext(bounds: appKitBounds, windowNumber: windowNumber), appKitBounds.width * appKitBounds.height)
        }

        return candidates.sorted(by: { $0.1 > $1.1 }).first?.0
    }

    @MainActor
    private static func appKitRect(fromQuartzBounds bounds: CGRect) -> CGRect {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(bounds) }) ?? NSScreen.main else {
            return bounds
        }
        return CGRect(x: bounds.minX, y: screen.frame.maxY - bounds.maxY, width: bounds.width, height: bounds.height)
    }
}
