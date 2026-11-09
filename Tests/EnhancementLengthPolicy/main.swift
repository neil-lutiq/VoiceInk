import Foundation
var checks = 0
for length in [0, 1, 299, 300, 301, 1000] {
    let text = String(repeating: "x", count: length)
    precondition(EnhancementLengthPolicy.allows(text, threshold: nil))
    precondition(EnhancementLengthPolicy.allows(text, threshold: 300) == (length > 300))
    checks += 2
}
for character in ["你", "👨‍👩‍👧‍👦", "e\u{301}"] {
    precondition(!EnhancementLengthPolicy.allows(String(repeating: character, count: 300), threshold: 300))
    precondition(EnhancementLengthPolicy.allows(String(repeating: character, count: 301), threshold: 300))
    checks += 2
}
precondition(EnhancementLengthPolicy.allows(String(repeating: "a ", count: 150) + ".", threshold: 300))
precondition(!EnhancementLengthPolicy.allows(String(repeating: "a\n", count: 150), threshold: 300))
precondition(!EnhancementLengthPolicy.allows("", threshold: 0))
precondition(EnhancementLengthPolicy.allows("a", threshold: -1))
checks += 4
print("Passed \(checks) character-threshold checks: boundaries, disabled option, whitespace, and Unicode.")
