import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: HubberStore
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            SettingsSection(title: "GitHub Account") {
                GitHubAuthSettingsView(store: store)
            }

            SettingsSection(title: "Developer") {
                DeveloperPanelView(store: store)
            }

            SettingsSection(title: ReviewSLOPresentation.settingsSectionTitle) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ReviewSLOPresentation.title)
                            .font(.system(size: 13, weight: .medium))
                        Text(ReviewSLOPresentation.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $settings.sloEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(settings.isLocked("reviewSLOEnabled"))
                }

                HStack(spacing: 12) {
                    Text(ReviewSLOPresentation.windowLabel).font(.system(size: 13))
                    Spacer(minLength: 12)
                    Slider(value: $settings.sloHours, in: 1...24, step: 1)
                        .frame(width: 190)
                    Text("\(Int(settings.sloHours))h")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .frame(width: 36, alignment: .trailing)
                }
                .disabled(!settings.sloEnabled || settings.isLocked("sloWindowHours"))
                .opacity(settings.sloEnabled ? 1 : 0.45)

                Text(ReviewSLOPresentation.thresholdHelp)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(settings.sloEnabled ? 1 : 0.55)
            }

            SettingsSection(title: "Show SLO as") {
                Picker("", selection: $settings.sloDisplay) {
                    ForEach(SLODisplay.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!settings.sloEnabled)
                .opacity(settings.sloEnabled ? 1 : 0.45)
            }

            SettingsSection(title: "Incoming mode") {
                Picker("", selection: $settings.incomingMode) {
                    ForEach(IncomingReviewMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(settings.isLocked("incomingMode"))
            }

            SettingsSection(title: "Unresolved threads") {
                Picker("", selection: $settings.unresolvedMode) {
                    ForEach(UnresolvedThreadMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(settings.isLocked("unresolvedThreadMode"))
            }

            SettingsSection(title: "Row density", isLast: true) {
                Picker("", selection: $settings.rowDensity) {
                    ForEach(RowDensity.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(settings.isLocked("rowDensity"))
            }
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    var isLast = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(.secondary)

            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider().opacity(0.55)
            }
        }
    }
}
