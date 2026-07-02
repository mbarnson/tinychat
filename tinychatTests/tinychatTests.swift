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
    // ── Directory structure ──

    @Test @MainActor func modelCacheDirectoryPathHasCorrectStructure() throws {
        let root = tempRoot()
        let cache = ModelCache(appSupportOverride: root)

        let path = cache.baseModelDirectory.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        #expect(path.hasSuffix("Models/\(ModelCache.baseModelID)/\(ModelCache.platformDirectoryName)"))
    }

    // ── Install: validation rejections ──

    @Test @MainActor func installRejectsManifestWithWrongModelID() {
        let root = tempRoot()
        _ = makeFixture(root: root)
        let cache = ModelCache(appSupportOverride: root)

        let manifest = ModelArtifactManifest(
            modelID: "wrong-model-id",
            version: "1.0.0",
            sourceURL: root.appending(path: "fake-fixture"),
            expectedFiles: ["weights.gguf"]
        )

        do {
            try cache.installBaseModel(from: manifest)
            Issue.record("Expected manifestModelMismatch error")
        } catch let error as ModelCacheError {
            #expect(error == .manifestModelMismatch(expected: ModelCache.baseModelID, actual: "wrong-model-id"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test @MainActor func installRejectsManifestWithWrongPlatform() {
        let root = tempRoot()
        let fixture = makeFixture(root: root)
        let cache = ModelCache(appSupportOverride: root)

        let manifest = ModelArtifactManifest(
            modelID: ModelCache.baseModelID,
            platform: "iOS",
            version: "1.0.0",
            sourceURL: fixture,
            expectedFiles: ["weights.gguf"]
        )

        do {
            try cache.installBaseModel(from: manifest)
            Issue.record("Expected manifestPlatformMismatch error")
        } catch let error as ModelCacheError {
            #expect(error == .manifestPlatformMismatch(expected: ModelCache.platformDirectoryName, actual: "iOS"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test @MainActor func installRejectsMissingSourceDirectory() {
        let root = tempRoot()
        let phantom = root.appending(path: "does-not-exist")
        let cache = ModelCache(appSupportOverride: root)

        let manifest = ModelArtifactManifest(
            modelID: ModelCache.baseModelID,
            version: "1.0.0",
            sourceURL: phantom,
            expectedFiles: ["weights.gguf"]
        )

        do {
            try cache.installBaseModel(from: manifest)
            Issue.record("Expected sourceDirectoryMissing error")
        } catch let error as ModelCacheError {
            #expect(error == .sourceDirectoryMissing(phantom))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test @MainActor func installRejectsMissingExpectedFile() {
        let root = tempRoot()
        let fixture = makeFixture(root: root)
        let cache = ModelCache(appSupportOverride: root)

        let manifest = ModelArtifactManifest(
            modelID: ModelCache.baseModelID,
            version: "1.0.0",
            sourceURL: fixture,
            expectedFiles: ["weights.gguf", "missing.bin"]
        )

        do {
            try cache.installBaseModel(from: manifest)
            Issue.record("Expected expectedFileMissing error")
        } catch let error as ModelCacheError {
            #expect(error == .expectedFileMissing("missing.bin"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // ── Install: happy path ──

    @Test @MainActor func installTransitionsMissingToInstalled() throws {
        let root = tempRoot()
        let fixture = makeFixture(root: root)
        let cache = ModelCache(appSupportOverride: root)

        #expect(cache.baseModelStatus().state == .missing)

        let manifest = ModelArtifactManifest(
            modelID: ModelCache.baseModelID,
            version: "1.0.0",
            sourceURL: fixture,
            expectedFiles: ["weights.gguf"]
        )
        try cache.installBaseModel(from: manifest)

        guard case .installed(let url) = cache.baseModelStatus().state else {
            Issue.record("Install did not transition to installed state")
            return
        }
        #expect(url == cache.baseModelDirectory)
    }

    @Test @MainActor func installWritesMetadataFile() throws {
        let root = tempRoot()
        let fixture = makeFixture(root: root)
        let cache = ModelCache(appSupportOverride: root)

        let manifest = ModelArtifactManifest(
            modelID: ModelCache.baseModelID,
            version: "1.0.0",
            sourceURL: fixture,
            expectedFiles: ["weights.gguf"]
        )
        try cache.installBaseModel(from: manifest)

        let metadataURL = cache.baseModelMetadataURL
        #expect(FileManager.default.fileExists(atPath: metadataURL.path(percentEncoded: false)))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: metadataURL)
        let metadata = try decoder.decode(InstalledModelMetadata.self, from: data)

        #expect(metadata.modelID == ModelCache.baseModelID)
        #expect(metadata.displayName == ModelCache.baseDisplayName)
        #expect(metadata.version == "1.0.0")
        #expect(metadata.platform == ModelCache.platformDirectoryName)
        #expect(metadata.sourceURL == fixture)
    }

    @Test @MainActor func installCopiesModelFiles() throws {
        let root = tempRoot()
        let fixture = makeFixture(root: root, extraFiles: ["config.json", "tokenizer.model"])
        let cache = ModelCache(appSupportOverride: root)

        let manifest = ModelArtifactManifest(
            modelID: ModelCache.baseModelID,
            version: "1.0.0",
            sourceURL: fixture,
            expectedFiles: ["weights.gguf", "config.json", "tokenizer.model"]
        )
        try cache.installBaseModel(from: manifest)

        for file in ["weights.gguf", "config.json", "tokenizer.model"] {
            let fileURL = cache.baseModelDirectory.appending(path: file, directoryHint: .notDirectory)
            #expect(FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
        }
    }

    // ── Install: replacement of stale contents ──

    @Test @MainActor func installReplacesPriorModelContents() throws {
        let root = tempRoot()
        let fixtureA = makeFixture(root: root, extraFiles: ["old.bin"])
        let fixtureB = makeFixture(root: root, extraFiles: ["new.bin"])
        let cache = ModelCache(appSupportOverride: root)

        // First install
        let manifestA = ModelArtifactManifest(
            modelID: ModelCache.baseModelID,
            version: "0.9.0",
            sourceURL: fixtureA,
            expectedFiles: ["weights.gguf", "old.bin"]
        )
        try cache.installBaseModel(from: manifestA)
        #expect(FileManager.default.fileExists(
            atPath: cache.baseModelDirectory.appending(path: "old.bin").path(percentEncoded: false)
        ))

        // Second install — should replace old.bin with new.bin
        let manifestB = ModelArtifactManifest(
            modelID: ModelCache.baseModelID,
            version: "1.0.0",
            sourceURL: fixtureB,
            expectedFiles: ["weights.gguf", "new.bin"]
        )
        try cache.installBaseModel(from: manifestB)

        #expect(!FileManager.default.fileExists(
            atPath: cache.baseModelDirectory.appending(path: "old.bin").path(percentEncoded: false)
        ))
        #expect(FileManager.default.fileExists(
            atPath: cache.baseModelDirectory.appending(path: "new.bin").path(percentEncoded: false)
        ))
    }

    // ── Remove ──

    @Test @MainActor func removeReturnsToMissingState() throws {
        let root = tempRoot()
        let fixture = makeFixture(root: root)
        let cache = ModelCache(appSupportOverride: root)

        let manifest = ModelArtifactManifest(
            modelID: ModelCache.baseModelID,
            version: "1.0.0",
            sourceURL: fixture,
            expectedFiles: ["weights.gguf"]
        )
        try cache.installBaseModel(from: manifest)
        #expect(cache.baseModelStatus().state == .installed(cache.baseModelDirectory))

        try cache.removeBaseModel()
        #expect(cache.baseModelStatus().state == .missing)
    }

    @Test @MainActor func removeIsIdempotentOnMissing() throws {
        let root = tempRoot()
        let cache = ModelCache(appSupportOverride: root)

        // Model is already missing — removing should not throw
        try cache.removeBaseModel()
        #expect(cache.baseModelStatus().state == .missing)
        // And again, still idempotent
        try cache.removeBaseModel()
        #expect(cache.baseModelStatus().state == .missing)
    }

    // ── Helpers ──

    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "cache-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func makeFixture(root: URL, extraFiles: [String] = []) -> URL {
        let fixture = root.appending(path: "fixture-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        // Write the mandatory weights file
        write(file: fixture.appending(path: "weights.gguf"), contents: "weights")
        // Write extra files
        for name in extraFiles {
            write(file: fixture.appending(path: name), contents: name)
        }
        return fixture
    }

    private func write(file: URL, contents: String) {
        try? contents.data(using: .utf8)?.write(to: file)
    }

    @Test @MainActor func reasoningParserSeparatesThinkBlock() {
        let parsed = ReasoningParser.split("<think>Check carefully.</think>Final answer.")

        #expect(parsed.reasoning == "Check carefully.")
        #expect(parsed.text == "Final answer.")
    }
}
