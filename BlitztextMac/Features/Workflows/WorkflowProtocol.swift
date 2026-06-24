import Foundation

// MARK: - Workflow Types

enum WorkflowType: String, CaseIterable, Identifiable, Codable {
    case transcription
    case localTranscription
    case textImprover
    case dampfAblassen
    case emojiText

    var id: String { rawValue }

    static var mainMenuCases: [WorkflowType] {
        allCases.filter { $0 != .localTranscription }
    }

    var displayName: String {
        switch self {
        case .transcription: return "Blitztext"
        case .localTranscription: return "Blitztext Lokal"
        case .textImprover: return "Blitztext+"
        case .dampfAblassen: return "Blitztext $%&!"
        case .emojiText: return "Blitztext :)"
        }
    }

    var icon: String {
        switch self {
        case .transcription: return "mic.fill"
        case .localTranscription: return "lock.shield.fill"
        case .textImprover: return "text.badge.checkmark"
        case .dampfAblassen: return "flame.fill"
        case .emojiText: return "face.smiling"
        }
    }

    var subtitle: String {
        switch self {
        case .transcription: return "Sprache rein. Text raus."
        case .localTranscription: return "Nur lokal. Kein Server."
        case .textImprover: return "Geschrieben sprechen."
        case .dampfAblassen: return "Frust rein. Entspannt raus."
        case .emojiText: return "Text rein. Emojis dazu."
        }
    }

    var hotkeyLabel: String {
        switch self {
        case .transcription: return "fn + Shift"
        case .localTranscription: return "fn + Shift + Ctrl"
        case .textImprover: return "fn + Control"
        case .dampfAblassen: return "fn + Option"
        case .emojiText: return "fn + Cmd"
        }
    }

    var accentColor: String {
        switch self {
        case .transcription: return "blue"
        case .localTranscription: return "green"
        case .textImprover: return "purple"
        case .dampfAblassen: return "orange"
        case .emojiText: return "cyan"
        }
    }
}

// MARK: - Workflow State

enum WorkflowPhase: Equatable {
    case idle
    case running(String)
    case done(String)
    case error(String)

    var isActive: Bool {
        switch self {
        case .idle: return false
        default: return true
        }
    }
}

enum WorkflowLaunchSource: Equatable {
    case manual
    case hotkeyBackground

    var presentsWorkflowPage: Bool {
        switch self {
        case .manual:
            return true
        case .hotkeyBackground:
            return false
        }
    }
}

typealias WorkflowOutputHandler = @MainActor (String) -> Void
typealias WorkflowPhaseChangeHandler = @MainActor (WorkflowPhase) -> Void

// MARK: - Workflow Protocol

@MainActor
protocol Workflow: AnyObject, Observable {
    var type: WorkflowType { get }
    var phase: WorkflowPhase { get set }
    var isRecording: Bool { get }
    var onOutput: WorkflowOutputHandler? { get set }
    var onPhaseChange: WorkflowPhaseChangeHandler? { get set }

    func start()
    func stop()
    func reset()
}

// MARK: - App Settings

enum SpeechProviderKind: String, Codable, CaseIterable, Identifiable {
    case localWhisperKit
    case openAI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .localWhisperKit: return "Lokal: WhisperKit"
        case .openAI: return "OpenAI Whisper"
        }
    }
}

struct AppSettings: Codable {
    static let defaultOllamaBaseURL = "http://localhost:11434"
    static let defaultOllamaModel = "llama3.1"
    static let defaultOpenAISpeechModel = "whisper-1"
    static let defaultAzureFoundryAPIVersion = "2024-05-01-preview"

    var hotkeyMode: HotkeyMode = .hold
    var hasSeenOnboarding: Bool = false
    var secureLocalModeEnabled: Bool = true
    var speechProvider: SpeechProviderKind = .localWhisperKit
    var textProvider: TextProviderKind = .ollama
    var selectedLocalTranscriptionModelName: String = LocalTranscriptionService.recommendedFastModelName
    var hasAutoSelectedFastLocalModel: Bool = false
    var ollamaBaseURL: String = Self.defaultOllamaBaseURL
    var ollamaModel: String = Self.defaultOllamaModel
    var openAISpeechModel: String = Self.defaultOpenAISpeechModel
    var openAITextModel: String = ""
    var azureFoundryEndpoint: String = ""
    var azureFoundryDeploymentName: String = ""
    var azureFoundryAPIVersion: String = Self.defaultAzureFoundryAPIVersion

    init(
        hotkeyMode: HotkeyMode = .hold,
        hasSeenOnboarding: Bool = false,
        secureLocalModeEnabled: Bool = true,
        speechProvider: SpeechProviderKind = .localWhisperKit,
        textProvider: TextProviderKind = .ollama,
        selectedLocalTranscriptionModelName: String = LocalTranscriptionService.recommendedFastModelName,
        hasAutoSelectedFastLocalModel: Bool = false,
        ollamaBaseURL: String = Self.defaultOllamaBaseURL,
        ollamaModel: String = Self.defaultOllamaModel,
        openAISpeechModel: String = Self.defaultOpenAISpeechModel,
        openAITextModel: String = "",
        azureFoundryEndpoint: String = "",
        azureFoundryDeploymentName: String = "",
        azureFoundryAPIVersion: String = Self.defaultAzureFoundryAPIVersion
    ) {
        self.hotkeyMode = hotkeyMode
        self.hasSeenOnboarding = hasSeenOnboarding
        self.secureLocalModeEnabled = secureLocalModeEnabled
        self.speechProvider = speechProvider
        self.textProvider = textProvider
        self.selectedLocalTranscriptionModelName = selectedLocalTranscriptionModelName
        self.hasAutoSelectedFastLocalModel = hasAutoSelectedFastLocalModel
        self.ollamaBaseURL = ollamaBaseURL
        self.ollamaModel = ollamaModel
        self.openAISpeechModel = openAISpeechModel
        self.openAITextModel = openAITextModel
        self.azureFoundryEndpoint = azureFoundryEndpoint
        self.azureFoundryDeploymentName = azureFoundryDeploymentName
        self.azureFoundryAPIVersion = azureFoundryAPIVersion
    }

    enum CodingKeys: String, CodingKey {
        case hotkeyMode
        case hasSeenOnboarding
        case secureLocalModeEnabled
        case speechProvider
        case textProvider
        case selectedLocalTranscriptionModelName
        case hasAutoSelectedFastLocalModel
        case ollamaBaseURL
        case ollamaModel
        case openAISpeechModel
        case openAITextModel
        case azureFoundryEndpoint
        case azureFoundryDeploymentName
        case azureFoundryAPIVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hotkeyMode = try container.decodeIfPresent(HotkeyMode.self, forKey: .hotkeyMode) ?? .hold
        hasSeenOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasSeenOnboarding) ?? false
        let storedLocalMode = try container.decodeIfPresent(Bool.self, forKey: .secureLocalModeEnabled)
        secureLocalModeEnabled = storedLocalMode ?? true
        speechProvider = try container.decodeIfPresent(
            SpeechProviderKind.self,
            forKey: .speechProvider
        ) ?? (secureLocalModeEnabled ? .localWhisperKit : .openAI)
        textProvider = try container.decodeIfPresent(
            TextProviderKind.self,
            forKey: .textProvider
        ) ?? (secureLocalModeEnabled ? .ollama : .openAI)
        selectedLocalTranscriptionModelName = try container.decodeIfPresent(
            String.self,
            forKey: .selectedLocalTranscriptionModelName
        ) ?? LocalTranscriptionService.recommendedFastModelName
        hasAutoSelectedFastLocalModel = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasAutoSelectedFastLocalModel
        ) ?? false
        ollamaBaseURL = try container.decodeIfPresent(
            String.self,
            forKey: .ollamaBaseURL
        ) ?? Self.defaultOllamaBaseURL
        ollamaModel = try container.decodeIfPresent(
            String.self,
            forKey: .ollamaModel
        ) ?? Self.defaultOllamaModel
        openAISpeechModel = try container.decodeIfPresent(
            String.self,
            forKey: .openAISpeechModel
        ) ?? Self.defaultOpenAISpeechModel
        openAITextModel = try container.decodeIfPresent(
            String.self,
            forKey: .openAITextModel
        ) ?? ""
        azureFoundryEndpoint = try container.decodeIfPresent(
            String.self,
            forKey: .azureFoundryEndpoint
        ) ?? ""
        azureFoundryDeploymentName = try container.decodeIfPresent(
            String.self,
            forKey: .azureFoundryDeploymentName
        ) ?? ""
        azureFoundryAPIVersion = try container.decodeIfPresent(
            String.self,
            forKey: .azureFoundryAPIVersion
        ) ?? Self.defaultAzureFoundryAPIVersion
    }
}

enum TranscriptionBackend: String, Codable {
    case remote
    case local
}

struct RewritePipelineConfiguration {
    let transcriptionBackend: TranscriptionBackend
    let localTranscriptionModelName: String
    let remoteTranscriptionModelName: String
    let textGenerationConfiguration: TextGenerationConfiguration

    var usesLocalTranscription: Bool {
        transcriptionBackend == .local
    }

    var usesLocalTextGeneration: Bool {
        textGenerationConfiguration.providerKind == .ollama
    }

    static func remoteOpenAI() -> RewritePipelineConfiguration {
        RewritePipelineConfiguration(
            transcriptionBackend: .remote,
            localTranscriptionModelName: LocalTranscriptionService.recommendedFastModelName,
            remoteTranscriptionModelName: AppSettings.defaultOpenAISpeechModel,
            textGenerationConfiguration: .openAI()
        )
    }
}

// MARK: - Workflow Settings

struct TranscriptionSettings: Codable {
    var language: String = "de"
}

struct DampfAblassenSettings: Codable {
    var systemPrompt: String = "Du erhältst ein emotional gesprochenes Transkript. Erkenne zuerst das eigentliche Ziel, Anliegen und den wahren Frust der Person. Formuliere daraus eine klare, respektvolle und wirksame Nachricht, mit der die Person ihr Ziel eher erreicht. Bewahre relevante Fakten, konkrete Probleme, Grenzen, Erwartungen und die nötige Dringlichkeit. Entferne Beleidigungen, Drohungen, Sarkasmus, Unterstellungen und unnötige Eskalation. Wenn mehrere Vorwürfe genannt werden, verdichte sie auf die entscheidenden Kernpunkte. Der Ton soll ruhig, menschlich, bestimmt und lösungsorientiert sein. Gib NUR die fertige Nachricht zurück."
    var customName: String = ""
}

struct EmojiTextSettings: Codable {
    var emojiDensity: EmojiDensity = .mittel
    var customName: String = ""

    enum EmojiDensity: String, Codable, CaseIterable, Identifiable {
        case wenig
        case mittel
        case viel

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .wenig: return "Wenig"
            case .mittel: return "Mittel"
            case .viel: return "Viel"
            }
        }
    }
}

struct TextImprovementSettings: Codable {
    var systemPrompt: String = ""
    var customTerms: [String] = []
    var context: String = ""
    var tone: TextTone = .neutral
    var customName: String = ""

    enum TextTone: String, Codable, CaseIterable, Identifiable {
        case formal
        case neutral
        case casual

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .formal: return "Formell"
            case .neutral: return "Neutral"
            case .casual: return "Locker"
            }
        }
    }
}
