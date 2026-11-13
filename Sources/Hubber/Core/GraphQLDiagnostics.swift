import Foundation

/// Pure helpers that turn the `errors[]` / SSO hints of a GraphQL response into short log notes.
enum GraphQLDiagnostics {
    static let maxNotes = 5
    static let maxMessageLength = 200

    /// One note per well-formed entry of `errors[]`: `TYPE: message` (or just `message`).
    /// Entries that are not objects or lack a string `message` are skipped.
    static func errorNotes(from json: [String: Any]) -> [String] {
        guard let errors = json["errors"] as? [Any] else { return [] }
        var notes: [String] = []
        for case let error as [String: Any] in errors {
            guard let message = error["message"] as? String else { continue }
            let text = String(message.prefix(maxMessageLength))
            if let type = error["type"] as? String, !type.isEmpty {
                notes.append("\(type): \(text)")
            } else {
                notes.append(text)
            }
            if notes.count == maxNotes {
                break
            }
        }
        return notes
    }

    /// Note for GitHub's `X-GitHub-SSO` header (present when a token needs SSO authorization).
    /// Only the header's kind (e.g. `required` / `partial-results`) is kept, never the authorization URL.
    static func ssoNote(header: String?) -> String? {
        guard let header, !header.isEmpty else { return nil }
        let summary = header.split(separator: ";").first.map(String.init) ?? header
        return "X-GitHub-SSO: \(String(summary.prefix(maxMessageLength)))"
    }
}
