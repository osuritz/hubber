import Foundation
@testable import Hubber

// MARK: - InMemoryManagedPreferences (test fake)
//
// Backed by a [String: Any] dictionary. Presence of a key implies it is forced.
// Used in unit tests where CFPreferencesAppValueIsForced cannot be forced by the system.
//
// @unchecked Sendable: this type is only ever constructed on a single task/actor in tests
// and is never mutated after initialisation, so the `@unchecked` annotation is safe.

final class InMemoryManagedPreferences: ManagedPreferences, @unchecked Sendable {
    private let store: [String: Any]

    init(_ store: [String: Any] = [:]) {
        self.store = store
    }

    func isForced(_ key: String) -> Bool {
        store[key] != nil
    }

    func value(_ key: String) -> Any? {
        store[key]
    }
}
