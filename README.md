# CoreVoiceAgent

**A Core AI voice pipeline with a swappable agent brain.**

CoreVoiceAgent is a Core AI-centered voice agent pipeline for Apple platforms:

```text
microphone ──▶ endpointer ──▶ transcriber ──▶ responder ──▶ chunker ──▶ synthesizer ──▶ speaker
   (your speech recognizer)      (swappable; Foundation Models Agent included)   (Chatterbox via Core AI)
```

Every stage is a protocol. The package's defining runtime is its Core AI
Chatterbox Turbo speech synthesis and interruption-aware voice loop. It also
ships an optional
[Foundation Models Agent](https://github.com/rudrankriyam/FoundationModelsAgent)
responder over any Foundation Models `LanguageModel`, AVAudioEngine
capture/playback, and deterministic test doubles. Bring the speech recognizer
that fits your app by conforming to `Transcriber`.

`VoiceAgentSession` owns the loop: it segments user speech with a
deterministic energy endpointer, transcribes the finished utterance,
streams the reply through an incremental sentence chunker, and pipelines
synthesis against playback so the next sentence is being generated while
the current one plays. Sustained user speech during a reply cancels it
(barge-in) over the echo-cancelled capture path.

## Requirements

- Swift 6.4 toolchain with Xcode 27 for the canonical Apple package
- iOS 27+ or macOS 27+ for Foundation Models Agent, Core AI, and AVFoundation
- The platform-independent core (`CoreVoiceAgentCore`) compiles and tests
  independently through the Swift 6.2+ shadow package, including on Linux

## Installation

```swift
dependencies: [
  .package(
    url: "https://github.com/rudrankriyam/CoreVoiceAgent.git",
    from: "0.2.0"
  )
]
```

Pick products by the weight you want to carry:

| Product | What it adds |
| --- | --- |
| `CoreVoiceAgent` | The pipeline plus the Foundation Models Agent responder |
| `CoreVoiceAgentCore` | Just the pipeline and protocols (no Apple-only imports) |
| `CoreVoiceAgentChatterbox` | Chatterbox Turbo mouth via Core AI |
| `CoreVoiceAgentAudio` | `AVAudioEngine` capture and playback |
| `CoreVoiceAgentTestSupport` | Scripted components and audio fixtures |

## Quick start

```swift
import CoreVoiceAgent
import CoreVoiceAgentAudio
import CoreVoiceAgentChatterbox
import FoundationModels
import FoundationModelsAgent

// The optional brain: any LanguageModel, wrapped in Foundation Models
// Agent. Voice turns accumulate in the native transcript, and tool
// governance, checkpoints, and memory apply as they do for text.
let agent = try AgentSession(
  model: SystemLanguageModel.default,
  instructions: Instructions {
    "You are a voice assistant. Keep replies short and speakable."
    "Prefer plain sentences over lists, code, and markup."
  }
)

// The mouth: Chatterbox Turbo from a directory containing recipe.json
// and the four .aimodel assets.
let chatterbox = ChatterboxEngine(recipeDirectory: chatterboxModelsURL)
try await chatterbox.prepare()

let session = VoiceAgentSession(
  input: MicrophoneAudioInput(),
  output: SpeakerAudioOutput(),
  transcriber: AppTranscriber(),
  responder: FoundationModelsAgentResponder(session: agent),
  synthesizer: ChatterboxSpeechSynthesizer(engine: chatterbox)
)

for await event in try await session.start() {
  switch event {
  case .userTranscript(let text):
    print("User: \(text)")
  case .assistantText(let text):
    print("Assistant: \(text)")
  case .bargeIn:
    print("(interrupted)")
  default:
    break
  }
}
```

On iOS, configure an `AVAudioSession` with the `.playAndRecord` category
and `.voiceChat` mode, and request microphone permission, before starting
the session.

A session runs once: calling `start()` a second time throws
`VoiceAgentSessionError.alreadyStarted`. Create a new session after
`stop()`.

## Swap the brain

`FoundationModelsAgentResponder` carries whichever `LanguageModel` its
`AgentSession` was built with. Everything Foundation Models Agent supports
drops in unchanged — the on-device system model, Claude or Gemini through
`FoundationModelsAgentProviders`, a local server through Apple's generic Chat
Completions client, or `RecordedLanguageModel` from
`FoundationModelsAgentTestSupport` for deterministic tests:

```swift
import FoundationModelsAgentProviders

let claude = FoundationModelsAgentProviderModels.claude(
  auth: .proxied(headers: ["Authorization": appSessionToken]),
  baseURL: relayURL
)
let responder = FoundationModelsAgentResponder(
  session: try AgentSession(model: claude)
)
```

Governed tools work mid-conversation: a voice turn that triggers a
Foundation Models Agent tool goes through the same approval, allowlist,
budget, and timeout policy as a text turn, and the confirmation is spoken
back.

Any other brain conforms in one method:

```swift
struct EchoResponder: ConversationResponder {
  func respond(
    to userText: String,
    onPartialResponse: @escaping @Sendable (String) async -> Void
  ) async throws -> String {
    let reply = "You said: \(userText)"
    await onPartialResponse(reply)
    return reply
  }
}
```

## Swap the ears and mouth

`Transcriber` and `SpeechSynthesizer` are single-method protocols. The
package currently leaves speech recognition to the app, so the Speech
framework, WhisperKit, a Core AI recognizer, or a fixture-backed test
transcriber can each fit the same seam.

The batch `Transcriber` shape is deliberate: the session endpoints first,
then gives the recognizer a finished clip. A streaming recognizer can still
surface partial captions through the `onPartialTranscript` callback.

## Model assets

| Stage | Model | Size | License |
| --- | --- | --- | --- |
| Ears | App-supplied `Transcriber` | app-defined | app-defined |
| Brain | On-device Foundation Models system model | — | — |
| Mouth | Chatterbox Turbo Core AI export ([conversion recipes](https://github.com/rudrankriyam/Core-AI-Framework-Lab)) | ~600 MiB | MIT (weights: Resemble AI) |

The Chatterbox engine loads a directory (or bundle resource folder)
containing `recipe.json`, the four `.aimodel` assets, and the tokenizer —
the exact layout Core-AI-Framework-Lab produces. Export them with the
conversion scripts there, or copy them from its
`CoreAILab/Resources/Chatterbox`.

## Latency model

Time-to-first-audio for a turn is approximately:

```text
endSilence (0.8 s default)
  + speech-recognition pass
  + first sentence from the model (model-dependent)
  + Chatterbox synthesis of that first sentence
```

The sentence chunker flushes the first completed sentence immediately —
regardless of the minimum-chunk setting — and later chunks synthesize
while earlier ones play, so the perceived gap is dominated by the first
sentence, not the full reply. Shorten `endSilenceDuration` for snappier
turns at the cost of more mid-sentence cutoffs.

## Testing

`CoreVoiceAgentTestSupport` runs the whole loop without hardware, models,
or network:

```swift
let session = VoiceAgentSession(
  input: ScriptedAudioInput(),
  output: CapturingAudioOutput(),
  transcriber: ScriptedTranscriber(transcripts: ["Hello there"]),
  responder: ScriptedResponder(replies: ["Hi! How can I help?"]),
  synthesizer: ScriptedSpeechSynthesizer()
)
```

The core test suite is platform-independent:

```bash
swift test                       # on a Mac, all targets
Scripts/test-core-linux.sh       # on Linux, the core + test support
```

Pair `FoundationModelsAgentResponder` with Foundation Models Agent's
`RecordedLanguageModel` for end-to-end voice tests with a deterministic,
zero-network brain.

## Deliberate boundaries

- **Endpoint-then-transcribe by default.** See above; the seams allow a
  streaming transcriber later without touching the session.
- **One fixed voice.** The Chatterbox Core AI export currently covers the
  fixed-voice inference path. Voice cloning needs the reference-voice
  encoders converted first.
- **Sentence-granular barge-in.** Cancellation stops synthesis within one
  T3 decode token and playback at the next buffer, but the already-spoken
  words stand — the transcriptual record keeps what the user actually
  heard... and Foundation Models Agent's transcript keeps the full intended
  reply.
- **The session does not manage audio-session policy.** Categories,
  routing, and interruptions differ per app; `MicrophoneAudioInput`
  documents what it needs.

## License

CoreVoiceAgent is available under the MIT license. See
`THIRD_PARTY_NOTICES.md` for the licenses of the model runtimes and
weights it composes.
