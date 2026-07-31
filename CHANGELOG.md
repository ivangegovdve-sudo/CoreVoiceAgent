# Changelog

## Unreleased

- Kept the `CoreVoiceAgent` package and product names: they describe the
  Core AI-centered voice pipeline, not its optional conversation model.
- **Breaking**: migrated the optional agent integration from CoreAgent 0.3 to
  Foundation Models Agent 0.5 and renamed `CoreAgentResponder` to
  `FoundationModelsAgentResponder`. The responder now wraps `AgentSession`;
  no compatibility alias is provided.
- Raised the canonical package tools version to Swift 6.4 and pinned
  Foundation Models Agent exactly at 0.5.0 so a future breaking 0.x release
  cannot be selected silently. The platform-independent shadow package remains
  on Swift 6.2.
- Fixed an Xcode 27 ownership-checking build failure in the Core AI Chatterbox
  cache helpers by keeping non-reassigned NDArray view bindings immutable.

## 0.2.0

Concurrency hardening and a safer session API.

- **Breaking**: `VoiceAgentSession.start()` now throws
  `VoiceAgentSessionError.alreadyStarted` when called more than once,
  instead of crashing with a precondition failure. Wrap the call in
  `do`/`catch` (or keep `try await` and let the error propagate) if your
  app could start a session twice.
- `SpeakerAudioOutput` playbacks now carry a generation (epoch) token: the
  fire-and-forget stop issued when a playback is cancelled can no longer
  land late and halt the next turn's first chunk.
- `SpeakerAudioOutput.play(_:)` applies a defensive timeout (buffer
  duration plus a margin), so an engine that never fires its completion
  handler can no longer hang the playback pipeline.
- `MicrophoneAudioInput` frame delivery is now bounded
  (`maxBufferedFrames`, five seconds of audio): the newest frames are
  kept and the oldest dropped, so a stalled consumer no longer
  accumulates unbounded audio.
- New `CoreVoiceAgentAudioTests` target covering the playback generation
  counter and timeout logic, and a CI workflow running `swift build` and
  `swift test` on every pull request and push to `main`.

## 0.1.0

Initial release.

- `CoreVoiceAgentCore`: the platform-independent voice pipeline —
  `VoiceAgentSession` orchestrator with pipelined synthesis/playback and
  barge-in, deterministic energy `UtteranceEndpointer`, incremental
  `SentenceChunker`, and protocol seams (`AudioInput`, `AudioOutput`,
  `Transcriber`, `ConversationResponder`, `SpeechSynthesizer`).
- `CoreVoiceAgent`: `CoreAgentResponder`, adapting `CoreAgentSession`
  (any Foundation Models `LanguageModel`) as the conversational brain.
- `CoreVoiceAgentChatterbox`: `ChatterboxEngine` and
  `ChatterboxSpeechSynthesizer` (Chatterbox Turbo through Core AI),
  vendored from Core-AI-Framework-Lab and adapted to return raw samples
  with cooperative cancellation in the T3 decode loop.
- `CoreVoiceAgentAudio`: `MicrophoneAudioInput` (voice-processed,
  echo-cancelled 16 kHz capture) and `SpeakerAudioOutput`.
- `CoreVoiceAgentTestSupport`: scripted components and audio fixtures;
  27 core tests run on any Swift platform, including Linux.
