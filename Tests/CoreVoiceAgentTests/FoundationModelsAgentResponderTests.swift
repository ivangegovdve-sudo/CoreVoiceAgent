import CoreVoiceAgent
import FoundationModelsAgent
import FoundationModelsAgentTestSupport
import Testing

private actor PartialResponseCapture {
  private var values: [String] = []

  func append(_ value: String) {
    values.append(value)
  }

  func snapshot() -> [String] {
    values
  }
}

@Suite("Foundation Models Agent responder")
struct FoundationModelsAgentResponderTests {
  @Test("Streams partial and final responses through AgentSession")
  func streamsAgentSessionResponse() async throws {
    let model = RecordedLanguageModel(steps: [
      .responseFragments(["hello", " there"])
    ])
    let responder = FoundationModelsAgentResponder(
      session: try AgentSession(model: model)
    )
    let partials = PartialResponseCapture()

    let response = try await responder.respond(to: "Greet me") { partial in
      await partials.append(partial)
    }

    #expect(response == "hello there")
    #expect(await partials.snapshot().last == "hello there")
    #expect(model.recorder.capturedTranscripts().count == 1)
  }
}
