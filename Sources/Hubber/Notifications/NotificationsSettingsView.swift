import AppKit
import SwiftUI

// MARK: - NotificationsSettingsView

struct NotificationsSettingsView: View {
    @ObservedObject var store: HubberStore
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            // Master toggle
            SettingsRow(isLast: false) {
                Text("Enable notifications")
                    .font(HubberType.settingsLabel)
                    .foregroundStyle(HubberDesign.text)
                Toggle("", isOn: $settings.notificationsEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(settings.isLocked("notificationsEnabled"))
            }

            // Per-type toggles
            perTypeRow(
                label: "New review requested",
                binding: $settings.notifyNewReview,
                key: "notifyNewReview",
                isLast: false
            )
            perTypeRow(
                label: "Review approved",
                binding: $settings.notifyReviewApproved,
                key: "notifyReviewApproved",
                isLast: false
            )
            perTypeRow(
                label: "Changes requested",
                binding: $settings.notifyChangesRequested,
                key: "notifyChangesRequested",
                isLast: false
            )
            perTypeRow(
                label: "CI failed",
                binding: $settings.notifyCIFailed,
                key: "notifyCIFailed",
                isLast: false
            )
            perTypeRow(
                label: "PR merged",
                binding: $settings.notifyPRMerged,
                key: "notifyPRMerged",
                isLast: true
            )

            // "Enable in System Settings" when denied
            if store.notificationsDenied {
                systemSettingsLink
            }
        }
        .disabled(!settings.notificationsEnabled)
        .opacity(settings.notificationsEnabled ? 1 : 0.45)
    }

    // MARK: - Helpers

    private func perTypeRow(
        label: String,
        binding: Binding<Bool>,
        key: String,
        isLast: Bool
    ) -> some View {
        SettingsRow(isLast: isLast) {
            Text(label)
                .font(HubberType.settingsLabel)
                .foregroundStyle(HubberDesign.text)
            Toggle("", isOn: binding)
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(settings.isLocked(key))
        }
    }

    private var systemSettingsLink: some View {
        SettingsRow(isLast: false) {
            Text("Enable in System Settings")
                .font(HubberType.settingsLabel)
                .foregroundStyle(HubberDesign.text)
            Spacer()
            Button("Open") {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
                NSWorkspace.shared.open(url)
            }
            .font(HubberType.settingsLabel)
        }
    }
}
