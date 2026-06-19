import Foundation

/// Which connections are shown in the unified inbox. A connection NOT in `hidden` is visible,
/// so newly-added accounts appear by default. Pure value type — persistence lives in SettingsStore.
struct ConnectionVisibility: Equatable, Codable {
    private(set) var hidden: Set<ConnectionID>

    init(hidden: Set<ConnectionID> = []) {
        self.hidden = hidden
    }

    func isVisible(_ id: ConnectionID) -> Bool {
        !hidden.contains(id)
    }

    /// Returns a copy with `id` shown or hidden.
    func setting(_ id: ConnectionID, visible: Bool) -> ConnectionVisibility {
        var next = hidden
        if visible { next.remove(id) } else { next.insert(id) }
        return ConnectionVisibility(hidden: next)
    }
}
