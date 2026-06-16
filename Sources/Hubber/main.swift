import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let panelSize = NSSize(width: 420, height: 540)
    private static let panelCornerRadius = 26.0
    private static let panelGap = 6.0

    private var statusItem: NSStatusItem?
    private let panel = HubberMenuPanel(
        contentRect: NSRect(origin: .zero, size: panelSize),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private let statusMenu = NSMenu()
    private let store = HubberStore()
    private var appActivationObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var eventMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []
    private var pulseTimer: Timer?
    private var pulsePhase: Double = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let contentView = HubberPopoverView(store: store)
            .frame(width: Self.panelSize.width, height: Self.panelSize.height)

        configurePanel(with: contentView)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        configureStatusMenu()

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "arrow.triangle.pull", accessibilityDescription: "Hubber")
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePanel(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        updateStatusItem()
        subscribeToStore()

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
                self?.closePanel()
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

        if state.isRefreshing {
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
        hostingView.frame = NSRect(origin: .zero, size: Self.panelSize)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = Self.panelCornerRadius
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true

        panel.contentView = hostingView
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

    private func configureStatusMenu() {
        statusMenu.removeAllItems()
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
        statusMenu.items.forEach { $0.target = self }
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
            panel.setFrameOrigin(panelOrigin(relativeTo: sender))
            panel.orderFrontRegardless()
            store.setPopoverOpen(true)
        }
    }

    private func closePanel() {
        panel.close()
    }

    private func closePanelForOutsideClick() {
        let clickLocation = NSEvent.mouseLocation
        if panel.frame.contains(clickLocation) || statusButtonFrame()?.contains(clickLocation) == true {
            return
        }
        closePanel()
    }

    private func panelOrigin(relativeTo sender: NSStatusBarButton) -> NSPoint {
        guard let buttonFrame = screenFrame(of: sender) else {
            return .zero
        }

        let visibleFrame = sender.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let preferredLeftAlignedX = buttonFrame.minX
        let preferredRightAlignedX = buttonFrame.maxX - Self.panelSize.width
        let unclampedX = preferredLeftAlignedX + Self.panelSize.width <= visibleFrame.maxX
            ? preferredLeftAlignedX
            : preferredRightAlignedX
        let x = min(max(unclampedX, visibleFrame.minX), visibleFrame.maxX - Self.panelSize.width)
        let y = buttonFrame.minY - Self.panelSize.height - Self.panelGap

        return NSPoint(x: x, y: y)
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
        store.signOut()
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    func applicationWillTerminate(_: Notification) {
        if let appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appActivationObserver)
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
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
app.run()
