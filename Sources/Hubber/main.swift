import AppKit
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
    private var eventMonitor: Any?

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
            button.title = "5"
            button.target = self
            button.action = #selector(togglePanel(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

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
                self?.panel.close()
            }
        }
    }

    private func configurePanel(with contentView: some View) {
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(origin: .zero, size: Self.panelSize)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = Self.panelCornerRadius
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true

        panel.contentView = hostingView
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
            panel.close()
            statusMenu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: sender.bounds.height + 4),
                in: sender
            )
            return
        }

        if panel.isVisible {
            panel.close()
        } else {
            panel.setFrameOrigin(panelOrigin(relativeTo: sender))
            panel.orderFrontRegardless()
        }
    }

    private func closePanelForOutsideClick() {
        let clickLocation = NSEvent.mouseLocation
        if panel.frame.contains(clickLocation) || statusButtonFrame()?.contains(clickLocation) == true {
            return
        }
        panel.close()
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
        panel.close()
        store.signOut()
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(sender)
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
