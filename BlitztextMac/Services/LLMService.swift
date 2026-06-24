import Foundation

enum LLMError: LocalizedError {
    case notConfigured
    case networkError(String)
    case apiError(String)
    case noContent
    case ollamaUnavailable
    case ollamaModelMissing(String)
    case ollamaRequestFailed(String)
    case invalidProviderConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "OpenAI API Key fehlt. Bitte in den Einstellungen hinterlegen."
        case .networkError(let msg):
            return "Verbindungsproblem: \(msg)"
        case .apiError(let msg):
            return "Fehler von OpenAI: \(msg)"
        case .noContent:
            return "Keine Antwort erhalten. Bitte nochmal versuchen."
        case .ollamaUnavailable:
            return "Ollama läuft nicht oder ist unter der eingestellten Adresse nicht erreichbar."
        case .ollamaModelMissing(let model):
            return "Ollama ist erreichbar, aber das Modell \"\(model)\" ist nicht installiert. Bitte mit `ollama pull \(model)` laden oder ein anderes Modell auswählen."
        case .ollamaRequestFailed(let msg):
            return "Ollama-Fehler: \(msg)"
        case .invalidProviderConfiguration(let msg):
            return msg
        }
    }
}

enum RewriteModel: String {
    case fastEdit = "gpt-4o-mini"
    case rageMode = "gpt-4o"
}

enum TextProviderKind: String, Codable, CaseIterable, Identifiable {
    case openAI = "openai"
    case ollama
    case azureFoundryClaude

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .ollama: return "Lokal: Ollama"
        case .azureFoundryClaude: return "Azure Foundry Claude"
        }
    }
}

struct TextGenerationRequest {
    let provider: TextProviderKind
    let model: String
    let systemPrompt: String
    let inputText: String
    let temperature: Double
}

struct TextGenerationResponse {
    let provider: TextProviderKind
    let model: String
    let text: String
}

struct TextGenerationConfiguration {
    let providerKind: TextProviderKind
    let ollamaBaseURL: String
    let ollamaModel: String
    let openAIModel: String?

    static func openAI(model: String? = nil) -> TextGenerationConfiguration {
        TextGenerationConfiguration(
            providerKind: .openAI,
            ollamaBaseURL: AppSettings.defaultOllamaBaseURL,
            ollamaModel: AppSettings.defaultOllamaModel,
            openAIModel: model
        )
    }

    static func ollama(baseURL: String, model: String) -> TextGenerationConfiguration {
        TextGenerationConfiguration(
            providerKind: .ollama,
            ollamaBaseURL: baseURL,
            ollamaModel: model,
            openAIModel: nil
        )
    }

    static func azureFoundryClaude() -> TextGenerationConfiguration {
        TextGenerationConfiguration(
            providerKind: .azureFoundryClaude,
            ollamaBaseURL: AppSettings.defaultOllamaBaseURL,
            ollamaModel: AppSettings.defaultOllamaModel,
            openAIModel: nil
        )
    }
}

protocol TextGenerating: Sendable {
    var kind: TextProviderKind { get }

    func generateText(request: TextGenerationRequest) async throws -> TextGenerationResponse
}

enum TextProviderFactory {
    static func makeProvider(configuration: TextGenerationConfiguration) throws -> any TextGenerating {
        switch configuration.providerKind {
        case .openAI:
            return OpenAITextProvider()
        case .ollama:
            return try OllamaTextProvider(
                baseURLString: configuration.ollamaBaseURL,
                model: configuration.ollamaModel
            )
        case .azureFoundryClaude:
            throw LLMError.invalidProviderConfiguration("Azure Foundry Claude ist in dieser Preview noch nicht konfiguriert.")
        }
    }
}

private struct OpenAITextProvider: TextGenerating {
    private struct ChatRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let messages: [Message]
        let temperature: Double
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }

            let message: Message?
        }

        let choices: [Choice]?
    }

    private struct ErrorResponse: Decodable {
        struct APIError: Decodable {
            let message: String?
        }

        let error: APIError?
    }

    let kind: TextProviderKind = .openAI

    private static let chatCompletionsURL = URL(string: "https://api.openai.com/v1/chat/completions")!

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 45
        return URLSession(configuration: configuration)
    }()

    func generateText(request: TextGenerationRequest) async throws -> TextGenerationResponse {
        guard let apiKey = KeychainService.load(key: .openAIAPIKey) else {
            throw LLMError.notConfigured
        }

        let payload = ChatRequest(
            model: request.model,
            messages: [
                .init(role: "system", content: request.systemPrompt),
                .init(role: "user", content: request.inputText),
            ],
            temperature: request.temperature
        )

        var urlRequest = URLRequest(url: Self.chatCompletionsURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 45
        urlRequest.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await Self.session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.networkError("Keine gültige Antwort")
        }

        guard httpResponse.statusCode == 200 else {
            throw LLMError.apiError(openAIErrorMessage(from: data) ?? "Status \(httpResponse.statusCode)")
        }

        let result = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = result.choices?.first?.message?.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.noContent
        }

        return TextGenerationResponse(
            provider: kind,
            model: request.model,
            text: content.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func openAIErrorMessage(from data: Data) -> String? {
        (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error?.message
    }
}

enum OllamaHealthStatus: Equatable {
    case notRunning
    case reachable
    case modelMissing(String)
    case requestFailed(String)
}

private struct OllamaTextProvider: TextGenerating {
    private struct ChatRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        struct Options: Encodable {
            let temperature: Double
        }

        let model: String
        let messages: [Message]
        let stream: Bool
        let options: Options
    }

    private struct ChatResponse: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message?
        let response: String?
        let error: String?
    }

    private struct TagsResponse: Decodable {
        struct Model: Decodable {
            let name: String
        }

        let models: [Model]?
    }

    let kind: TextProviderKind = .ollama

    private let baseURL: URL
    private let model: String

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    init(baseURLString: String, model: String) throws {
        let trimmedBaseURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: trimmedBaseURL), let scheme = url.scheme, !scheme.isEmpty else {
            throw LLMError.invalidProviderConfiguration("Ollama-Adresse ist ungültig.")
        }
        guard !trimmedModel.isEmpty else {
            throw LLMError.invalidProviderConfiguration("Kein Ollama-Modell ausgewählt.")
        }

        self.baseURL = url
        self.model = trimmedModel
    }

    static func healthCheck(baseURLString: String, model: String?) async -> OllamaHealthStatus {
        do {
            let trimmedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
            let requestedModel: String
            if let trimmedModel, !trimmedModel.isEmpty {
                requestedModel = trimmedModel
            } else {
                requestedModel = AppSettings.defaultOllamaModel
            }
            let provider = try OllamaTextProvider(
                baseURLString: baseURLString,
                model: requestedModel
            )
            return try await provider.healthStatus(requiredModel: trimmedModel)
        } catch let error as LLMError {
            return .requestFailed(error.localizedDescription)
        } catch {
            return .requestFailed(error.localizedDescription)
        }
    }

    func generateText(request: TextGenerationRequest) async throws -> TextGenerationResponse {
        let health = try await healthStatus(requiredModel: model)
        switch health {
        case .reachable:
            break
        case .notRunning:
            throw LLMError.ollamaUnavailable
        case .modelMissing(let missingModel):
            throw LLMError.ollamaModelMissing(missingModel)
        case .requestFailed(let message):
            throw LLMError.networkError(message)
        }

        let payload = ChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: request.systemPrompt),
                .init(role: "user", content: request.inputText),
            ],
            stream: false,
            options: .init(temperature: request.temperature)
        )

        var urlRequest = URLRequest(url: endpoint("api/chat"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 30
        urlRequest.httpBody = try JSONEncoder().encode(payload)

        do {
            let (data, response) = try await Self.session.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LLMError.networkError("Keine gültige Antwort von Ollama.")
            }

            let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data)
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw LLMError.ollamaRequestFailed(decoded?.error ?? "Status \(httpResponse.statusCode)")
            }
            if let error = decoded?.error, !error.isEmpty {
                throw LLMError.ollamaRequestFailed(error)
            }

            let content = decoded?.message?.content ?? decoded?.response
            guard let content,
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LLMError.noContent
            }

            return TextGenerationResponse(
                provider: kind,
                model: model,
                text: content.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch let error as LLMError {
            throw error
        } catch let error as URLError where error.code == .cannotConnectToHost || error.code == .notConnectedToInternet {
            throw LLMError.ollamaUnavailable
        } catch {
            throw LLMError.networkError(error.localizedDescription)
        }
    }

    private func healthStatus(requiredModel: String?) async throws -> OllamaHealthStatus {
        var request = URLRequest(url: endpoint("api/tags"))
        request.httpMethod = "GET"
        request.timeoutInterval = 2.5

        do {
            let (data, response) = try await Self.session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .requestFailed("Keine gültige Antwort von Ollama.")
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                return .requestFailed("Ollama-Status \(httpResponse.statusCode)")
            }

            guard let requiredModel, !requiredModel.isEmpty else {
                return .reachable
            }

            let tags = try JSONDecoder().decode(TagsResponse.self, from: data)
            let modelNames = tags.models?.map(\.name) ?? []
            guard modelNames.contains(where: { installedModelMatches($0, requiredModel: requiredModel) }) else {
                return .modelMissing(requiredModel)
            }

            return .reachable
        } catch let error as URLError where error.code == .cannotConnectToHost || error.code == .notConnectedToInternet {
            return .notRunning
        } catch {
            return .requestFailed(error.localizedDescription)
        }
    }

    private func endpoint(_ path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }

    private func installedModelMatches(_ installedModel: String, requiredModel: String) -> Bool {
        installedModel == requiredModel || installedModel.hasPrefix("\(requiredModel):")
    }
}

enum LLMService {
    static func improve(
        text: String,
        settings: TextImprovementSettings,
        model: RewriteModel = .fastEdit,
        providerConfiguration: TextGenerationConfiguration = .openAI()
    ) async throws -> String {
        try await complete(
            text: text,
            systemPrompt: buildSystemPrompt(settings: settings),
            model: model,
            temperature: 0.3,
            providerConfiguration: providerConfiguration
        )
    }

    static func dampfAblassen(
        text: String,
        systemPrompt: String,
        model: RewriteModel = .rageMode,
        providerConfiguration: TextGenerationConfiguration = .openAI()
    ) async throws -> String {
        try await complete(
            text: text,
            systemPrompt: systemPrompt,
            model: model,
            temperature: 0.4,
            providerConfiguration: providerConfiguration
        )
    }

    static func addEmojis(
        text: String,
        settings: EmojiTextSettings,
        model: RewriteModel = .fastEdit,
        providerConfiguration: TextGenerationConfiguration = .openAI()
    ) async throws -> String {
        try await complete(
            text: text,
            systemPrompt: buildEmojiSystemPrompt(density: settings.emojiDensity),
            model: model,
            temperature: 0.3,
            providerConfiguration: providerConfiguration
        )
    }

    static func ollamaHealthStatus(baseURL: String, model: String?) async -> OllamaHealthStatus {
        await OllamaTextProvider.healthCheck(baseURLString: baseURL, model: model)
    }

    private static func complete(
        text: String,
        systemPrompt: String,
        model: RewriteModel,
        temperature: Double,
        providerConfiguration: TextGenerationConfiguration
    ) async throws -> String {
        let provider = try TextProviderFactory.makeProvider(configuration: providerConfiguration)
        let requestedModel: String
        switch provider.kind {
        case .ollama:
            requestedModel = providerConfiguration.ollamaModel
        case .openAI:
            if let openAIModel = providerConfiguration.openAIModel?.trimmingCharacters(in: .whitespacesAndNewlines),
               !openAIModel.isEmpty {
                requestedModel = openAIModel
            } else {
                requestedModel = model.rawValue
            }
        case .azureFoundryClaude:
            requestedModel = model.rawValue
        }
        let request = TextGenerationRequest(
            provider: provider.kind,
            model: requestedModel,
            systemPrompt: systemPrompt,
            inputText: text,
            temperature: temperature
        )

        return try await provider.generateText(request: request).text
    }

    private static func buildEmojiSystemPrompt(density: EmojiTextSettings.EmojiDensity) -> String {
        let densityInstruction: String
        switch density {
        case .wenig:
            densityInstruction = "Setze nur vereinzelt Emojis ein, maximal 1-2 pro Absatz."
        case .mittel:
            densityInstruction = "Setze regelmaessig passende Emojis ein, etwa alle 1-2 Saetze."
        case .viel:
            densityInstruction = "Setze grosszuegig Emojis ein, gerne mehrere pro Satz."
        }

        return "Du erhaeltst ein gesprochenes Transkript. Gib den Text moeglichst originalgetreu zurueck, aber fuege passende Emojis ein. \(densityInstruction) Korrigiere offensichtliche Sprach- und Grammatikfehler. Behalte den Stil und die Bedeutung bei. Gib NUR den Text mit Emojis zurueck, keine Erklaerungen."
    }

    private static func buildSystemPrompt(settings: TextImprovementSettings) -> String {
        if !settings.systemPrompt.isEmpty {
            var prompt = settings.systemPrompt
            if !settings.customTerms.isEmpty {
                prompt += "\n\nWichtig: Diese Eigennamen und Fachbegriffe muessen exakt so geschrieben werden: \(settings.customTerms.joined(separator: ", "))"
            }
            return prompt
        }

        var prompt = """
        Du bist ein Lektor und Schreibassistent. Verbessere den folgenden Text:
        - Korrigiere Rechtschreibung und Grammatik
        - Verbessere die Formulierung und den Lesefluss
        - Behalte die urspruengliche Bedeutung bei
        - Gib NUR den verbesserten Text zurueck, keine Erklaerungen
        """

        switch settings.tone {
        case .formal:
            prompt += "\n- Verwende einen formellen, professionellen Ton"
        case .neutral:
            prompt += "\n- Verwende einen neutralen, klaren Ton"
        case .casual:
            prompt += "\n- Verwende einen lockeren, natuerlichen Ton"
        }

        if !settings.customTerms.isEmpty {
            prompt += "\n\nWichtig: Diese Eigennamen und Fachbegriffe muessen exakt so geschrieben werden: \(settings.customTerms.joined(separator: ", "))"
        }

        if !settings.context.isEmpty {
            prompt += "\n\nKontext: \(settings.context)"
        }

        return prompt
    }
}
