import SwiftUI

/// Settings -> Accounts management: account rows, add-account sheet, and hidden notification policy.
struct AccountsSettingsSection: View {
    @ObservedObject var store: HubberStore
    @ObservedObject var settings: SettingsStore

    @State private var showingAdd = false
    @State private var reauthToken: [ConnectionID: String] = [:]

    var body: some View {
        SettingsGroup {
            ForEach(store.connections, id: \.id) { connection in
                accountRow(connection, isLast: false)
            }

            SettingsRow(isLast: false) {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add account…", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(HubberDesign.accent)
            }

            SettingsRow(isLast: true) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notify for hidden accounts")
                        .font(HubberType.settingsLabel)
                        .foregroundStyle(HubberDesign.text)
                    Text("Hidden accounts still alert on new activity.")
                        .font(HubberType.settingsSub)
                        .foregroundStyle(HubberDesign.text2)
                }

                Spacer()

                Toggle("", isOn: $settings.notifyHiddenAccounts)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddAccountView(
                policy: settings.providerAccessPolicy,
                isDuplicate: { [weak store] id in store?.connections.contains { $0.id == id } ?? false },
                addAccount: { [weak store] id, token, user in
                    _ = try await store?.addResolvedAccount(id: id, token: token, user: user)
                },
                onActiveChange: { store.setAddingAccount($0) },
                onDone: { showingAdd = false }
            )
        }
    }

    private func accountRow(_ connection: Connection, isLast: Bool) -> some View {
        SettingsRow(isStack: true, isLast: isLast) {
            HStack(spacing: 10) {
                AvatarView(
                    user: GitHubUser(
                        login: connection.id.login,
                        initials: initials(for: connection.viewerName ?? connection.id.login),
                        color: avatarColor(for: connection.id.login),
                        avatarURL: connection.viewerAvatarURL
                    ),
                    size: AvatarSize.row.rawValue
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(connection.id.providerDisplayName) · @\(connection.id.login)")
                        .font(HubberType.title)
                        .foregroundStyle(HubberDesign.text)

                    accountStatus(connection)
                }

                Spacer()
            }

            switch connection.authState {
            case let .waitingForUser(authorization):
                deviceCodeControls(connection: connection, authorization: authorization)
            default:
                accountActions(connection)
            }
        }
    }

    @ViewBuilder
    private func accountStatus(_ connection: Connection) -> some View {
        switch connection.authState {
        case .error:
            Text("⚠ Needs attention")
                .font(HubberType.secondary)
                .foregroundStyle(HubberDesign.sloAmber.fg)
        case .sessionExpired:
            Text("Session expired")
                .font(HubberType.secondary)
                .foregroundStyle(HubberDesign.sloAmber.fg)
        case .waitingForUser:
            Text("Waiting for device authorization")
                .font(HubberType.secondary)
                .foregroundStyle(HubberDesign.text2)
        case .restoring:
            Text("Checking sign-in")
                .font(HubberType.secondary)
                .foregroundStyle(HubberDesign.text2)
        case .signedOut:
            Text("Signed out")
                .font(HubberType.secondary)
                .foregroundStyle(HubberDesign.text2)
        case .signedIn:
            EmptyView()
        }
    }

    private func accountActions(_ connection: Connection) -> some View {
        HStack(spacing: 8) {
            if needsReauth(connection.authState) {
                if isDeviceFlow(connection) {
                    Button("Re-authenticate") {
                        connection.startSignIn(policy: settings.providerAccessPolicy)
                    }
                } else {
                    SecureField(
                        "New token",
                        text: Binding(
                            get: { reauthToken[connection.id] ?? "" },
                            set: { reauthToken[connection.id] = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 160)

                    Button("Re-authenticate") {
                        let token = reauthToken[connection.id] ?? ""
                        Task { @MainActor in
                            await connection.signIn(withToken: token)
                            reauthToken[connection.id] = nil
                        }
                    }
                    .disabled((reauthToken[connection.id] ?? "").isEmpty)
                }
            }

            Button("Sign out") {
                Task { await connection.signOut() }
            }

            Button("Remove") {
                Task { await store.removeConnection(connection.id) }
            }
        }
        .controlSize(.small)
    }

    private func deviceCodeControls(connection: Connection, authorization: GitHubDeviceAuthorization) -> some View {
        HStack(spacing: 8) {
            Text(authorization.userCode)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(HubberDesign.text)

            Button("Copy") {
                connection.copyDeviceCode()
            }

            Button("Open GitHub") {
                connection.openDeviceVerificationPage()
            }

            Button("Cancel") {
                connection.cancelSignIn()
            }
        }
        .controlSize(.small)
    }

    private func needsReauth(_ state: HubberAuthState) -> Bool {
        switch state {
        case .error, .sessionExpired, .signedOut:
            true
        case .restoring, .waitingForUser, .signedIn:
            false
        }
    }

    private func isDeviceFlow(_ connection: Connection) -> Bool {
        connection.id.provider == "github" && connection.id.host == "github.com"
    }

    private func initials(for name: String) -> String {
        let words = name.split(separator: " ").prefix(2)
        if
            words.count >= 2,
            let first = words[0].first,
            let second = words[1].first {
            return "\(first)\(second)".uppercased()
        } else if let first = name.first {
            return String(first).uppercased()
        }
        return "?"
    }

    private func avatarColor(for login: String) -> Color {
        let hue = Double(abs(login.hashValue) % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.70)
    }
}
