import Foundation
import Testing

@testable import CoreVoiceAgentAudio

@Suite("PlaybackGenerationCounter")
struct PlaybackGenerationCounterTests {
  @Test("A playback's own stop request is allowed while it is current")
  func currentGenerationMayStop() {
    var counter = PlaybackGenerationCounter()
    let generation = counter.beginPlayback()

    #expect(counter.isCurrent(generation))
  }

  @Test("A stale stop request is rejected once a newer playback begins")
  func staleStopCannotAffectNewerPlayback() {
    var counter = PlaybackGenerationCounter()
    let cancelled = counter.beginPlayback()
    let next = counter.beginPlayback()

    #expect(!counter.isCurrent(cancelled))
    #expect(counter.isCurrent(next))
  }

  @Test("An explicit stop invalidates every outstanding generation")
  func invalidateRejectsAllOutstandingGenerations() {
    var counter = PlaybackGenerationCounter()
    let generation = counter.beginPlayback()
    counter.invalidate()

    #expect(!counter.isCurrent(generation))
  }

  @Test("Generations are strictly increasing across playbacks")
  func generationsIncrease() {
    var counter = PlaybackGenerationCounter()
    let first = counter.beginPlayback()
    let second = counter.beginPlayback()

    #expect(second != first)
    #expect(!counter.isCurrent(first))
  }
}

@Suite("Playback timeout")
struct PlaybackTimeoutTests {
  @Test("The timeout is the buffer duration plus the margin")
  func timeoutCoversBufferAndMargin() {
    let timeout = playbackTimeout(
      sampleCount: 48_000,
      sampleRate: 24_000,
      margin: .seconds(2)
    )

    #expect(timeout == .seconds(4))
  }

  @Test("Degenerate buffers fall back to the margin alone")
  func degenerateBuffersUseMargin() {
    #expect(playbackTimeout(sampleCount: 0, sampleRate: 24_000, margin: .seconds(2)) == .seconds(2))
    #expect(playbackTimeout(sampleCount: 24_000, sampleRate: 0, margin: .seconds(2)) == .seconds(2))
  }
}

@Suite("Playback completion wait")
struct PlaybackSignalWaitTests {
  @Test("A completion signal ends the wait before the timeout")
  func signalCompletesBeforeTimeout() async {
    let (signal, continuation) = AsyncStream.makeStream(of: Void.self)
    continuation.yield(())
    continuation.finish()

    let outcome = await awaitPlaybackSignal(signal, timeout: .seconds(10))

    #expect(outcome == .completed)
  }

  @Test("A signal stream that finishes without yielding also completes")
  func finishedStreamCompletes() async {
    let (signal, continuation) = AsyncStream.makeStream(of: Void.self)
    continuation.finish()

    let outcome = await awaitPlaybackSignal(signal, timeout: .seconds(10))

    #expect(outcome == .completed)
  }

  @Test("A completion handler that never fires times out instead of hanging")
  func missingSignalTimesOut() async {
    let (signal, _continuation) = AsyncStream.makeStream(of: Void.self)

    let outcome = await awaitPlaybackSignal(signal, timeout: .milliseconds(50))

    #expect(outcome == .timedOut)
    _continuation.finish()
  }

  @Test("A late signal still wins over a distant timeout")
  func lateSignalCompletes() async {
    let (signal, continuation) = AsyncStream.makeStream(of: Void.self)
    let signaler = Task {
      try? await Task.sleep(for: .milliseconds(30))
      continuation.yield(())
      continuation.finish()
    }

    let outcome = await awaitPlaybackSignal(signal, timeout: .seconds(10))

    #expect(outcome == .completed)
    await signaler.value
  }
}
