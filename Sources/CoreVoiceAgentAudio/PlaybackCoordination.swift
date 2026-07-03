import Foundation

/// Tracks playback generations (epochs) so a stale, fire-and-forget stop
/// request cannot halt a newer playback that started after the request
/// was issued.
///
/// Every playback begins by taking a fresh generation token. A stop
/// request carries the token of the playback it belongs to and may only
/// act while that token is still current. An explicit, unconditional stop
/// invalidates every outstanding token.
struct PlaybackGenerationCounter: Sendable {
  private(set) var current: UInt64 = 0

  /// Starts a new playback and returns its generation token.
  mutating func beginPlayback() -> UInt64 {
    current &+= 1
    return current
  }

  /// Invalidates every outstanding generation token, for example when the
  /// output is stopped explicitly.
  mutating func invalidate() {
    current &+= 1
  }

  /// Whether a stop request carrying `generation` is still allowed to act.
  func isCurrent(_ generation: UInt64) -> Bool {
    generation == current
  }
}

/// How a wait for a playback-completion signal ended.
enum PlaybackWaitOutcome: Sendable, Equatable {
  /// The completion signal arrived (or the signal stream finished).
  case completed
  /// The defensive timeout elapsed before any signal arrived.
  case timedOut
}

/// The defensive timeout for one playback: the buffer's duration plus a
/// fixed margin. If the player's completion handler never fires (for
/// example because the engine died), the pipeline resumes after this
/// interval instead of hanging forever.
///
/// - Parameters:
///   - sampleCount: The number of samples in the buffer.
///   - sampleRate: The buffer's sample rate in Hz.
///   - margin: Extra time granted beyond the buffer's nominal duration.
/// - Returns: The timeout to apply while waiting for playback completion.
func playbackTimeout(
  sampleCount: Int,
  sampleRate: Int,
  margin: Duration = .seconds(2)
) -> Duration {
  guard sampleCount > 0, sampleRate > 0 else { return margin }
  return .seconds(Double(sampleCount) / Double(sampleRate)) + margin
}

/// Waits for the first element (or the end) of `signal`, or for `timeout`,
/// whichever comes first.
///
/// Cancellation of the surrounding task ends the wait promptly; callers
/// are expected to check for cancellation afterwards.
func awaitPlaybackSignal(
  _ signal: AsyncStream<Void>,
  timeout: Duration
) async -> PlaybackWaitOutcome {
  await withTaskGroup(of: PlaybackWaitOutcome.self) { group in
    group.addTask {
      for await _ in signal { break }
      return .completed
    }
    group.addTask {
      do {
        try await Task.sleep(for: timeout)
        return .timedOut
      } catch {
        return .completed
      }
    }
    let first = await group.next() ?? .completed
    group.cancelAll()
    return first
  }
}
