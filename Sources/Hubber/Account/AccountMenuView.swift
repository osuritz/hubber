import SwiftUI

/// Header account menu: visibility summary plus per-account visibility toggles.
struct AccountMenuView: View {
    @ObservedObject var store: HubberStore

    private var ids: [ConnectionID] {
        store.connections.map(\.id)
    }

    private var hidden: Set<ConnectionID> {
        store.settings.connectionVisibility.hidden
    }

    private var allVisible: Bool {
        ids.allSatisfy { store.settings.connectionVisibility.isVisible($0) }
    }

    var body: some View {
        Menu {
            Button {
                setAll(visible: !allVisible)
            } label: {
                Label("All accounts", systemImage: allVisible ? "checkmark" : "")
            }

            Divider()

            ForEach(store.connections, id: \.id) { connection in
                Button {
                    let visible = store.settings.connectionVisibility.isVisible(connection.id)
                    store.setConnectionVisible(connection.id, !visible)
                } label: {
                    let visible = store.settings.connectionVisibility.isVisible(connection.id)
                    Label(
                        rowTitle(for: connection),
                        systemImage: visible ? "checkmark" : ""
                    )
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.pull")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HubberDesign.accent)

                Text(AccountHeaderLabel.text(ids: ids, hidden: hidden))
                    .hubberFont(.headerTitle)
                    .foregroundStyle(HubberDesign.text)

                if store.connections.contains(where: { needsAttention($0.authState) }) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(HubberDesign.sloAmber.fg)
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(HubberDesign.text3)
            }
            .frame(minWidth: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func rowTitle(for connection: Connection) -> String {
        let base = "\(connection.id.providerDisplayName) · @\(connection.id.login)"
        return needsAttention(connection.authState) ? "\(base)  ⚠ Needs attention" : base
    }

    private func setAll(visible: Bool) {
        for connection in store.connections {
            store.setConnectionVisible(connection.id, visible)
        }
    }

    /// An account "needs attention" when signed-in auth has failed or expired — matches the
    /// re-auth affordance in Settings → Accounts so the header ⚠ and Settings stay consistent.
    private func needsAttention(_ state: HubberAuthState) -> Bool {
        switch state {
        case .error, .sessionExpired:
            true
        default:
            false
        }
    }
}
