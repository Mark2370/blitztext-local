import Foundation
import AppKit
import Observation

@Observable
@MainActor
final class TextImprovementWorkflow: Workflow {
    let type = WorkflowType.textImprover
    var phase: WorkflowPhase = .idle {
        didSet { onPhaseChange?(phase) }
    }
    var onOutput: WorkflowOutputHandler?
    var onPhaseChange: WorkflowPhaseChangeHandler?

    private let recorder = AudioRecorder()
    private let settings: TextImprovementSettings
    private let language: String
    private let pipeline: RewritePipelineConfiguration
    private var processingTask: Task<Void, Never>?

    init(
        settings: TextImprovementSettings,
        language: String = "de",
        pipeline: RewritePipelineConfiguration = .remoteOpenAI()
    ) {
        self.settings = settings
        self.language = language
        self.pipeline = pipeline
    }

    // MARK: - Recording State

    var isRecording: Bool { recorder.isRecording }
    var audioLevel: Float { recorder.audioLevel }

    // MARK: - Workflow Protocol

    func start() {
        phase = .running("Aufnahme läuft ...")
        recorder.startRecording()

        if let error = recorder.errorMessage {
            phase = .error(error)
        }
    }

    func stop() {
        if recorder.isRecording {
            recorder.stopRecording()
            guard !TranscriptionQualityService.shouldRejectRecording(duration: recorder.lastRecordingDuration) else {
                recorder.discardRecording()
                phase = .error("Keine Aufnahme erkannt.")
                return
            }
            processRecording()
        } else {
            processingTask?.cancel()
            phase = .idle
        }
    }

    func reset() {
        processingTask?.cancel()
        if recorder.isRecording {
            recorder.stopRecording()
        }
        recorder.discardRecording()
        phase = .idle
    }

    // MARK: - Two-Phase Processing: Transcription -> Text Generation

    private func processRecording() {
        guard let url = recorder.recordingURL else {
            phase = .error("Keine Aufnahme vorhanden.")
            return
        }

        phase = .running(pipeline.usesLocalTranscription ? "Wird lokal transkribiert ..." : "Wird transkribiert ...")
        let recordingDuration = recorder.lastRecordingDuration
        let vocabularyHints = recordingDuration >= 0.9 ? settings.customTerms : []
        let requestLanguage = language

        processingTask = Task {
            defer {
                try? FileManager.default.removeItem(at: url)
            }

            do {
                let rawText: String
                switch pipeline.transcriptionBackend {
                case .remote:
                    rawText = try await TranscriptionService.transcribe(
                        audioURL: url,
                        customTerms: vocabularyHints,
                        language: requestLanguage,
                        model: pipeline.remoteTranscriptionModelName
                    )
                case .local:
                    rawText = try await LocalTranscriptionService.shared.transcribe(
                        audioURL: url,
                        language: requestLanguage,
                        modelName: pipeline.localTranscriptionModelName
                    )
                }
                let cleanedRawText = TranscriptionQualityService.cleanedTranscript(rawText)
                guard !TranscriptionQualityService.isLikelyArtifact(cleanedRawText, recordingDuration: recordingDuration) else {
                    phase = .error("Keine Aufnahme erkannt.")
                    return
                }

                if Task.isCancelled { return }

                // Phase 2: Text improvement
                phase = .running(pipeline.usesLocalTextGeneration ? "Text wird lokal verbessert ..." : "Text wird verbessert ...")

                let improved = try await LLMService.improve(
                    text: cleanedRawText,
                    settings: settings,
                    providerConfiguration: pipeline.textGenerationConfiguration
                )

                let cleanedImproved = TranscriptionQualityService.cleanedTranscript(improved)
                phase = .done(cleanedImproved)
                onOutput?(cleanedImproved)
            } catch {
                phase = .error(error.localizedDescription)
            }
        }
    }
}
