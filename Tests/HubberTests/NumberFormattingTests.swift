import Testing
@testable import Hubber

@Suite("Number formatting")
struct NumberFormattingTests {
    @Test("Counts below 1000 render verbatim")
    func verbatimBelowThousand() {
        #expect(abbreviatedLineCount(0) == "0")
        #expect(abbreviatedLineCount(7) == "7")
        #expect(abbreviatedLineCount(42) == "42")
        #expect(abbreviatedLineCount(999) == "999")
    }

    @Test("Thousands abbreviate with one decimal, trimming a trailing .0")
    func abbreviatesThousands() {
        #expect(abbreviatedLineCount(1000) == "1k")
        #expect(abbreviatedLineCount(1200) == "1.2k")
        #expect(abbreviatedLineCount(2000) == "2k")
    }

    @Test("Ten thousand and above drop the decimal")
    func abbreviatesTensOfThousands() {
        #expect(abbreviatedLineCount(12000) == "12k")
        #expect(abbreviatedLineCount(12345) == "12k")
    }
}
