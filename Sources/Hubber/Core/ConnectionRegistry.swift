import Foundation

struct ConnectionRegistry {
    private let defaults: UserDefaults
    private let key = "hubber.connections"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [ConnectionID] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }
        return (try? JSONDecoder().decode([ConnectionID].self, from: data)) ?? []
    }

    func save(_ ids: [ConnectionID]) throws {
        let data = try JSONEncoder().encode(ids)
        defaults.set(data, forKey: key)
    }

    func append(_ id: ConnectionID) throws {
        var ids = load()
        guard !ids.contains(id) else { return }
        ids.append(id)
        try save(ids)
    }

    func remove(_ id: ConnectionID) throws {
        try save(load().filter { $0 != id })
    }

    func removeAll() {
        defaults.removeObject(forKey: key)
    }
}
