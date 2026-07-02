//
//  ChatEngine.swift
//  tinychat
//
//  Created by Matthew Barnson on 7/1/26.
//

import Foundation

#if canImport(CoreAILanguageModels) && canImport(FoundationModels)
import CoreAILanguageModels
import FoundationModels
#endif

struct ChatRequest: Sendable {
    let prompt: String
    let thinkingEnabled: Bool
    let priorMessages: [TranscriptMessage]
}

struct TranscriptMessage: Sendable, Equatable {
    let role: MessageRole
    let text: String
}

enum ChatStreamEvent: Sendable, Equatable {
    case text(String)
    case reasoning(String)
}

protocol ChatEngine: Sendable {
    nonisolated func responseEvents(for request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error>
}

struct DeterministicChatEngine: ChatEngine {
    nonisolated func responseEvents(for request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    if request.thinkingEnabled {
                        continuation.yield(.reasoning("Checked the deterministic test path."))
                    }

                    continuation.yield(.text("Hello"))

                    for chunk in [" from", " tinychat."] {
                        try await Task.sleep(for: .milliseconds(1_500))
                        try Task.checkCancellation()
                        continuation.yield(.text(chunk))
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

struct MissingModelChatEngine: ChatEngine {
    let modelName: String

    nonisolated func responseEvents(for request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: ChatEngineError.modelMissing(modelName))
        }
    }
}

enum ChatEngineError: LocalizedError, Equatable {
    case modelMissing(String)
    case coreAIUnavailable
    case coreAIResponse(String)

    var errorDescription: String? {
        switch self {
        case .modelMissing(let modelName):
            "Install \(modelName) before sending a message."
        case .coreAIUnavailable:
            "CoreAI is unavailable in this build. Install Xcode/CoreAI support and rebuild."
        case .coreAIResponse(let message):
            message
        }
    }
}

struct ChatEngineFactory {
    static func make(cache: ModelCache = ModelCache()) -> ChatEngine {
        if ProcessInfo.processInfo.arguments.contains("--use-deterministic-chat-engine") {
            return DeterministicChatEngine()
        }

        let status = cache.baseModelStatus()
        guard case .installed(let url) = status.state else {
            return MissingModelChatEngine(modelName: status.displayName)
        }

        return CoreAIChatEngine(modelURL: url)
    }
}

struct CoreAIChatEngine: ChatEngine {
    let modelURL: URL

    nonisolated func responseEvents(for request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
#if canImport(CoreAILanguageModels) && canImport(FoundationModels)
                    let model = try await CoreAILanguageModel(resourcesAt: modelURL)
                    let session = LanguageModelSession(model: model, transcript: transcript(for: request))
                    let stream = session.streamResponse(
                        to: promptText(for: request),
                        options: GenerationOptions(
                            samplingMode: .greedy,
                            temperature: 0,
                            maximumResponseTokens: 64
                        )
                    )
                    var emittedReasoning = ""
                    var emittedText = ""

                    for try await snapshot in stream {
                        try Task.checkCancellation()

                        if request.thinkingEnabled {
                            guard snapshot.content.contains("</think>") else { continue }

                            let parsed = ReasoningParser.split(snapshot.content)
                            if let reasoning = parsed.reasoning {
                                let delta = parsedDelta(from: emittedReasoning, to: reasoning)
                                if !delta.isEmpty {
                                    continuation.yield(.reasoning(delta))
                                    emittedReasoning = reasoning
                                }
                            }

                            let textDelta = parsedDelta(from: emittedText, to: parsed.text)
                            if !textDelta.isEmpty {
                                continuation.yield(.text(textDelta))
                                emittedText = parsed.text
                            }
                        } else {
                            let textDelta = parsedDelta(from: emittedText, to: snapshot.content)
                            if !textDelta.isEmpty {
                                continuation.yield(.text(textDelta))
                                emittedText = snapshot.content
                            }
                        }
                    }

                    continuation.finish()
#else
                    throw ChatEngineError.coreAIUnavailable
#endif
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    nonisolated private func parsedDelta(from emitted: String, to latest: String) -> String {
        if latest.hasPrefix(emitted) {
            return String(latest.dropFirst(emitted.count))
        }
        return latest
    }

#if canImport(CoreAILanguageModels) && canImport(FoundationModels)
    nonisolated private func transcript(for request: ChatRequest) -> Transcript {
        var entries: [Transcript.Entry] = [
            .instructions(
                Transcript.Instructions(
                    segments: [.text(.init(content: "You are a helpful local assistant inside tinychat."))],
                    toolDefinitions: []
                )
            )
        ]

        for message in request.priorMessages.dropLast() {
            let segment = Transcript.Segment.text(.init(content: message.text))
            switch message.role {
            case .user:
                entries.append(.prompt(Transcript.Prompt(segments: [segment])))
            case .assistant:
                entries.append(.response(Transcript.Response(segments: [segment])))
            }
        }

        return Transcript(entries: entries)
    }
#endif

    nonisolated private func promptText(for request: ChatRequest) -> String {
        "\(request.thinkingEnabled ? "/think" : "/no_think")\n\(request.prompt)"
    }
}


struct ReasoningParser {
    nonisolated static func split(_ content: String) -> (reasoning: String?, text: String) {
        guard let openRange = content.range(of: "<think>"),
              let closeRange = content.range(of: "</think>", range: openRange.upperBound..<content.endIndex)
        else {
            return (nil, content.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let reasoning = content[openRange.upperBound..<closeRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let before = content[..<openRange.lowerBound]
        let after = content[closeRange.upperBound...]
        let text = (before + after).trimmingCharacters(in: .whitespacesAndNewlines)
        return (reasoning.isEmpty ? nil : String(reasoning), String(text))
    }
}

