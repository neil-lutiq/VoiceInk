import Foundation

@main
struct TranscriptionLengthRoutingTests {
    @MainActor
    static func main() async throws {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }

        let primary = "parakeet-ultra"
        let rule = TranscriptionLengthRoute(characterThreshold: 300, modelSelectionKey: "scribe_v3")

        // A short first pass must never call the second service; only 301+ does.
        for count in [0, 1, 299, 300, 301, 1000] {
            var calls: [String] = []
            let text = String(repeating: "x", count: count)
            let result = try await TranscriptionLengthRouter.route(text, primaryModelKey: primary, rule: rule) { key in
                calls.append(key)
                return "Scribe output"
            }
            check(calls == (count > 300 ? ["scribe_v3"] : []), "Wrong routing at \(count) characters")
            check(result.text == (count > 300 ? "Scribe output" : text), "Wrong final transcript")
            check(result.didSwitchModel == (count > 300), "Wrong final model")
            check(result.routingError == nil, "Unexpected routing failure")
        }

        for character in ["你", "👨‍👩‍👧‍👦", "e\u{301}"] {
            check(!rule.shouldRetranscribe(String(repeating: character, count: 300), primaryModelKey: primary),
                  "300 user-perceived characters must stay local")
            check(rule.shouldRetranscribe(String(repeating: character, count: 301), primaryModelKey: primary),
                  "301 user-perceived characters must switch")
        }
        check(rule.shouldRetranscribe(String(repeating: "a ", count: 150) + ".", primaryModelKey: primary),
              "Spaces and punctuation must count")
        check(!rule.shouldRetranscribe(String(repeating: "a\n", count: 150), primaryModelKey: primary),
              "Exactly 300 including newlines must stay local")

        let longText = String(repeating: "x", count: 301)
        for disabledRule in [nil, TranscriptionLengthRoute(modelSelectionKey: primary),
                             TranscriptionLengthRoute(modelSelectionKey: " ")] as [TranscriptionLengthRoute?] {
            let result = try await TranscriptionLengthRouter.route(longText, primaryModelKey: primary, rule: disabledRule) { _ in
                preconditionFailure("Disabled or identical model must not make a second request")
            }
            check(result.text == longText && !result.didSwitchModel && result.routingError == nil,
                  "Disabled route changed the result")
        }

        // The second pass runs once even if its result is also above the threshold.
        var calls = 0
        let longerText = String(repeating: "y", count: 1000)
        let longerResult = try await TranscriptionLengthRouter.route(longText, primaryModelKey: primary, rule: rule) { _ in
            calls += 1
            return longerText
        }
        check(calls == 1 && longerResult.text == longerText && longerResult.didSwitchModel, "Second pass recursed")

        enum TestError: Error { case offline }
        let failed = try await TranscriptionLengthRouter.route(longText, primaryModelKey: primary, rule: rule) { _ in
            throw TestError.offline
        }
        check(failed.text == longText && !failed.didSwitchModel, "Failure lost the first transcript")
        check(failed.routingError is TestError, "Failure must be reported")

        let empty = try await TranscriptionLengthRouter.route(longText, primaryModelKey: primary, rule: rule) { _ in " \n" }
        check(empty.text == longText && !empty.didSwitchModel && empty.routingError != nil,
              "Empty second response lost the first transcript")

        let unavailable = try await TranscriptionLengthRouter.route(longText, primaryModelKey: primary, rule: rule) { _ in
            throw TranscriptionLengthRouter.RoutingError.unavailableModel
        }
        check(unavailable.text == longText && !unavailable.didSwitchModel && unavailable.routingError != nil,
              "Unavailable model lost the first transcript")

        // Both the recorder's cancellation flag and Swift task cancellation must prevent delivery.
        do {
            _ = try await TranscriptionLengthRouter.route(longText, primaryModelKey: primary, rule: rule, shouldCancel: { true }) { _ in
                preconditionFailure("Cancelled recording uploaded audio")
            }
            preconditionFailure("Cancellation was swallowed")
        } catch is CancellationError { checks += 1 }

        var cancelled = false
        do {
            _ = try await TranscriptionLengthRouter.route(longText, primaryModelKey: primary, rule: rule, shouldCancel: { cancelled }) { _ in
                cancelled = true
                return "Late result"
            }
            preconditionFailure("Result delivered after cancellation")
        } catch is CancellationError { checks += 1 }

        do {
            _ = try await TranscriptionLengthRouter.route(longText, primaryModelKey: primary, rule: rule) { _ in
                throw CancellationError()
            }
            preconditionFailure("Cancellation treated as fallback")
        } catch is CancellationError { checks += 1 }

        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await TranscriptionLengthRouter.route(longText, primaryModelKey: primary, rule: rule) { _ in
                preconditionFailure("Cancelled task uploaded audio")
            }
        }
        do {
            _ = try await task.value
            preconditionFailure("Task cancellation ignored")
        } catch is CancellationError { checks += 1 }

        let decoded = try JSONDecoder().decode(TranscriptionLengthRoute.self, from: JSONEncoder().encode(rule))
        check(decoded == rule, "Saved routing rule did not round-trip")
        let negative = TranscriptionLengthRoute(characterThreshold: -1, modelSelectionKey: "scribe_v3")
        check(negative.characterThreshold == 0, "Negative threshold was not clamped")
        check(!negative.shouldRetranscribe("", primaryModelKey: primary), "Empty text must stay local")
        check(negative.shouldRetranscribe("a", primaryModelKey: primary), "Zero threshold should route nonempty text")

        print("Passed \(checks) transcription-routing checks: boundaries, Unicode, persistence, single second pass, fallback, and cancellation.")
    }
}
