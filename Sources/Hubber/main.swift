import AppKit
import Combine
import MetricKit
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Initial allocation size only. The real frame is computed on every open (and on every
    /// width change) from the width setting + the host screen — see `panelFrame(relativeTo:)`.
    private static let initialPanelSize = NSSize(width: PanelWidth.normal.points, height: PanelGeometry.minHeight)
    private static let panelCornerRadius = 26.0
    private static let panelGap = 6.0

    private var statusItem: NSStatusItem?
    /// The SwiftUI host for the popover content, retained so the panel's backing can be re-wrapped
    /// (glass vs. plain) when Reduce Transparency toggles at runtime — see applyPanelBacking().
    private var panelHostingView: NSView?
    private let panel = HubberMenuPanel(
        contentRect: NSRect(origin: .zero, size: initialPanelSize),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private let statusMenu = NSMenu()
    private let store = HubberStore(restoreOnInit: false)
    private let updaterController = UpdaterController()
    private let metricSubscriber = MetricSubscriber()
    private var appActivationObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var a11yDisplayObserver: NSObjectProtocol?
    private var eventMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []
    private var pulseTimer: Timer?
    private var pulsePhase: Double = 0
    /// Tracks whether MetricKit was started at launch. Used in applicationWillTerminate
    /// to remove the subscriber only if it was actually added — guards against the case
    /// where the user disables crash reporting mid-session (live setting would be false,
    /// but the subscriber is still registered from launch time).
    private var metricKitStarted = false

    /// The menu-bar status-item glyph: a custom "rubber stamp" template image that
    /// auto-inverts for light/dark menu bars. In DEBUG the stroke weight is selectable
    /// via `HUBBER_STAMP_LEVEL` (0 = full, 1 = thinner, 2 = thinnest) so the weight can
    /// be judged live in the menu bar; release builds use a fixed weight. Falls back to
    /// the previous SF Symbol if the bundled asset is missing.
    /// The menu-bar status-item glyph: the custom "rubber stamp" template image (vector PDF),
    /// which auto-inverts for light/dark menu bars and stays crisp at any scale. Falls back to
    /// the previous SF Symbol if the bundled asset is somehow missing.
    private static func menubarGlyph() -> NSImage? {
        if
            let url = Bundle.module.url(forResource: "stamp-vector", withExtension: "pdf"),
            let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            image.accessibilityDescription = "Hubber"
            return image
        }
        return NSImage(systemSymbolName: "arrow.triangle.pull", accessibilityDescription: "Hubber")
    }

    /// Menu-bar (`.accessory`) apps show no menu bar, so AppKit never delivers the standard
    /// ⌘X/⌘C/⌘V/⌘A/⌘Z key equivalents to the focused text field — those route through the Edit
    /// menu's items, which don't exist by default. Installing a minimal Edit menu on
    /// `NSApp.mainMenu` restores clipboard shortcuts in the popover + sheets (the items target
    /// `nil`, so they dispatch to the first responder). Right-click already works via the field's
    /// own context menu. See #100.
    private func installEditMenu() {
        let mainMenu = NSMenu()
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        editItem.submenu = editMenu
        NSApp.mainMenu = mainMenu
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        startTelemetry()
        NSApp.setActivationPolicy(.accessory)
        installEditMenu()

        // No fixed size here: the content fills its hosting view, which the panel resizes
        // (width from the setting, height from the screen). See applyPanelWidth() / panelFrame().
        let contentView = HubberPopoverView(store: store)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        configurePanel(with: contentView)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        configureStatusMenu()

        if let button = item.button {
            button.image = Self.menubarGlyph()
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePanel(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Hubber")
        }

        updateStatusItem()
        subscribeToStore()
        configureInitialConnections()
        store.reconcileLaunchAtLogin()

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closePanelForOutsideClick()
            }
        }

        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let activatedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                activatedApp.processIdentifier != NSRunningApplication.current.processIdentifier
            else {
                return
            }

            Task { @MainActor in
                // Don't close the panel when the browser activates during device-flow sign-in
                // OR while the add-account sheet is open — the user needs the panel while they
                // authorize a device code or follow the "create a token" link in the browser.
                guard let self, !self.store.shouldPinPanel else { return }
                self.closePanel()
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.store.refreshPullRequests()
            }
        }

        a11yDisplayObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Reduce Transparency changes which panel backing we use (glass vs. plain); the
                // status-item glyph can also depend on Increased Contrast.
                self?.updateStatusItem()
                self?.applyPanelBacking()
            }
        }
    }

    private func configureInitialConnections() {
        #if DEBUG
            if MockMode.shared.isActive {
                MockMode.shared.apply(MockMode.shared.scenario, to: store)
            } else {
                store.restoreAllConnections()
            }
        #else
            store.restoreAllConnections()
        #endif
    }

    // MARK: - Telemetry / crash reporting

    /// Crash/hang diagnostics (MetricKit → local os_log only) are gated here at launch.
    /// Analytics (TelemetryDeck) is gated LIVE by GatedTelemetrySink, so it is NOT started here.
    private func startTelemetry() {
        if store.settings.crashReportingEnabled {
            MXMetricManager.shared.add(metricSubscriber)
            metricKitStarted = true
        }
    }

    // MARK: - Status item badge + animation

    private func subscribeToStore() {
        // Merge data, badgeMode, and refreshing signals into a single debounced update.
        let dataChange = store.$data.map { _ in () }
        let badgeModeChange = store.settings.$badgeMode.map { _ in () }
        let refreshingChange = store.$isRefreshingPullRequests.map { _ in () }

        dataChange
            .merge(with: badgeModeChange)
            .merge(with: refreshingChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateStatusItem() }
            .store(in: &cancellables)

        // Live-resize the panel when the width setting changes (slider drag). The async hop
        // ensures the stored property is updated before applyPanelWidth() reads it.
        store.settings.$panelWidth
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyPanelWidth() }
            .store(in: &cancellables)
    }

    /// Resizes the panel to the current width setting + screen-adaptive height. When the panel
    /// is visible this re-anchors it under the menu-bar icon. Non-animated so it tracks the
    /// width slider smoothly.
    private func applyPanelWidth() {
        guard let button = statusItem?.button else { return }
        panel.setFrame(panelFrame(relativeTo: button), display: true, animate: false)
    }

    private func updateStatusItem() {
        let mode = store.settings.badgeMode
        let incomingCount = store.data.incoming.count
        let attentionCount = AttentionState.attentionCount(data: store.data)
        let count = MenubarPresentation.badgeCount(
            mode: mode,
            incomingCount: incomingCount,
            attentionCount: attentionCount
        )
        let state = MenubarPresentation.state(badgeCount: count, isRefreshing: store.isRefreshingPullRequests)

        guard let button = statusItem?.button else { return }

        button.title = state.badgeText ?? ""
        button.toolTip = MenubarPresentation.tooltip(
            mode: mode,
            incomingCount: incomingCount,
            attentionCount: attentionCount
        )
        button.setAccessibilityValue(
            MenubarPresentation.accessibilityValue(
                mode: mode,
                incomingCount: incomingCount,
                attentionCount: attentionCount
            )
        )

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if state.isRefreshing, AccessibilityGates.pulseEnabled(reduceMotion: reduceMotion) {
            startPulse(on: button)
        } else {
            stopPulse(on: button)
        }
    }

    /// Starts a subtle alpha pulse (0.45 ↔ 1.0) on the status button to signal a refresh in progress.
    private func startPulse(on button: NSStatusBarButton) {
        guard pulseTimer == nil else { return }
        pulsePhase = 0
        // Timer fires on the main run loop (scheduled on main thread); MainActor.assumeIsolated
        // is safe here because AppDelegate is @MainActor and all setup runs on the main thread.
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self, weak button] _ in
            MainActor.assumeIsolated {
                guard let self, let button else { return }
                self.pulsePhase += 0.05
                let alpha = 0.725 + 0.275 * sin(self.pulsePhase * .pi * 2)
                button.alphaValue = alpha
            }
        }
    }

    /// Stops the alpha pulse and restores full opacity.
    private func stopPulse(on button: NSStatusBarButton) {
        pulseTimer?.invalidate()
        pulseTimer = nil
        button.alphaValue = 1.0
    }

    private func configurePanel(with contentView: some View) {
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(origin: .zero, size: Self.initialPanelSize)
        // Reflow with the panel as it resizes (width setting / screen-adaptive height).
        hostingView.autoresizingMask = [.width, .height]
        panelHostingView = hostingView
        applyPanelBacking()

        panel.delegate = self
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.isMovable = false
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
    }

    /// Installs the panel's content backing; safe to call repeatedly. On macOS 26+ the panel is
    /// backed by the system Liquid Glass material (NSGlassEffectView, Regular) so it matches the
    /// Wi-Fi/Bluetooth/Control Center menus — UNLESS Reduce Transparency is on, in which case we
    /// skip the glass entirely (rather than hide it under an opaque fill) so no glass rim or
    /// lensing leaks for that accessibility setting. Older systems use the plain clipped host with
    /// the in-SwiftUI vibrancy material. Re-invoked from the accessibility-display observer so a
    /// runtime Reduce Transparency toggle takes effect immediately.
    private func applyPanelBacking() {
        guard let hostingView = panelHostingView else { return }
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency

        if #available(macOS 26, *), !reduceTransparency {
            let glass = NSGlassEffectView()
            glass.frame = NSRect(origin: .zero, size: Self.initialPanelSize)
            glass.autoresizingMask = [.width, .height]
            glass.style = .regular
            glass.cornerRadius = Self.panelCornerRadius
            glass.contentView = hostingView
            panel.contentView = glass
        } else {
            hostingView.wantsLayer = true
            hostingView.layer?.cornerRadius = Self.panelCornerRadius
            hostingView.layer?.cornerCurve = .continuous
            hostingView.layer?.masksToBounds = true
            panel.contentView = hostingView
        }
    }

    private func configureStatusMenu() {
        statusMenu.removeAllItems()

        // Only surface "Check for Updates…" when this build actually carries an update feed.
        // Dev builds omit SUFeedURL, so Sparkle would error on a missing feed — hide the item
        // until a feed ships (#113). Routed straight to Sparkle's controller so its
        // canCheckForUpdates validation enables/disables it without AppDelegate proxying.
        if updaterController.isUpdateMechanismAvailable {
            let checkForUpdates = statusMenu.addItem(
                withTitle: "Check for Updates…",
                action: updaterController.checkForUpdatesAction,
                keyEquivalent: ""
            )
            checkForUpdates.target = updaterController.checkForUpdatesTarget
            statusMenu.addItem(.separator())
        }

        statusMenu.addItem(
            withTitle: "Sign Out",
            action: #selector(signOut(_:)),
            keyEquivalent: ""
        )
        statusMenu.addItem(.separator())
        statusMenu.addItem(
            withTitle: "Quit",
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        // Point the Hubber-owned items at self, but DON'T clobber the updater item
        // (its target must stay the Sparkle controller). Separators have no target.
        for item in statusMenu.items where item.target == nil && !item.isSeparatorItem {
            item.target = self
        }
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.type == .rightMouseDown {
            closePanel()
            statusMenu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: sender.bounds.height + 4),
                in: sender
            )
            return
        }

        if panel.isVisible {
            closePanel()
        } else {
            panel.setFrame(panelFrame(relativeTo: sender), display: true)
            panel.orderFrontRegardless()
            // Don't let AppKit focus-ring the first control (the Refresh button) on open;
            // the key-view loop still engages the moment the user tabs.
            panel.makeFirstResponder(nil)
            store.setPopoverOpen(true)
            emitSessionOpenedEvents()
        }
    }

    private func emitSessionOpenedEvents() {
        let data = store.data
        let settings = store.settings
        store.telemetry.sessionOpened()
        store.telemetry.sessionCounts(
            incoming: data.incoming.count,
            outgoing: data.outgoing.count,
            drafts: data.drafts.count
        )
        // Emit SLO distribution only when SLO is enabled.
        if settings.sloEnabled {
            let sloHours = settings.sloHours
            var green = 0, amber = 0, red = 0
            for review in data.incoming {
                let ratio = review.assignedAgoHours / sloHours
                if ratio < 0.5 {
                    green += 1
                } else if ratio < 1.0 {
                    amber += 1
                } else {
                    red += 1
                }
            }
            store.telemetry.sloDistribution(green: green, amber: amber, red: red)
        }
    }

    private func closePanel() {
        panel.close()
    }

    private func closePanelForOutsideClick() {
        // Keep the panel pinned during device-flow sign-in or while the add-account sheet is
        // open, so clicking into the browser (enter the code / create a token) doesn't dismiss it.
        if store.shouldPinPanel { return }
        let clickLocation = NSEvent.mouseLocation
        if panel.frame.contains(clickLocation) || statusButtonFrame()?.contains(clickLocation) == true {
            return
        }
        closePanel()
    }

    /// Computes the panel's full frame for the screen hosting the menu-bar item: width from
    /// the user setting, height adaptive to the screen (see PanelGeometry), right/left-aligned
    /// under the button and clamped to the visible frame.
    private func panelFrame(relativeTo sender: NSStatusBarButton) -> NSRect {
        let width = store.settings.panelWidth.points

        guard let buttonFrame = screenFrame(of: sender) else {
            return NSRect(origin: .zero, size: NSSize(width: width, height: PanelGeometry.minHeight))
        }

        let visibleFrame = sender.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let height = PanelGeometry.height(
            screenVisibleHeight: visibleFrame.height,
            screenVisibleMinY: visibleFrame.minY,
            buttonMinY: buttonFrame.minY,
            gap: Self.panelGap
        )

        let preferredLeftAlignedX = buttonFrame.minX
        let preferredRightAlignedX = buttonFrame.maxX - width
        let unclampedX = preferredLeftAlignedX + width <= visibleFrame.maxX
            ? preferredLeftAlignedX
            : preferredRightAlignedX
        let x = min(max(unclampedX, visibleFrame.minX), visibleFrame.maxX - width)
        let y = buttonFrame.minY - height - Self.panelGap

        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func screenFrame(of sender: NSStatusBarButton) -> NSRect? {
        guard let window = sender.window else {
            return nil
        }

        let frameInWindow = sender.convert(sender.bounds, to: nil)
        return window.convertToScreen(frameInWindow)
    }

    private func statusButtonFrame() -> NSRect? {
        guard let button = statusItem?.button else {
            return nil
        }
        return screenFrame(of: button)
    }

    @objc private func signOut(_ sender: Any?) {
        closePanel()
        Task {
            await store.signOut()
        }
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    func applicationWillTerminate(_: Notification) {
        // Only remove the subscriber if it was actually added at launch.
        // Gating on metricKitStarted (not the live setting) prevents a leak when the
        // user disables crash reporting mid-session — the subscriber was registered
        // and must be removed regardless of the current setting value.
        if metricKitStarted {
            MXMetricManager.shared.remove(metricSubscriber)
        }
        if let appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appActivationObserver)
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let a11yDisplayObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(a11yDisplayObserver)
        }
    }
}

private final class HubberMenuPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_: Notification) {
        store.setPopoverOpen(false)
    }
}

// MARK: - Notification tap handling

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Called when the user taps a notification while the app is in the foreground.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Called when the user taps a notification to open the PR.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let urlString = userInfo["prURL"] as? String, let url = URL(string: urlString) {
            Task { @MainActor in
                NSWorkspace.shared.open(url)
            }
        }
        completionHandler()
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(signOut(_:)) {
            switch store.authState {
            case .signedIn, .sessionExpired:
                return true
            default:
                return false
            }
        }
        return true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Register the UNUserNotificationCenter delegate for tap-to-open — but only inside a real
// `.app` bundle. `UNUserNotificationCenter.current()` raises an uncatchable NSException
// ("bundleProxyForCurrentProcess is nil") when there is no app bundle (e.g. under `swift run`
// or xctest), so we must not touch it there. Mirrors NotificationDispatcher.isBundledApp.
// AppDelegate adopts UNUserNotificationCenterDelegate below.
if Bundle.main.bundleURL.pathExtension == "app" {
    UNUserNotificationCenter.current().delegate = delegate
}

app.run()
