//
//  ContentView.swift
//  tinychat
//
//  Created by Matthew Barnson on 7/1/26.
//

import SwiftData
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Chat.updatedAt, order: .reverse) private var chats: [Chat]

    @State private var selectedChatID: UUID?
    @State private var composerText = ""
    @State private var streamedAssistantText = ""
    @State private var streamedReasoningText = ""
    @State private var generationTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var modelStatus = ModelCache().baseModelStatus()
    @State private var isInstallingModel = false
    @State private var modelInstallError: String?
    @State private var modelDownloadProgress: ModelDownloadProgress?
    @State private var isShowingModelDownloadDialog = false

    private var selectedChat: Chat? {
        if let selectedChatID, let chat = chats.first(where: { $0.id == selectedChatID }) {
            return chat
        }
        return chats.first
    }

    private var isGenerating: Bool {
        generationTask != nil
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let selectedChat {
                chatDetail(for: selectedChat)
            } else {
                ContentUnavailableView("No Chat", systemImage: "bubble.left.and.bubble.right")
            }
        }
        .task {
            if !applyUITestLaunchArgumentsIfNeeded() {
                try? await Task.sleep(for: .milliseconds(100))
                ensureInitialChat()
            }
            modelStatus = ModelCache().baseModelStatus()
        }
        .onChange(of: chats.count, initial: false) {
            ensureInitialChat()
        }
    }

    private var sidebar: some View {
        List(selection: $selectedChatID) {
            ForEach(chats) { chat in
                Text(chat.title)
                    .tag(chat.id)
                    .accessibilityIdentifier("chat-row-\(chat.id.uuidString)")
            }
        }
        .navigationTitle("tinychat")
        .toolbar {
            ToolbarItem {
                Button(action: createChat) {
                    Label("New Chat", systemImage: "plus")
                }
                .accessibilityIdentifier("new-chat-button")
            }
        }
    }

    @ViewBuilder
    private func chatDetail(for chat: Chat) -> some View {
        VStack(spacing: 0) {
            modelStatusView
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(chat.messages.sorted(by: { $0.createdAt < $1.createdAt })) { message in
                        MessageBubble(message: message)
                    }

                    if isGenerating {
                        StreamingBubble(text: streamedAssistantText, reasoning: streamedReasoningText)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("transcript-scroll")

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
                    .accessibilityIdentifier("chat-error")
            }

            composer(for: chat)
        }
        .navigationTitle(chat.title)
    }

    private var modelStatusView: some View {
        HStack {
            switch modelStatus.state {
            case .missing:
                Label("Qwen3 0.6B not installed", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("model-status-missing")

                if allowsFixtureModelInstall {
                    Button(isInstallingModel ? "Installing..." : "Install Fixture") {
                        installFixtureModel()
                    }
                    .disabled(isInstallingModel)
                    .accessibilityIdentifier("install-fixture-model-button")
                }

                Button("Download Model…") {
                    isShowingModelDownloadDialog = true
                }
                .disabled(isInstallingModel)
                .accessibilityIdentifier("download-model-button")
            case .installed:
                Label("Qwen3 0.6B installed", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("model-status-installed")

                Button("Delete Model") {
                    deleteInstalledModel()
                }
                .disabled(isGenerating)
                .accessibilityIdentifier("delete-model-button")
            }

            if let modelInstallError {
                Text(modelInstallError)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .accessibilityIdentifier("model-install-error")
            }

            if let modelDownloadProgress {
                Text(modelDownloadProgressLabel(modelDownloadProgress))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("model-download-progress")
            }

            Spacer()
        }
        .sheet(isPresented: $isShowingModelDownloadDialog) {
            modelDownloadDialog
        }
    }

    private var modelDownloadDialog: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Download Model")
                .font(.title2)
                .fontWeight(.semibold)
                .accessibilityIdentifier("model-download-dialog")

            Text("Choose the model artifact tinychat should install into Application Support.")
                .foregroundStyle(.secondary)

            ForEach(modelDownloadOptions) { option in
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(option.displayName)
                            .fontWeight(.semibold)
                            .accessibilityIdentifier("model-option-\(option.id)")
                        Text(option.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let manifestURL = option.manifestURL {
                        Button("Download") {
                            isShowingModelDownloadDialog = false
                            downloadReleaseModel(manifestURL: manifestURL)
                        }
                        .disabled(isInstallingModel)
                        .accessibilityIdentifier("download-option-\(option.id)")
                    } else {
                        Text("Artifact not published yet")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("download-option-\(option.id)-unavailable")
                    }
                }
                .padding()
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    isShowingModelDownloadDialog = false
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(minWidth: 460)
    }

    private struct ModelDownloadOption: Identifiable {
        let id: String
        let displayName: String
        let detail: String
        let manifestURL: URL?
    }

    private var modelDownloadOptions: [ModelDownloadOption] {
        [
            ModelDownloadOption(
                id: "qwen3-0.6b",
                displayName: "Qwen3 0.6B",
                detail: modelReleaseManifestURL == nil
                    ? "Small base model. Release artifact is not published yet."
                    : "Small base model. Fast first-run download for smoke testing.",
                manifestURL: modelReleaseManifestURL
            ),
            ModelDownloadOption(
                id: "qwen3-4b",
                displayName: "Qwen3 4B",
                detail: "Larger model planned for the release gate. Release artifact is not published yet.",
                manifestURL: nil
            ),
        ]
    }

    private func composer(for chat: Chat) -> some View {
        VStack(spacing: 8) {
            Toggle("Think", isOn: Binding(
                get: { chat.thinkingEnabled },
                set: {
                    chat.thinkingEnabled = $0
                    chat.updatedAt = .now
                }
            ))
                .toggleStyle(.switch)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("think-toggle")

            HStack(alignment: .bottom, spacing: 8) {
                TextEditor(text: $composerText)
                    .frame(minHeight: 48, maxHeight: 120)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary)
                    }
                    .accessibilityIdentifier("message-composer")

                if isGenerating {
                    Button("Stop") {
                        stopGeneration(for: chat)
                    }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("stop-button")
                } else {
                    Button("Send") {
                        sendMessage(in: chat)
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("send-button")
                }
            }
        }
        .padding()
    }

    private func ensureInitialChat() {
        if let selectedChatID, chats.contains(where: { $0.id == selectedChatID }) {
            return
        }

        if let firstChat = chats.first {
            selectedChatID = firstChat.id
        } else {
            createChat()
        }
    }

    private func createChat() {
        let chat = Chat()
        modelContext.insert(chat)
        selectedChatID = chat.id
        try? modelContext.save()
    }

    private var allowsFixtureModelInstall: Bool {
        ProcessInfo.processInfo.arguments.contains("--use-fixture-model-installer")
    }

    private var modelReleaseManifestURL: URL? {
        guard let value = argumentValue(
            after: "--model-release-manifest-url",
            in: ProcessInfo.processInfo.arguments
        ) else {
            return nil
        }

        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            return URL(string: value)
        }
        return URL(fileURLWithPath: value, isDirectory: false)
    }

    private func downloadReleaseModel(manifestURL: URL) {
        guard !isInstallingModel else { return }

        isInstallingModel = true
        modelInstallError = nil
        modelDownloadProgress = .init(phase: .preparing, completedBytes: 0, totalBytes: nil)

        Task.detached {
            do {
                let manifest = try await Self.loadReleaseManifest(from: manifestURL)
                let status = try await ModelDownloadManager().installBaseModel(from: manifest) { progress in
                    Task { @MainActor in
                        modelDownloadProgress = progress
                    }
                }
                await MainActor.run {
                    modelStatus = status
                    modelDownloadProgress = nil
                    isInstallingModel = false
                }
            } catch {
                await MainActor.run {
                    modelInstallError = error.localizedDescription
                    isInstallingModel = false
                }
            }
        }
    }

    private static func loadReleaseManifest(from url: URL) async throws -> ModelReleaseManifest {
        let data: Data
        if url.isFileURL {
            data = try Data(contentsOf: url)
        } else {
            let (remoteData, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
                throw ModelDownloadError.downloadFailed(statusCode: httpResponse.statusCode)
            }
            data = remoteData
        }
        return try JSONDecoder().decode(ModelReleaseManifest.self, from: data)
    }

    private func modelDownloadProgressLabel(_ progress: ModelDownloadProgress) -> String {
        let phase = progress.phase.rawValue.capitalized
        guard let totalBytes = progress.totalBytes, totalBytes > 0 else {
            return "\(phase)…"
        }

        let downloaded = ByteCountFormatter.string(fromByteCount: progress.completedBytes, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return "\(phase) \(downloaded) of \(total)"
    }

    private func installFixtureModel() {
        guard !isInstallingModel else { return }

        isInstallingModel = true
        modelInstallError = nil
        defer { isInstallingModel = false }

        do {
            let cache = ModelCache()
            let source = cache.appSupportDirectory
                .appending(path: "FixtureModelSource", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            let marker = source.appending(path: "model.mil", directoryHint: .notDirectory)
            if !FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)) {
                try Data("fixture".utf8).write(to: marker)
            }
            try installModelFixture(source: source, version: "fixture", expectedFiles: ["model.mil"])
        } catch {
            modelInstallError = error.localizedDescription
        }
    }

    private func installModelFixture(source: URL, version: String, expectedFiles: [String]) throws {
        let cache = ModelCache()
        let manifest = ModelArtifactManifest(
            version: version,
            sourceURL: source,
            expectedFiles: expectedFiles
        )
        try cache.installBaseModel(from: manifest)
        modelStatus = cache.baseModelStatus()
    }

    private func deleteInstalledModel() {
        do {
            let cache = ModelCache()
            try cache.removeBaseModel()
            modelStatus = cache.baseModelStatus()
            modelInstallError = nil
        } catch {
            modelInstallError = error.localizedDescription
        }
    }

    private func sendMessage(in chat: Chat) {
        let prompt = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, generationTask == nil else { return }

        composerText = ""
        errorMessage = nil
        streamedAssistantText = ""
        streamedReasoningText = ""

        let userMessage = Message(role: .user, text: prompt, chat: chat)
        chat.messages.append(userMessage)
        chat.updatedAt = .now
        try? modelContext.save()

        let priorMessages = chat.messages
            .sorted(by: { $0.createdAt < $1.createdAt })
            .map { TranscriptMessage(role: $0.role, text: $0.text) }

        let request = ChatRequest(
            prompt: prompt,
            thinkingEnabled: chat.thinkingEnabled,
            priorMessages: priorMessages
        )
        let engine = ChatEngineFactory.make()

        generationTask = Task {
            do {
                for try await event in engine.responseEvents(for: request) {
                    guard !Task.isCancelled else { throw CancellationError() }
                    await MainActor.run {
                        switch event {
                        case .text(let text):
                            streamedAssistantText += text
                        case .reasoning(let reasoning):
                            if !streamedReasoningText.isEmpty { streamedReasoningText += "\n" }
                            streamedReasoningText += reasoning
                        }
                    }
                }

                await MainActor.run {
                    persistAssistantMessage(in: chat, stopped: false, error: nil)
                    generationTask = nil
                }
            } catch is CancellationError {
                await MainActor.run {
                    persistAssistantMessage(in: chat, stopped: true, error: nil)
                    generationTask = nil
                }
            } catch {
                await MainActor.run {
                    persistAssistantMessage(in: chat, stopped: false, error: error.localizedDescription)
                    errorMessage = error.localizedDescription
                    generationTask = nil
                }
            }
        }
    }

    private func stopGeneration(for chat: Chat) {
        generationTask?.cancel()
        persistAssistantMessage(in: chat, stopped: true, error: nil)
        generationTask = nil
    }

    private func persistAssistantMessage(in chat: Chat, stopped: Bool, error: String?) {
        guard !streamedAssistantText.isEmpty || !streamedReasoningText.isEmpty || error != nil else { return }

        let message = Message(
            role: .assistant,
            text: streamedAssistantText,
            reasoningText: streamedReasoningText.isEmpty ? nil : streamedReasoningText,
            isStopped: stopped,
            errorDescription: error,
            chat: chat
        )
        chat.messages.append(message)
        chat.updatedAt = .now

        if chat.title == "New Chat" {
            chat.title = TitleGenerator.title(for: chat.messages)
        }
        try? modelContext.save()

        streamedAssistantText = ""
        streamedReasoningText = ""
    }

    @discardableResult
    private func applyUITestLaunchArgumentsIfNeeded() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--reset-chat-state") else { return false }

        for chat in chats {
            modelContext.delete(chat)
        }

        let chat = Chat()
        modelContext.insert(chat)
        selectedChatID = chat.id
        try? modelContext.save()

        if arguments.contains("--disable-thinking") {
            chat.thinkingEnabled = false
            try? modelContext.save()
        }

        if arguments.contains("--reset-model-cache") {
            try? ModelCache().removeBaseModel()
            modelStatus = ModelCache().baseModelStatus()
        }

        if arguments.contains("--install-fixture-model"),
           let fixturePath = argumentValue(after: "--fixture-model-path", in: arguments) {
            do {
                let source = URL(fileURLWithPath: fixturePath, isDirectory: true)
                try installModelFixture(
                    source: source,
                    version: "ui-test",
                    expectedFiles: try modelArtifactFiles(in: source)
                )
                modelInstallError = nil
            } catch {
                modelInstallError = error.localizedDescription
            }
        }

        if let prompt = argumentValue(after: "--auto-send-prompt", in: arguments) {
            composerText = prompt
            sendMessage(in: chat)
        }

        return true
    }

    private func modelArtifactFiles(in directory: URL) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [String] = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            files.append(String(fileURL.path(percentEncoded: false).dropFirst(directory.path(percentEncoded: false).count + 1)))
        }
        return files.sorted()
    }

    private func argumentValue(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return nil }
        return arguments[valueIndex]
    }
}

private struct MessageBubble: View {
    let message: Message

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message.role == .user ? "You" : "Assistant")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let reasoningText = message.reasoningText, !reasoningText.isEmpty {
                DisclosureGroup("Reasoning") {
                    Text(reasoningText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Copy reasoning") {
#if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(reasoningText, forType: .string)
#else
                        UIPasteboard.general.string = reasoningText
#endif
                    }
                    .accessibilityIdentifier("copy-reasoning-button")
                }
            }

            Text(message.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(message.role == .user ? "user-message" : "assistant-message")

            if let errorDescription = message.errorDescription {
                Text(errorDescription)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("assistant-message-error")
            }

            if message.isStopped {
                Text("Stopped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Copy") {
#if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.text, forType: .string)
#else
                UIPasteboard.general.string = message.text
#endif
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("copy-message-button")
        }
        .padding(10)
        .background(message.role == .user ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct StreamingBubble: View {
    let text: String
    let reasoning: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Assistant")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if !reasoning.isEmpty {
                DisclosureGroup("Reasoning") {
                    Text(reasoning)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Text(text.isEmpty ? "Thinking…" : text)
                .textSelection(.enabled)
                .accessibilityIdentifier("streaming-assistant-message")
        }
        .padding(10)
        .background(Color.secondary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct TitleGenerator {
    static func title(for messages: [Message]) -> String {
        guard let firstPrompt = messages
            .filter({ $0.role == .user })
            .sorted(by: { $0.createdAt < $1.createdAt })
            .first?
            .text
        else {
            return "New Chat"
        }

        let words = firstPrompt
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .prefix(6)
            .joined(separator: " ")
        return words.isEmpty ? "New Chat" : words
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Chat.self, Message.self], inMemory: true)
}
