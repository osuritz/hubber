import AppKit
import SwiftUI

/// Stable in-app privacy-policy link (GitHub-hosted PRIVACY.md). Reused by the onboarding
/// consent step. See #104.
enum PrivacyLinks {
    static let privacyPolicy = URL(string: "https://github.com/osuritz/hubber/blob/main/PRIVACY.md")!
}

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject var store: HubberStore
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            // Accounts
            SettingsSection(title: "Accounts") {
                AccountsSettingsSection(store: store, settings: settings)
            }

            // Incoming Reviews
            SettingsSection(title: ReviewSLOPresentation.settingsSectionTitle) {
                SettingsGroup {
                    // SLO toggle
                    SettingsRow(isLast: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ReviewSLOPresentation.title)
                                .hubberFont(.settingsLabel)
                                .foregroundStyle(HubberDesign.text)
                            Text(ReviewSLOPresentation.subtitle)
                                .hubberFont(.settingsSub)
                                .foregroundStyle(HubberDesign.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Toggle("", isOn: $settings.sloEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .accessibilityLabel(ReviewSLOPresentation.title)
                            .disabled(settings.isLocked("reviewSLOEnabled"))
                    }

                    // Review window slider
                    SettingsRow(isLast: false) {
                        Text(ReviewSLOPresentation.windowLabel)
                            .hubberFont(.settingsLabel)
                            .foregroundStyle(settings.sloEnabled ? HubberDesign.text : HubberDesign.text3)

                        Slider(value: $settings.sloHours, in: 1...24, step: 1)
                            .frame(maxWidth: 190)
                            .accessibilityLabel("Review SLO")
                            .accessibilityValue("\(Int(settings.sloHours)) hours")

                        Text("\(Int(settings.sloHours))h")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(settings.sloEnabled ? HubberDesign.text : HubberDesign.text3)
                            .frame(width: 36, alignment: .trailing)
                    }
                    .disabled(!settings.sloEnabled || settings.isLocked("sloWindowHours"))
                    .opacity(settings.sloEnabled ? 1 : 0.45)

                    // SLO display mode
                    SettingsRow(isStack: true, isLast: false) {
                        Text("Show SLO as")
                            .hubberFont(.settingsLabel)
                            .foregroundStyle(settings.sloEnabled ? HubberDesign.text : HubberDesign.text3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        NativeSegmentedPicker(
                            SLODisplay.self,
                            selection: $settings.sloDisplay,
                            isEnabled: settings.sloEnabled && !settings.isLocked("sloDisplay"),
                            title: \.title,
                            accessibilityLabel: "Show SLO as"
                        )
                        .opacity(settings.sloEnabled ? 1 : 0.45)
                    }

                    // Incoming mode
                    SettingsRow(isStack: true, isLast: true) {
                        Text("Incoming requests")
                            .hubberFont(.settingsLabel)
                            .foregroundStyle(HubberDesign.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        NativeSegmentedPicker(
                            IncomingReviewMode.self,
                            selection: $settings.incomingMode,
                            isEnabled: !settings.isLocked("incomingMode"),
                            title: \.title,
                            accessibilityLabel: "Incoming requests"
                        )
                    }
                }
            }

            // Outgoing
            SettingsSection(title: "Outgoing") {
                SettingsGroup {
                    SettingsRow(isStack: true, isLast: true) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Unresolved threads")
                                .hubberFont(.settingsLabel)
                                .foregroundStyle(HubberDesign.text)
                            Text("Which threads count as unresolved")
                                .hubberFont(.settingsSub)
                                .foregroundStyle(HubberDesign.text2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        NativeSegmentedPicker(
                            UnresolvedThreadMode.self,
                            selection: $settings.unresolvedMode,
                            isEnabled: !settings.isLocked("unresolvedThreadMode"),
                            title: \.title,
                            accessibilityLabel: "Unresolved threads"
                        )
                    }
                }
            }

            // Appearance
            SettingsSection(title: "Appearance") {
                SettingsGroup {
                    SettingsRow(isStack: true, isLast: false) {
                        Text("Row density")
                            .hubberFont(.settingsLabel)
                            .foregroundStyle(HubberDesign.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        NativeSegmentedPicker(
                            RowDensity.self,
                            selection: $settings.rowDensity,
                            isEnabled: !settings.isLocked("rowDensity"),
                            title: \.title,
                            accessibilityLabel: "Row density"
                        )
                    }

                    // Panel width preset — resizes the menu-bar panel. Height is automatic
                    // (a fraction of the screen), so only width is user-set here.
                    SettingsRow(isStack: true, isLast: false) {
                        Text("Panel width")
                            .hubberFont(.settingsLabel)
                            .foregroundStyle(HubberDesign.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        NativeSegmentedPicker(
                            PanelWidth.self,
                            selection: $settings.panelWidth,
                            isEnabled: !settings.isLocked(ManagedKey.panelWidth),
                            title: \.title,
                            accessibilityLabel: "Panel width"
                        )
                    }

                    SettingsRow(isStack: true, isLast: true) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Status indicator")
                                .hubberFont(.settingsLabel)
                                .foregroundStyle(HubberDesign.text)
                            Text("Slim colour rail for roomier titles, or the classic CI badge.")
                                .hubberFont(.settingsSub)
                                .foregroundStyle(HubberDesign.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        NativeSegmentedPicker(
                            StatusIndicatorStyle.self,
                            selection: $settings.statusIndicatorStyle,
                            isEnabled: !settings.isLocked(ManagedKey.statusIndicatorStyle),
                            title: \.title,
                            accessibilityLabel: "Status indicator"
                        )
                    }
                }
            }

            // Launch at login (#106)
            SettingsSection(title: "General") {
                SettingsGroup {
                    SettingsRow(isLast: true) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open at login")
                                .hubberFont(.settingsLabel)
                                .foregroundStyle(HubberDesign.text)
                            Text("Start Hubber automatically when you log in.")
                                .hubberFont(.settingsSub)
                                .foregroundStyle(HubberDesign.text2)
                        }
                        Toggle("", isOn: Binding(
                            get: { settings.launchAtLoginEnabled },
                            set: { store.setLaunchAtLogin($0) }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityLabel("Open at login")
                        .disabled(settings.isLocked(ManagedKey.launchAtLogin))
                    }
                }
            }

            // Menubar Badge
            SettingsSection(title: "Menubar Badge") {
                SettingsGroup {
                    SettingsRow(isStack: true, isLast: true) {
                        Text("Badge shows")
                            .hubberFont(.settingsLabel)
                            .foregroundStyle(HubberDesign.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        NativeSegmentedPicker(
                            BadgeMode.self,
                            selection: $settings.badgeMode,
                            isEnabled: !settings.isLocked("badgeMode"),
                            title: \.title,
                            accessibilityLabel: "Menubar badge"
                        )
                    }
                }
            }

            // Tab Badges
            SettingsSection(title: "Tab Badges") {
                SettingsGroup {
                    SettingsRow(isStack: true, isLast: true) {
                        Text("Badges show")
                            .hubberFont(.settingsLabel)
                            .foregroundStyle(HubberDesign.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        NativeSegmentedPicker(
                            TabBadgeMode.self,
                            selection: $settings.tabBadgeMode,
                            isEnabled: !settings.isLocked("tabBadgeMode"),
                            title: \.title,
                            accessibilityLabel: "Tab badges"
                        )
                    }
                }
            }

            // Notifications
            SettingsSection(title: "Notifications") {
                SettingsGroup {
                    NotificationsSettingsView(store: store, settings: settings)
                }
            }

            // Privacy
            SettingsSection(title: "Privacy") {
                SettingsGroup {
                    // Analytics toggle
                    SettingsRow(isLast: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Share anonymous usage analytics")
                                .hubberFont(.settingsLabel)
                                .foregroundStyle(HubberDesign.text)
                            Text("Helps improve Hubber. No personal data is shared.")
                                .hubberFont(.settingsSub)
                                .foregroundStyle(HubberDesign.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Toggle("", isOn: $settings.analyticsEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .accessibilityLabel("Share anonymous usage analytics")
                            .disabled(settings.isLocked(ManagedKey.analyticsEnabled))
                    }

                    // Crash reporting toggle — LOCAL os_log only (transmits nothing). Label must
                    // not imply transmission. See #104.
                    SettingsRow(isLast: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Diagnostic logging")
                                .hubberFont(.settingsLabel)
                                .foregroundStyle(HubberDesign.text)
                            Text(
                                "Crash, hang, and performance diagnostics are written to your "
                                    + "Mac's local log only — never sent anywhere."
                            )
                            .hubberFont(.settingsSub)
                            .foregroundStyle(HubberDesign.text2)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        Toggle("", isOn: $settings.crashReportingEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .accessibilityLabel("Diagnostic logging")
                            .disabled(settings.isLocked(ManagedKey.crashReportingEnabled))
                    }

                    // Privacy policy link (#104)
                    SettingsRow(isLast: true) {
                        Text("Privacy Policy")
                            .hubberFont(.settingsLabel)
                            .foregroundStyle(HubberDesign.text)
                        Spacer()
                        Button("Read") { NSWorkspace.shared.open(PrivacyLinks.privacyPolicy) }
                            .buttonStyle(.plain)
                            .hubberFont(.settingsSub)
                            .foregroundStyle(HubberDesign.accent)
                    }
                }
            }

            // Developer (debug chip per settings.jsx)
            SettingsSection(title: "Developer", isLast: true, isDebug: true) {
                DeveloperPanelView(store: store)
            }
        }
    }
}

// MARK: - SettingsSection

struct SettingsSection<Content: View>: View {
    let title: String
    var isLast = false
    var isDebug = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header: Title Case · 13 / Regular · secondaryLabelColor (native macOS style)
            HStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    // No native token sits between secondaryLabelColor and labelColor;
                    // secondary reads too light for a section header, so use primary at 70%.
                    .foregroundStyle(Color.primary.opacity(0.7))

                if isDebug {
                    Text("DEBUG")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(HubberDesign.sloAmber.fg)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(HubberDesign.sloAmber.bg, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(HubberDesign.sloAmber.border, lineWidth: 0.5)
                        }
                }
            }

            content()
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        // Real gap below the card so the separator sits in the gutter between
        // sections (12pt below this card, 12pt above the next header) rather than
        // being pulled up into the card by overlay padding.
        .padding(.bottom, isLast ? 18 : 12)
        .overlay(alignment: .bottom) {
            if !isLast {
                Color(nsColor: .separatorColor)
                    .frame(height: 0.5)
            }
        }
    }
}

// MARK: - SettingsGroup (per settings.jsx Group)

/// Rounded container for settings rows — mirrors the macOS grouped table section.
struct SettingsGroup<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            colorScheme == .dark
                ? .white.opacity(0.05)
                : .white.opacity(0.5),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(HubberDesign.sep, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - SettingsRow (per settings.jsx GRow)

struct SettingsRow<Content: View>: View {
    var isStack = false
    var isLast = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if isStack {
                VStack(alignment: .leading, spacing: 8) {
                    content()
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    content()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, isStack ? 9 : 8)
        .frame(minHeight: 22)
        .overlay(alignment: .bottom) {
            if !isLast {
                Color(nsColor: .separatorColor)
                    .frame(height: 0.5)
                    .padding(.leading, 12)
            }
        }
    }
}
