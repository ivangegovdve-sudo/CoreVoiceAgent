import CoreVoiceAgentCore
import Foundation
import FoundationModels
import FoundationModelsAgent

/// A conversation responder backed by an `AgentSession`.
///
/// This is the seam that makes the brain swappable: `AgentSession`
/// accepts any Foundation Models `LanguageModel` — the on-device system
/// model, a provider model from `FoundationModelsAgentProviders`, or a
/// recorded model from `FoundationModelsAgentTestSupport` — and this
/// responder carries whichever one the session was built with into the
/// voice loop, along with Foundation Models Agent's tool governance,
/// checkpoints, memory, and observability.
///
/// ```swift
/// let agent = try AgentSession(
///   model: SystemLanguageModel.default,
///   instructions: Instructions {
///     "You are a voice assistant. Keep replies short and speakable."
///     "Prefer plain sentences over lists, code, and markup."
///   }
/// )
///
/// let responder = FoundationModelsAgentResponder(session: agent)
/// ```
///
/// The `AgentSession` is persistent, so the voice conversation
/// accumulates in its native transcript across turns — and checkpoints,
/// retention, and memory plugins apply to voice turns exactly as they do
/// to text turns.
public struct FoundationModelsAgentResponder: ConversationResponder {
  /// The wrapped agent session.
  public let session: AgentSession

  /// Generation options applied to every voice turn.
  public let options: GenerationOptions

  /// Creates a responder over an existing agent session.
  ///
  /// - Parameters:
  ///   - session: The agent session that owns the model, tools, and
  ///     transcript.
  ///   - options: Generation options applied to every voice turn.
  public init(
    session: AgentSession,
    options: GenerationOptions = GenerationOptions()
  ) {
    self.session = session
    self.options = options
  }

  public func respond(
    to userText: String,
    onPartialResponse: @escaping @Sendable (String) async -> Void
  ) async throws -> String {
    let response = try await session.respondStreaming(
      to: userText,
      options: options,
      onPartialResponse: onPartialResponse
    )
    return response.content
  }
}
