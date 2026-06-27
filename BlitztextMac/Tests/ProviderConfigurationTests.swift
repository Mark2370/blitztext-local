import XCTest
@testable import Blitztext

final class ProviderConfigurationTests: XCTestCase {
    func testPromptGenerationIncludesToneContextAndTerms() {
        let settings = TextImprovementSettings(
            systemPrompt: "",
            customTerms: ["Blackboat", "Blitztext"],
            context: "Kurze Kundenmail",
            tone: .formal
        )

        let prompt = LLMService.buildSystemPrompt(settings: settings)

        XCTAssertTrue(prompt.contains("formellen"))
        XCTAssertTrue(prompt.contains("Blackboat, Blitztext"))
        XCTAssertTrue(prompt.contains("Kontext: Kurze Kundenmail"))
        XCTAssertTrue(prompt.contains("Gib NUR den verbesserten Text"))
    }

    func testDefaultTextCorrectionPromptMatchesPreMigrationPrompt() {
        let settings = TextImprovementSettings(
            systemPrompt: "",
            customTerms: [],
            context: "",
            tone: .neutral
        )

        let prompt = LLMService.buildSystemPrompt(settings: settings)

        XCTAssertEqual(
            prompt,
            """
            Du bist ein Lektor und Schreibassistent. Verbessere den folgenden Text:
            - Korrigiere Rechtschreibung und Grammatik
            - Verbessere die Formulierung und den Lesefluss
            - Behalte die urspruengliche Bedeutung bei
            - Gib NUR den verbesserten Text zurueck, keine Erklaerungen
            - Verwende einen neutralen, klaren Ton
            """
        )
    }

    func testTextCorrectionSystemPromptIsUsedForEveryTextProvider() {
        let settings = TextImprovementSettings(
            systemPrompt: "",
            customTerms: ["Blackboat"],
            context: "Interne Notiz",
            tone: .casual
        )
        let systemPrompt = LLMService.buildSystemPrompt(settings: settings)
        let providerConfigurations: [TextGenerationConfiguration] = [
            .openAI(model: "gpt-4o-mini"),
            .ollama(baseURL: "http://localhost:11434", model: "llama3.1"),
            .azureFoundryClaude(
                endpoint: "https://example.services.ai.azure.com",
                deploymentName: "claude-sonnet",
                apiVersion: "2024-05-01-preview"
            ),
        ]

        for configuration in providerConfigurations {
            let request = LLMService.buildTextGenerationRequest(
                text: "Das ist der zu korrigierende Text.",
                systemPrompt: systemPrompt,
                model: .fastEdit,
                temperature: 0.3,
                providerConfiguration: configuration
            )

            XCTAssertEqual(request.systemPrompt, systemPrompt)
            XCTAssertEqual(request.provider, configuration.providerKind)
            XCTAssertTrue(request.inputText.contains("Das ist der zu korrigierende Text."))
        }
    }

    func testCustomPromptKeepsTermsWithoutAddingDefaultInstructions() {
        let settings = TextImprovementSettings(
            systemPrompt: "Schreibe knapp.",
            customTerms: ["WhisperKit"],
            context: "Wird bei eigenem Prompt nicht automatisch angehaengt",
            tone: .casual
        )

        let prompt = LLMService.buildSystemPrompt(settings: settings)

        XCTAssertTrue(prompt.hasPrefix("Schreibe knapp."))
        XCTAssertTrue(prompt.contains("WhisperKit"))
        XCTAssertFalse(prompt.contains("Du bist ein Lektor"))
        XCTAssertFalse(prompt.contains("Kontext:"))
    }

    func testEmojiPromptReflectsDensity() {
        let prompt = LLMService.buildEmojiSystemPrompt(density: .wenig)

        XCTAssertTrue(prompt.contains("maximal 1-2 pro Absatz"))
        XCTAssertTrue(prompt.contains("Gib NUR den Text mit Emojis"))
    }

    func testRewriteUserPromptMarksTranscriptAsTextNotChat() {
        let prompt = LLMService.buildRewriteUserPrompt(text: "Kannst du mir kurz helfen?")

        XCTAssertTrue(prompt.contains("kein Chat und keine Frage"))
        XCTAssertTrue(prompt.contains("wende ausschließlich die Systemanweisung darauf an"))
        XCTAssertTrue(prompt.contains("<text>"))
        XCTAssertTrue(prompt.contains("Kannst du mir kurz helfen?"))
        XCTAssertTrue(prompt.contains("</text>"))
    }

    func testSettingsDecodeOldRemoteOpenAIShape() throws {
        let json = #"{"secureLocalModeEnabled":false,"hotkeyMode":"hold","hasSeenOnboarding":true}"#

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.speechProvider, .openAI)
        XCTAssertEqual(settings.textProvider, .openAI)
        XCTAssertEqual(settings.openAISpeechModel, AppSettings.defaultOpenAISpeechModel)
        XCTAssertEqual(settings.azureFoundryAPIVersion, AppSettings.defaultAzureFoundryAPIVersion)
        XCTAssertTrue(settings.azureFoundryEndpoint.isEmpty)
        XCTAssertTrue(settings.azureFoundryDeploymentName.isEmpty)
    }

    func testSettingsDecodeNewLocalFirstDefaults() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))

        XCTAssertEqual(settings.speechProvider, .localWhisperKit)
        XCTAssertEqual(settings.textProvider, .ollama)
        XCTAssertEqual(settings.ollamaBaseURL, AppSettings.defaultOllamaBaseURL)
        XCTAssertEqual(settings.ollamaModel, AppSettings.defaultOllamaModel)
    }

    func testSettingsMigrateLegacyAzureFoundryAPIVersion() throws {
        let json = #"{"azureFoundryAPIVersion":"2024-05-01-preview"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.azureFoundryAPIVersion, "2023-06-01")
    }

    func testTextGenerationConfigurationsKeepProviderSpecificSettings() {
        let openAI = TextGenerationConfiguration.openAI(model: "gpt-4o-mini")
        XCTAssertEqual(openAI.providerKind, .openAI)
        XCTAssertEqual(openAI.openAIModel, "gpt-4o-mini")

        let ollama = TextGenerationConfiguration.ollama(baseURL: "http://localhost:11434", model: "llama3.1")
        XCTAssertEqual(ollama.providerKind, .ollama)
        XCTAssertEqual(ollama.ollamaBaseURL, "http://localhost:11434")
        XCTAssertEqual(ollama.ollamaModel, "llama3.1")

        let azure = TextGenerationConfiguration.azureFoundryClaude(
            endpoint: "https://example.services.ai.azure.com",
            deploymentName: "claude-sonnet",
            apiVersion: "2023-06-01"
        )
        XCTAssertEqual(azure.providerKind, .azureFoundryClaude)
        XCTAssertEqual(azure.azureFoundryEndpoint, "https://example.services.ai.azure.com")
        XCTAssertEqual(azure.azureFoundryDeploymentName, "claude-sonnet")
        XCTAssertEqual(azure.azureFoundryAPIVersion, "2023-06-01")
    }

    func testErrorMappingIsProviderSpecificAndGerman() {
        XCTAssertEqual(
            LLMError.notConfigured.localizedDescription,
            "OpenAI API Key fehlt. Bitte in den Einstellungen hinterlegen."
        )
        XCTAssertTrue(LLMError.ollamaUnavailable.localizedDescription.contains("Ollama läuft nicht"))
        XCTAssertTrue(LLMError.ollamaModelMissing("llama3.1").localizedDescription.contains("ollama pull llama3.1"))
        XCTAssertTrue(LLMError.azureFoundryNotConfigured("Endpoint fehlt.").localizedDescription.contains("Endpoint fehlt"))
        XCTAssertTrue(LLMError.azureFoundryRequestFailed("Status 401").localizedDescription.contains("Azure-Foundry-Fehler"))
    }
}
