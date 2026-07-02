//
//  ChatModels.swift
//  tinychat
//
//  Created by Matthew Barnson on 7/1/26.
//

import Foundation
import SwiftData

enum MessageRole: String, Codable, CaseIterable {
    case user
    case assistant
}

@Model
final class Chat {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var title: String
    var contextSummary: String?
    var thinkingEnabled: Bool

    @Relationship(deleteRule: .cascade, inverse: \Message.chat)
    var messages: [Message]

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        title: String = "New Chat",
        contextSummary: String? = nil,
        thinkingEnabled: Bool = true,
        messages: [Message] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.contextSummary = contextSummary
        self.thinkingEnabled = thinkingEnabled
        self.messages = messages
    }
}

@Model
final class Message {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var roleRawValue: String
    var text: String
    var reasoningText: String?
    var isStopped: Bool
    var errorDescription: String?
    var chat: Chat?

    var role: MessageRole {
        get { MessageRole(rawValue: roleRawValue) ?? .assistant }
        set { roleRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        role: MessageRole,
        text: String,
        reasoningText: String? = nil,
        isStopped: Bool = false,
        errorDescription: String? = nil,
        chat: Chat? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.roleRawValue = role.rawValue
        self.text = text
        self.reasoningText = reasoningText
        self.isStopped = isStopped
        self.errorDescription = errorDescription
        self.chat = chat
    }
}
