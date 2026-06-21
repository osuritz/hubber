import Foundation

/// Abbreviates a non-negative line count for compact display:
/// 0–999 render verbatim, 1_000+ as a "k" suffix ("1.2k", "12k").
/// Counts below 10_000 keep one decimal (trimming a trailing ".0"); larger
/// counts drop the decimal entirely.
func abbreviatedLineCount(_ value: Int) -> String {
    guard value >= 1000 else { return "\(value)" }
    let thousands = Double(value) / 1000
    if thousands < 10 {
        let formatted = String(format: "%.1fk", thousands)
        return formatted.replacingOccurrences(of: ".0k", with: "k")
    }
    return "\(Int(thousands.rounded()))k"
}
