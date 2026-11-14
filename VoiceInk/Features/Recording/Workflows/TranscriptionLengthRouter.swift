import Foundation

/// Runs at most one second pass, preserving the first transcript if that pass fails.
enum TranscriptionLengthRouter {
    struct Result {
        let text: String
        let didSwitchModel: Bool
        let routingError: Error?
    }

    enum RoutingError: LocalizedError {
        case unavailableModel
        case emptyTranscript

        var errorDescription: String? {
            switch self {
            case .unavailableModel:
                return String(localized: "The model for longer transcriptions is unavailable. Check AI Models.")
            case .emptyTranscript:
                return String(localized: "The model for longer transcriptions returned no text.")
            }
        }
    }

    @MainActor
    static func route(
        _ text: String,
        primaryModelKey: String,
        rule: TranscriptionLengthRoute?,
        shouldCancel: () -> Bool = { false },
        retranscribe: (String) async throws -> String
    ) async throws -> Result {
        func checkCancellation() throws {
            try Task.checkCancellation()
            if shouldCancel() { throw CancellationError() }
        }

        try checkCancellation()
        guard let rule, rule.shouldRetranscribe(text, primaryModelKey: primaryModelKey) else {
            return Result(text: text, didSwitchModel: false, routingError: nil)
        }

        do {
            let secondText = try await retranscribe(rule.modelSelectionKey)
            try checkCancellation()
            guard !secondText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RoutingError.emptyTranscript
            }
            return Result(text: secondText, didSwitchModel: true, routingError: nil)
        } catch {
            try checkCancellation()
            if error is CancellationError { throw error }
            return Result(text: text, didSwitchModel: false, routingError: error)
        }
    }
}
