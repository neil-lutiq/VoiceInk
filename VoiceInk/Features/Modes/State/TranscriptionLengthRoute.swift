import Foundation

/// Re-transcribe the original audio when the first, unformatted transcript exceeds the limit.
struct TranscriptionLengthRoute: Codable, Equatable {
    var characterThreshold: Int
    var modelSelectionKey: String

    init(characterThreshold: Int = 300, modelSelectionKey: String) {
        self.characterThreshold = max(0, characterThreshold)
        self.modelSelectionKey = modelSelectionKey
    }

    func shouldRetranscribe(_ text: String, primaryModelKey: String) -> Bool {
        !modelSelectionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && modelSelectionKey != primaryModelKey
            && text.count > max(0, characterThreshold)
    }
}
