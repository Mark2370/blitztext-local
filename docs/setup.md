# Setup

This guide is for people who want to build and inspect the preview themselves.

## 1. Requirements

- macOS 14 or newer
- Full Xcode, with Command Line Tools installed
- XcodeGen
- Homebrew, if you want to install XcodeGen with `brew install xcodegen`
- For local speech: a WhisperKit/CoreML model
- For local rewriting: Ollama running on `http://localhost:11434`
- Optional for remote OpenAI workflows: an OpenAI API key
- Optional for Azure Foundry Claude rewriting: Endpoint, Deployment/Model name, API version, and API key

Install XcodeGen manually if needed:

```bash
brew install xcodegen
```

## 2. Clone And Build

```bash
git clone https://github.com/cmagnussen/blitztext-app.git
cd blitztext-app
./build.sh --debug
```

To launch after building:

```bash
./build.sh --run
```

## 3. Configure Local Providers

The default setup is local-first:

- choose or install a WhisperKit/CoreML model in the app for speech-to-text
- run Ollama locally and select an installed model for text rewriting

Example Ollama preparation:

```bash
brew install ollama
ollama serve
ollama pull llama3.1
```

Ollama listens on `http://localhost:11434` by default. You can test the connection from the app settings.

For a new local-first install, no API key is required. The app is ready once a WhisperKit model is installed and Ollama can answer with the selected model.

## 4. Optional Remote Providers

Open the app settings and paste your own OpenAI API key only if you want OpenAI transcription or OpenAI rewriting. Then select OpenAI as speech provider, text provider, or both.

The preview currently uses:

- `whisper-1` for transcription
- `gpt-4o-mini` for lightweight rewriting
- `gpt-4o` for the calmer-message workflow

You are responsible for API access, billing, and data handling in your own OpenAI account.

Never commit your API key into this repository, issues, logs, or screenshots.

For Azure Foundry Claude, select Azure Foundry Claude as text provider and configure the resource endpoint (`https://<resource>.services.ai.azure.com`), deployment name, Anthropic API version (`2023-06-01`), and deployment API key. Blitztext calls `/anthropic/v1/messages` and accepts either the resource endpoint or the full Messages API URL. The API key is stored in the macOS Keychain; the endpoint and model settings are stored as non-secret app settings.

You can skip remote providers for fully local WhisperKit + Ollama workflows.

## 5. Local Speech Model

To use local transcription, choose a compatible WhisperKit CoreML model in the app and click **Installieren**. Blitztext stores models in:

```text
~/Library/Application Support/Blitztext/models/whisperkit/
```

Recommended first model: `openai_whisper-small_216MB`.

See [local-models.md](local-models.md) for the exact command, model links, and expected folder layout.

## 6. macOS Permissions

The app needs Microphone permission to record audio.

For automatic paste into the previous app, grant Accessibility permission in macOS System Settings. Without it, you can still copy and paste manually.

Blitztext does not need Full Disk Access. Auto-paste uses the Accessibility permission because the app simulates Cmd+V after putting the result on the clipboard.

## Troubleshooting

- If `xcodebuild` reports that the active developer directory is only Command Line Tools, run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
- If the build cannot find XcodeGen, install it explicitly with `brew install xcodegen`.
- To run unit tests locally on Apple Silicon, use `xcodebuild ... -destination 'platform=macOS,arch=arm64' test CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES`.
- If local transcription is unavailable, check whether a WhisperKit model is installed in the expected folder.
- If local rewriting fails, check whether Ollama is running and the selected model is installed.
- If transcription works but paste does not, this is not an OpenAI billing issue. Check **Privacy & Security -> Accessibility**, restart Blitztext after changing the permission, and make sure the cursor is focused in a text field before starting the workflow.
- If macOS shows multiple Blitztext entries under Accessibility, remove or disable stale entries, run the app from the final location (`/Applications` if you used `./build.sh --install`), then grant the permission again.
- If the target app blocks synthetic paste or the target app was not detected, the result still stays on the clipboard so you can press Cmd+V manually.
- If audio is missing, check Microphone permission and macOS input settings.
- If you see OpenAI errors while OpenAI is selected, verify the API key, model access, and account billing.
- If Azure Foundry returns 401, verify that the deployment API key belongs to the same resource as the endpoint. Blitztext sends it as `x-api-key` to `/anthropic/v1/messages`; Claude Mythos deployments require Microsoft Entra ID and cannot use this API-key configuration.
