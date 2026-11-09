import Foundation

/// Decides locally whether a transcript should be sent to an enhancement provider.
enum EnhancementLengthPolicy {
    static func allows(_ text: String, threshold: Int?) -> Bool {
        guard let threshold else { return true }
        // String.count counts user-perceived Unicode characters, not UTF-8 bytes.
        return text.count > max(0, threshold)
    }
}
