#if canImport(AVFoundation)
import AVFoundation
import CoreVoiceAgentCore
import Foundation

/// A speaker output that plays synthesized speech with `AVAudioEngine`.
///
/// Chunks are scheduled onto a single player node and `play(_:)` returns
/// when the chunk has been played back, which is the signal the session's
/// playback stage uses to keep chunk order. `stop()` halts the player
/// immediately, discarding scheduled audio — the barge-in path.
public actor SpeakerAudioOutput: AudioOutput {
  private var engine: AVAudioEngine?
  private var player: AVAudioPlayerNode?
  private var connectedSampleRate: Double?
  private var generations = PlaybackGenerationCounter()

  /// Creates a speaker output.
  public init() {}

  public func play(_ speech: SynthesizedSpeech) async throws {
    guard !speech.samples.isEmpty, speech.sampleRate > 0 else { return }
    let player = try preparePlayer(sampleRate: Double(speech.sampleRate))
    let buffer = try makeBuffer(for: speech)

    // Each playback takes a fresh generation token so that the
    // fire-and-forget stop issued on cancellation cannot land late and
    // halt a newer playback that started after this one ended.
    let generation = generations.beginPlayback()
    let timeout = playbackTimeout(
      sampleCount: speech.samples.count,
      sampleRate: speech.sampleRate
    )
    let (playedBack, playedBackContinuation) = AsyncStream.makeStream(of: Void.self)

    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      player.scheduleBuffer(
        buffer,
        at: nil,
        options: [],
        completionCallbackType: .dataPlayedBack
      ) { _ in
        playedBackContinuation.yield(())
        playedBackContinuation.finish()
      }
      player.play()

      // A defensive timeout (buffer duration plus margin) keeps a dead
      // engine from hanging the pipeline when the completion handler
      // never fires.
      let outcome = await awaitPlaybackSignal(playedBack, timeout: timeout)
      if outcome == .timedOut, generations.isCurrent(generation) {
        // The engine failed to report completion; reset the player so
        // the next chunk starts from a clean state.
        generations.invalidate()
        player.stop()
      }
      try Task.checkCancellation()
    } onCancel: {
      // Carry this playback's generation so a stop that lands late is a
      // no-op once a newer playback (or an explicit stop) has taken over.
      Task { await self.stop(ifCurrent: generation) }
    }
  }

  public func stop() async {
    // Stopping the player flushes scheduled buffers and fires their
    // completion handlers, which resumes any in-flight play(_:).
    // Invalidate outstanding generations so late cancellation stops
    // become no-ops.
    generations.invalidate()
    player?.stop()
  }

  /// Stops playback only if `generation` is still the current playback.
  private func stop(ifCurrent generation: UInt64) {
    guard generations.isCurrent(generation) else { return }
    generations.invalidate()
    player?.stop()
  }

  /// Tears down the audio engine. The next `play(_:)` rebuilds it.
  public func shutDown() {
    generations.invalidate()
    player?.stop()
    engine?.stop()
    player = nil
    engine = nil
    connectedSampleRate = nil
  }

  private func preparePlayer(sampleRate: Double) throws -> AVAudioPlayerNode {
    if let player, let engine, engine.isRunning, connectedSampleRate == sampleRate {
      return player
    }

    let engine = self.engine ?? AVAudioEngine()
    let player = self.player ?? AVAudioPlayerNode()
    if player.engine == nil {
      engine.attach(player)
    }

    guard
      let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
      )
    else {
      throw VoiceAgentError(
        stage: .playback,
        message: "Could not build a playback format at \(sampleRate) Hz."
      )
    }
    // The main mixer resamples from the chunk's rate to the hardware
    // rate.
    engine.connect(player, to: engine.mainMixerNode, format: format)
    if !engine.isRunning {
      engine.prepare()
      try engine.start()
    }

    self.engine = engine
    self.player = player
    connectedSampleRate = sampleRate
    return player
  }

  private func makeBuffer(for speech: SynthesizedSpeech) throws -> AVAudioPCMBuffer {
    guard
      let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(speech.sampleRate),
        channels: 1,
        interleaved: false
      ),
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: AVAudioFrameCount(speech.samples.count)
      ),
      let channel = buffer.floatChannelData
    else {
      throw VoiceAgentError(
        stage: .playback,
        message: "Could not allocate a playback buffer."
      )
    }
    speech.samples.withUnsafeBufferPointer { samples in
      channel[0].update(from: samples.baseAddress!, count: samples.count)
    }
    buffer.frameLength = AVAudioFrameCount(speech.samples.count)
    return buffer
  }
}
#endif
