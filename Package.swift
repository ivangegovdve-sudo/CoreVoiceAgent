// swift-tools-version: 6.4

import PackageDescription

let package = Package(
  name: "CoreVoiceAgent",
  platforms: [
    .iOS("27.0"),
    .macOS("27.0"),
  ],
  products: [
    // The umbrella product: the Core AI voice pipeline plus the optional
    // Foundation Models Agent-backed conversation brain (on-device
    // Foundation Models by default, any `LanguageModel` by construction).
    .library(name: "CoreVoiceAgent", targets: ["CoreVoiceAgent"]),
    // The platform-independent voice pipeline: protocols, endpointing,
    // sentence chunking, and the session orchestrator. No Apple-only
    // framework imports; compiles and tests on Linux.
    .library(name: "CoreVoiceAgentCore", targets: ["CoreVoiceAgentCore"]),
    // Resemble AI Chatterbox Turbo text-to-speech through Core AI, vendored
    // from Core-AI-Framework-Lab and adapted to return raw samples.
    .library(name: "CoreVoiceAgentChatterbox", targets: ["CoreVoiceAgentChatterbox"]),
    // AVAudioEngine microphone capture (voice-processed, echo-cancelled)
    // and speaker playback.
    .library(name: "CoreVoiceAgentAudio", targets: ["CoreVoiceAgentAudio"]),
    // Deterministic scripted transcriber/responder/synthesizer and audio
    // fixtures for tests. No network, no models, no audio hardware.
    .library(name: "CoreVoiceAgentTestSupport", targets: ["CoreVoiceAgentTestSupport"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/rudrankriyam/FoundationModelsAgent.git",
      exact: "0.5.0"
    ),
    .package(
      url: "https://github.com/huggingface/swift-transformers.git",
      from: "1.1.0"
    ),
  ],
  targets: [
    .target(name: "CoreVoiceAgentCore"),
    .target(
      name: "CoreVoiceAgent",
      dependencies: [
        "CoreVoiceAgentCore",
        .product(name: "FoundationModelsAgent", package: "FoundationModelsAgent"),
      ]
    ),
    .target(
      name: "CoreVoiceAgentChatterbox",
      dependencies: [
        "CoreVoiceAgentCore",
        .product(name: "Transformers", package: "swift-transformers"),
      ],
      linkerSettings: [
        .linkedFramework("CoreAI")
      ]
    ),
    .target(
      name: "CoreVoiceAgentAudio",
      dependencies: ["CoreVoiceAgentCore"],
      linkerSettings: [
        .linkedFramework("AVFoundation")
      ]
    ),
    .target(
      name: "CoreVoiceAgentTestSupport",
      dependencies: ["CoreVoiceAgentCore"]
    ),
    .testTarget(
      name: "CoreVoiceAgentCoreTests",
      dependencies: ["CoreVoiceAgentCore", "CoreVoiceAgentTestSupport"]
    ),
    .testTarget(
      name: "CoreVoiceAgentAudioTests",
      dependencies: ["CoreVoiceAgentAudio"]
    ),
    .testTarget(
      name: "CoreVoiceAgentTests",
      dependencies: [
        "CoreVoiceAgent",
        .product(
          name: "FoundationModelsAgentTestSupport",
          package: "FoundationModelsAgent"
        ),
      ]
    ),
  ]
)
