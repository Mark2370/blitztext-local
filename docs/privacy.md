# Privacy Notes

Blitztext macOS Preview does not include a hosted backend.

Blitztext is local-first when configured with WhisperKit/CoreML for speech and Ollama for text generation. In that setup, audio transcription and rewriting happen on your Mac or on your local Ollama endpoint.

When you explicitly select OpenAI as speech provider or text provider, your Mac sends the relevant data directly to OpenAI:

- audio recordings for transcription
- transcribed or typed text for rewriting
- custom terms and prompt context if you configured them

You are responsible for your OpenAI account, API usage, costs, and data handling when you choose OpenAI.

## Local Data

The app stores:

- your OpenAI API key in the user's macOS Keychain, only if you entered one
- workflow settings in local app support storage
- provider selections and non-secret model names in local app support storage
- optional WhisperKit/CoreML model folders in local app support storage
- temporary audio files while a transcription is being processed; the app attempts to delete each recording when the workflow ends or is cancelled

Workflow output may also be placed on your clipboard so it can be pasted into another app. Auto-paste marks the clipboard entry as concealed for compatible clipboard managers, but the generated text intentionally remains on the clipboard as a fallback if automatic paste is blocked. Clipboard managers, macOS, or other apps may still observe clipboard contents while they are present.

The app uses the system TLS trust store for OpenAI and Hugging Face requests. It does not currently pin certificates. A user-installed or managed root certificate can therefore affect HTTPS trust decisions on that Mac.

Settings such as custom prompts, custom terms, and context are stored in local app support storage as plain JSON. Do not put secrets into those fields.

## Offline Scope

With a local WhisperKit/CoreML model and a reachable Ollama model, transcription and rewriting workflows can run without an OpenAI key. OpenAI remains an optional remote provider.

## Sensitive Content

Do not use this preview with confidential, regulated, or highly sensitive content unless you have reviewed the code, your provider settings, and your legal/privacy requirements.
