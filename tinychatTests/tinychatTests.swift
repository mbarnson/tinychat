//
//  tinychatTests.swift
//  tinychatTests
//
//  Created by Matthew Barnson on 7/1/26.
//

import Foundation
import SwiftData
import Testing
@testable import tinychat

struct tinychatTests {
    @Test @MainActor func chatAndMessagePersistInMemory() throws {
        let container = try ModelContainer(
            for: Chat.self,
            Message.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let chat = Chat(title: "Unit Test")
        let userMessage = Message(role: .user, text: "Hello", chat: chat)
        let assistantMessage = Message(
            role: .assistant,
            text: "Hi",
            reasoningText: "Greeting is appropriate.",
            chat: chat
        )

        chat.messages.append(userMessage)
        chat.messages.append(assistantMessage)
        context.insert(chat)
        try context.save()

        let descriptor = FetchDescriptor<Chat>()
        let chats = try context.fetch(descriptor)

        #expect(chats.count == 1)
        #expect(chats[0].messages.count == 2)
        #expect(chats[0].messages.contains { $0.role == .assistant && $0.reasoningText != nil })
    }

    @Test @MainActor func modelCacheReportsMissingAndInstalledStates() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "tinychat-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let cache = ModelCache(appSupportOverride: root)
        #expect(cache.baseModelStatus().state == .missing)

        try FileManager.default.createDirectory(
            at: cache.baseModelDirectory,
            withIntermediateDirectories: true
        )

        guard case .installed(let url) = cache.baseModelStatus().state else {
            Issue.record("Expected installed model status")
            return
        }

        #expect(url == cache.baseModelDirectory)
    }

    @Test @MainActor func reasoningParserSeparatesThinkBlock() {
        let parsed = ReasoningParser.split("<think>Check carefully.</think>Final answer.")

        #expect(parsed.reasoning == "Check carefully.")
        #expect(parsed.text == "Final answer.")
    }
}
