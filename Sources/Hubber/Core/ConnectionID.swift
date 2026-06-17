import Foundation

// swiftformat:disable redundantSendable
struct ConnectionID: Hashable, Codable, CustomStringConvertible, Sendable {
    // swiftformat:enable redundantSendable

    let provider: String
    let host: String
    let login: String

    init(provider: String, host: String, login: String) {
        self.provider = provider.lowercased()
        self.host = host.lowercased()
        self.login = login.lowercased()
    }

    var description: String {
        "\(provider):\(host):\(login)"
    }

    var slug: String {
        "\(provider)_\(host)_\(login)"
            .map { character in
                character.isSlugSafe ? character : "-"
            }
            .map(String.init)
            .joined()
    }

    static func gitHubDotCom(login: String) -> ConnectionID {
        ConnectionID(provider: "github", host: "github.com", login: login)
    }
}

private extension Character {
    var isSlugSafe: Bool {
        isASCII && (isLetter || isNumber || self == "." || self == "_" || self == "-")
    }
}
