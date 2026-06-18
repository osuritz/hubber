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
        [provider, host, login]
            .map(Self.encodeSlugComponent)
            .joined(separator: "_")
    }

    /// Human label for the header / Settings: "GitHub", "GitHub Enterprise", or "GitLab".
    var providerDisplayName: String {
        switch provider {
        case "gitlab":
            "GitLab"
        case "github":
            host == "github.com" ? "GitHub" : "GitHub Enterprise"
        default:
            provider.capitalized
        }
    }

    static func gitHubDotCom(login: String) -> ConnectionID {
        ConnectionID(provider: "github", host: "github.com", login: login)
    }

    private static func encodeSlugComponent(_ component: String) -> String {
        var encoded = ""

        for byte in component.utf8 {
            if byte.isSlugComponentSafe {
                encoded.unicodeScalars.append(Unicode.Scalar(byte))
            } else {
                // H1: escape "_" so component delimiters remain unambiguous and slugs stay injective.
                encoded.append("%")
                encoded.append(hexDigits[Int(byte >> 4)])
                encoded.append(hexDigits[Int(byte & 0x0F)])
            }
        }

        return encoded
    }

    private static let hexDigits: [Character] = [
        "0",
        "1",
        "2",
        "3",
        "4",
        "5",
        "6",
        "7",
        "8",
        "9",
        "a",
        "b",
        "c",
        "d",
        "e",
        "f",
    ]
}

private extension UInt8 {
    var isSlugComponentSafe: Bool {
        (ASCII.lowercaseA...ASCII.lowercaseZ).contains(self)
            || (ASCII.zero...ASCII.nine).contains(self)
            || self == ASCII.period
            || self == ASCII.hyphen
    }
}

private enum ASCII {
    static let lowercaseA: UInt8 = 97
    static let lowercaseZ: UInt8 = 122
    static let zero: UInt8 = 48
    static let nine: UInt8 = 57
    static let period: UInt8 = 46
    static let hyphen: UInt8 = 45
}
