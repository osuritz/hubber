import SwiftUI

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
                                .font(HubberType.settingsLabel)
                                .foregroundStyle(HubberDesign.text)
                            Text(ReviewSLOPresentation.subtitle)
                                .font(HubberType.settingsSub)
                                .foregroundStyle(HubberDesign.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Toggle("", isOn: $settings.sloEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(settings.isLocked("reviewSLOEnabled"))
                    }

                    // Review window slider
                    SettingsRow(isLast: false) {
                        Text(ReviewSLOPresentation.windowLabel)
                            .font(HubberType.settingsLabel)
                            .foregroundStyle(settings.sloEnabled ? HubberDesign.text : HubberDesign.text3)

                        Slider(value: $settings.sloHours, in: 1...24, step: 1)
                            .frame(maxWidth: 190)

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
                            .font(HubberType.settingsLabel)
                            .foregroundStyle(settings.sloEnabled ? HubberDesign.text : HubberDesign.text3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        NativeSegmentedPicker(
                            SLODisplay.self,
                            selection: $settings.sloDisplay,
                            isEnabled: settings.sloEnabled && !settings.isLocked("sloDisplay"),
                            title: \.title
                        )
                        .opacity(settings.sloEnabled ? 1 : 0.45)
                    }

                    // Incoming mode
                    SettingsRow(isStack: true, isLast: true) {
                        Text("Incoming requests")
                            .font(HubberType.settingsLabel)
                            .foregroundStyle(HubberDesign.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        NativeSegmentedPicker(
                            IncomingReviewMode.self,
                            selection: $settings.incomingMode,
                            isEnabled: !settings.isLocked("incomingMode"),
                            title: \.title
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
                                .font(HubberType.settingsLabel)
                                .foregroundStyle(HubberDesign.text)
                            Text("Which threads count as unresolved")
                                .font(HubberType.settingsSub)
                                .foregroundStyle(HubberDesign.text2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        NativeSegmentedPicker(
                            UnresolvedThreadMode.self,
                            selection: $settings.unresolvedMode,
                            isEnabled: !settings.isLocked("unresolvedThreadMode"),
                            title: \.title
                        )
                    }
                }
            }

            // Appearance
            SettingsSection(title: "Appearance") {
                SettingsGroup {
                    SettingsRow(isStack: true, isLast: true) {
                        Text("Row density")
                            .font(HubberType.settingsLabel)
                            .foregroundStyle(HubberDesign.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        NativeSegmentedPicker(
                            RowDensity.self,
                            selection: $settings.rowDensity,
                            isEnabled: !settings.isLocked("rowDensity"),
                            title: \.title
                        )
                    }
                }
            }

            // Menubar Badge
            SettingsSection(title: "Menubar Badge") {
                SettingsGroup {
                    SettingsRow(isStack: true, isLast: true) {
                        Text("Badge shows")
                            .font(HubberType.settingsLabel)
                            .foregroundStyle(HubberDesign.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        NativeSegmentedPicker(
                            BadgeMode.self,
                            selection: $settings.badgeMode,
                            isEnabled: !settings.isLocked("badgeMode"),
                            title: \.title
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
                                .font(HubberType.settingsLabel)
                                .foregroundStyle(HubberDesign.text)
                            Text("Helps improve Hubber. No personal data is shared.")
                                .font(HubberType.settingsSub)
                                .foregroundStyle(HubberDesign.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Toggle("", isOn: $settings.analyticsEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(settings.isLocked(ManagedKey.analyticsEnabled))
                    }

                    // Crash reporting toggle
                    SettingsRow(isLast: true) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Send crash & hang reports")
                                .font(HubberType.settingsLabel)
                                .foregroundStyle(HubberDesign.text)
                            Text("Reports help diagnose stability issues. No PII is included.")
                                .font(HubberType.settingsSub)
                                .foregroundStyle(HubberDesign.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Toggle("", isOn: $settings.crashReportingEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(settings.isLocked(ManagedKey.crashReportingEnabled))
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
