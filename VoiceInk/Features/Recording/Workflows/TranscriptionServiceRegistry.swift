import Foundation
import SwiftData
import SwiftUI
import os

@MainActor
class TranscriptionServiceRegistry {
    private weak var modelProvider: (any WhisperModelProvider)?
    private let modelsDirectory: URL
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TranscriptionServiceRegistry")

    private(set) lazy var localTranscriptionService = WhisperTranscriptionService(
        modelsDirectory: modelsDirectory,
        modelProvider: modelProvider
    )
    private(set) lazy var cloudTranscriptionService = CloudTranscriptionService()
    private(set) lazy var nativeAppleTranscriptionService = NativeAppleTranscriptionService()
    private(set) lazy var fluidAudioTranscriptionService = FluidAudioTranscriptionService()
    private var cachedTranscribeCppTranscriptionService: TranscribeCppTranscriptionService?

    var transcribeCppTranscriptionService: TranscribeCppTranscriptionService {
        if let cachedTranscribeCppTranscriptionService {
            return cachedTranscribeCppTranscriptionService
        }
        let service = TranscribeCppTranscriptionService()
        cachedTranscribeCppTranscriptionService = service
        return service
    }

    init(modelProvider: any WhisperModelProvider, modelsDirectory: URL, modelContext: ModelContext) {
        self.modelProvider = modelProvider
        self.modelsDirectory = modelsDirectory
        self.modelContext = modelContext
    }

    func service(for provider: ModelProvider) -> TranscriptionService {
        switch provider {
        case .whisper:
            return localTranscriptionService
        case .fluidAudio:
            return fluidAudioTranscriptionService
        case .transcribeCpp:
            return transcribeCppTranscriptionService
        case .nativeApple:
            return nativeAppleTranscriptionService
        default:
            return cloudTranscriptionService
        }
    }

    func transcribe(
        audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext = .currentDefaults
    ) async throws -> String {
        let service = service(for: model.provider)
        logger.debug(
            "Transcribing with \(model.displayName, privacy: .public) using \(String(describing: type(of: service)), privacy: .public)"
        )
        let vocabulary = context.vocabulary ?? CustomVocabularyService.shared.loadSavedVocabulary(from: modelContext)
        return try await service.transcribe(
            audioURL: audioURL, model: model, context: context.withVocabulary(vocabulary).scoped(to: model)
        )
    }

    /// Selects the final transcript before formatting or enhancement, using a single optional batch pass.
    func routeLongTranscription(
        _ text: String,
        audioURL: URL,
        configuration: TranscriptionRuntimeConfiguration,
        vocabulary: RecordingVocabulary,
        shouldCancel: () -> Bool = { false }
    ) async throws -> (text: String, model: any TranscriptionModel) {
        let primaryModel = configuration.model
        let targetModel = configuration.longTranscriptionModel
        let result = try await TranscriptionLengthRouter.route(
            text,
            primaryModelKey: primaryModel.selectionKey,
            rule: configuration.mode.longTranscriptionRoute,
            shouldCancel: shouldCancel
        ) { modelKey in
            guard let targetModel,
                targetModel.selectionKey == modelKey,
                targetModel.selectionKey != primaryModel.selectionKey,
                !TranscriptionRealtimeSupport.isRequired(for: targetModel)
            else {
                throw TranscriptionLengthRouter.RoutingError.unavailableModel
            }

            let language = TranscriptionLanguageSupport.validLanguageOrFallback(
                configuration.mode.selectedLanguage, for: targetModel, realtimeEnabled: false
            )
            let context = TranscriptionRequestContext(
                language: language,
                prompt: targetModel.provider == .whisper ? WhisperPrompt.resolvedPrompt(for: language) : nil,
                vocabulary: vocabulary
            )
            let secondText = try await self.transcribe(audioURL: audioURL, model: targetModel, context: context)
            return TranscriptionOutputFilter.filter(secondText, language: language)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let error = result.routingError {
            logger.warning("Long transcription second pass failed: \(error.localizedDescription, privacy: .public)")
            NotificationManager.shared.showNotification(
                title: String(
                    format: String(localized: "Kept the %@ transcript. The second transcription failed: %@"),
                    primaryModel.displayName, error.localizedDescription
                ),
                type: .warning
            )
        }

        return (result.text, result.didSwitchModel ? (targetModel ?? primaryModel) : primaryModel)
    }

    /// Creates a streaming or file-based session for the resolved transcription configuration.
    func createSession(
        for configuration: TranscriptionRuntimeConfiguration, onPartialTranscript: ((String) -> Void)? = nil
    ) -> TranscriptionSession {
        let model = configuration.model

        if shouldUseRealtimeTranscription(for: configuration) {
            let streamingService = StreamingTranscriptionService(
                fluidAudioService: model.provider == .fluidAudio ? fluidAudioTranscriptionService : nil,
                onPartialTranscript: onPartialTranscript
            )
            let fallback = service(for: model.provider)
            return StreamingTranscriptionSession(streamingService: streamingService, fallbackService: fallback)
        } else {
            return FileTranscriptionSession(service: service(for: model.provider))
        }
    }

    /// Whether the resolved transcription configuration should use real-time transcription.
    func shouldUseRealtimeTranscription(for configuration: TranscriptionRuntimeConfiguration) -> Bool {
        configuration.isRealtimeEnabled
    }

    func cleanup() async {
        await fluidAudioTranscriptionService.cleanup()
        cachedTranscribeCppTranscriptionService?.cleanup()
    }
}
