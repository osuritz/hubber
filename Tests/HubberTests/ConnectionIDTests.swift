import XCTest
@testable import Hubber

final class ConnectionIDTests: XCTestCase {

    func testMixedCaseInputsProduceEqualIDsAndHashes() {
        let mixedCase = ConnectionID(provider: "GitHub", host: "GitHub.com", login: "Personal")
        let normalized = ConnectionID(provider: "github", host: "github.com", login: "personal")

        XCTAssertEqual(mixedCase, normalized)
        XCTAssertEqual(mixedCase.hashValue, normalized.hashValue)
    }

    func testDescriptionUsesLowercasedColonSeparatedComponents() {
        let id = ConnectionID(provider: "GitHub", host: "GitHub.com", login: "Personal")

        XCTAssertEqual(id.description, "github:github.com:personal")
    }

    func testSlugIsStableLowercasedAndFilenameSafeForNormalInputs() {
        let id = ConnectionID(provider: "GitHub", host: "GitHub.Com", login: "Personal")

        XCTAssertEqual(id.slug, "github_github.com_personal")
        XCTAssertTrue(id.slug.allSatisfy(isSlugSafe))
    }

    func testSlugSanitizesUnsafeCharacters() {
        let id = ConnectionID(provider: "GitHub", host: "GitHub.Com", login: "Work User/Prod")

        XCTAssertEqual(id.slug, "github_github.com_work-user-prod")
        XCTAssertTrue(id.slug.allSatisfy(isSlugSafe))
    }

    func testGitHubDotComHelperUsesGitHubProviderAndHost() {
        let id = ConnectionID.gitHubDotCom(login: "Personal")

        XCTAssertEqual(id.provider, "github")
        XCTAssertEqual(id.host, "github.com")
        XCTAssertEqual(id.login, "personal")
    }

    func testCodableRoundTrip() throws {
        let original = ConnectionID(provider: "GitHub", host: "GitHub.com", login: "Personal")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ConnectionID.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    private func isSlugSafe(_ character: Character) -> Bool {
        character.isASCII
            && (character.isLetter || character.isNumber || character == "." || character == "_" || character == "-")
    }
}
