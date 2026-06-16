import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject var store: HubberStore
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            // GitHub Account
            SettingsSection(title: "GitHub Account") {
                SettingsGroup {
                    GitHubAuthSettingsView(store: store)
                }
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
                        Picker("", selection: $settings.sloDisplay) {
                            ForEach(SLODisplay.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .disabled(!settings.sloEnabled)
                        .opacity(settings.sloEnabled ? 1 : 0.45)
                    }

                    // Incoming mode
                    SettingsRow(isStack: true, isLast: true) {
                        Text("Incoming requests")
                            .font(HubberType.settingsLabel)
                            .foregroundStyle(HubberDesign.text)
                        Picker("", selection: $settings.incomingMode) {
                            ForEach(IncomingReviewMode.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .disabled(settings.isLocked("incomingMode"))
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
                        Picker("", selection: $settings.unresolvedMode) {
                            ForEach(UnresolvedThreadMode.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .disabled(settings.isLocked("unresolvedThreadMode"))
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
                        Picker("", selection: $settings.rowDensity) {
                            ForEach(RowDensity.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .disabled(settings.isLocked("rowDensity"))
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
                        Picker("", selection: $settings.badgeMode) {
                            ForEach(BadgeMode.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .disabled(settings.isLocked("badgeMode"))
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
            // Section header: 11 / Semibold · UPPERCASE · +0.4 tracking
            HStack(spacing: 7) {
                Text(title.uppercased())
                    .font(HubberType.section)
                    .tracking(0.4)
                    .foregroundStyle(HubberDesign.text2)

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
        .padding(.top, 14)
        .padding(.bottom, isLast ? 18 : 2)
        .overlay(alignment: .bottom) {
            if !isLast {
                HubberDesign.sep.frame(height: 0.5)
                    .padding(.top, 12)
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
                HubberDesign.sep.frame(height: 0.5)
                    .padding(.leading, 12)
            }
        }
    }
}
