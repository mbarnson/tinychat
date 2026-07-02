//
//  tinychatTests.swift
//  tinychatTests
//
//  Created by Matthew Barnson on 7/1/26.
//

import Foundation
import SwiftData
import CryptoKit
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

    // ── Install: ZIP download path ──

    @Test @MainActor func manifestArtifactReturnsMatchingPlatform() throws {
        let artifact = ModelReleaseArtifact(
            version: "1.0.0",
            platform: ModelCache.platformDirectoryName,
            archiveURL: URL(string: "https://example.com/m.zip")!,
            archiveSHA256: "abc",
            byteSize: 0,
            expandedDirectoryName: "model",
            expectedFiles: ["weights.gguf"]
        )
        let manifest = ModelReleaseManifest(artifacts: [artifact])

        let matched = try manifest.artifact()
        #expect(matched.version == "1.0.0")
    }

    @Test @MainActor func manifestArtifactThrowsForWrongPlatform() throws {
        let artifact = ModelReleaseArtifact(
            version: "1.0.0",
            platform: "Android",
            archiveURL: URL(string: "https://example.com/m.zip")!,
            archiveSHA256: "abc",
            byteSize: 0,
            expandedDirectoryName: "model",
            expectedFiles: ["weights.gguf"]
        )
        let manifest = ModelReleaseManifest(artifacts: [artifact])

        #expect(throws: ModelReleaseManifestError.noArtifact(platform: ModelCache.platformDirectoryName)) {
            try manifest.artifact()
        }
    }

    @MainActor
    @Test func installZipArtifactVerifiesAndInstalls() async throws {
        let root = tempRoot()

        let zipData = makeZipWithEntry(name: "model/weights.gguf", data: "weights".data(using: .utf8)!)
        let zipURL = root.appending(path: "model.zip")
        try zipData.write(to: zipURL)
        let sha = dataSHA256Hex(zipData)

        let manifest = ModelReleaseManifest(artifacts: [ModelReleaseArtifact(
            version: "2.0.0",
            archiveURL: zipURL,
            archiveSHA256: sha,
            byteSize: Int64(zipData.count),
            expandedDirectoryName: "model",
            expectedFiles: ["weights.gguf"]
        )])

        let cache = ModelCache(appSupportOverride: root)
        let manager = ModelDownloadManager(cache: cache)

        let status = try await manager.installBaseModel(from: manifest)

        #expect(status.isInstalled == true)
        #expect(status.modelID == ModelCache.baseModelID)

        let modelDir = cache.baseModelDirectory
        #expect(FileManager.default.fileExists(atPath: modelDir.path))

        let weightsURL = modelDir.appending(path: "weights.gguf")
        #expect(FileManager.default.fileExists(atPath: weightsURL.path))

        let metaURL = modelDir.appending(path: ModelCache.metadataFileName)
        #expect(FileManager.default.fileExists(atPath: metaURL.path))
        let metaJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: metaURL)) as! [String: Any]
        #expect(metaJSON["version"] as? String == "2.0.0")
        #expect((metaJSON["sourceURL"] as? String)?.contains("/expanded/model") == true)
    }

    @MainActor
    @Test func installZipArtifactRejectsSHA256Mismatch() async {
        let root = tempRoot()

        let zipData = makeZipWithEntry(name: "model/weights.gguf", data: "weights".data(using: .utf8)!)
        let zipURL = root.appending(path: "model.zip")
        try? zipData.write(to: zipURL)

        let manifest = ModelReleaseManifest(artifacts: [ModelReleaseArtifact(
            version: "1.0.0",
            archiveURL: zipURL,
            archiveSHA256: "0000000000000000000000000000000000000000000000000000000000000000",
            byteSize: Int64(zipData.count),
            expandedDirectoryName: "model",
            expectedFiles: ["weights.gguf"]
        )])

        let cache = ModelCache(appSupportOverride: root)
        let manager = ModelDownloadManager(cache: cache)

        await #expect(throws: ModelDownloadError.sha256Mismatch(
            expected: "0000000000000000000000000000000000000000000000000000000000000000",
            actual: dataSHA256Hex(zipData)
        )) {
            try await manager.installBaseModel(from: manifest)
        }

        #expect(cache.baseModelStatus().state == .missing)
    }

    @MainActor
    @Test func installZipArtifactRejectsUnsafeZipEntry() async {
        let root = tempRoot()

        let zipData = makeZipWithEntry(name: "../escape.txt", data: "pwned".data(using: .utf8)!)
        let zipURL = root.appending(path: "bad.zip")
        try? zipData.write(to: zipURL)
        let sha = dataSHA256Hex(zipData)

        let manifest = ModelReleaseManifest(artifacts: [ModelReleaseArtifact(
            version: "1.0.0",
            archiveURL: zipURL,
            archiveSHA256: sha,
            byteSize: Int64(zipData.count),
            expandedDirectoryName: "model",
            expectedFiles: ["weights.gguf"]
        )])

        let cache = ModelCache(appSupportOverride: root)
        let manager = ModelDownloadManager(cache: cache)

        await #expect(throws: ModelDownloadError.unsafeZipEntry("../escape.txt")) {
            try await manager.installBaseModel(from: manifest)
        }

        // Ensure nothing leaked past extraction boundary
        let escapeInRoot = root.appending(path: "escape.txt")
        #expect(!FileManager.default.fileExists(atPath: escapeInRoot.path))
        let modelDir = cache.baseModelDirectory
        #expect(!FileManager.default.fileExists(atPath: modelDir.path))
    }

    @MainActor
    @Test func installZipArtifactRejectsDeflateCompression() async {
        let root = tempRoot()

        var zipData = makeZipWithEntry(name: "model/weights.gguf", data: "weights".data(using: .utf8)!)
        // Flip method bytes at offset 8..9 from 0 (store) -> 8 (deflate)
        zipData[8] = 0x08
        zipData[9] = 0x00

        let sha = dataSHA256Hex(zipData)
        let zipURL = root.appending(path: "deflate.zip")
        try? zipData.write(to: zipURL)

        let manifest = ModelReleaseManifest(artifacts: [ModelReleaseArtifact(
            version: "1.0.0",
            archiveURL: zipURL,
            archiveSHA256: sha,
            byteSize: Int64(zipData.count),
            expandedDirectoryName: "model",
            expectedFiles: ["weights.gguf"]
        )])

        let cache = ModelCache(appSupportOverride: root)
        let manager = ModelDownloadManager(cache: cache)

        await #expect(throws: ModelDownloadError.unsupportedZipCompression(method: 8)) {
            try await manager.installBaseModel(from: manifest)
        }

        let modelDir = cache.baseModelDirectory
        #expect(!FileManager.default.fileExists(atPath: modelDir.path))
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

    @Test func coreAIRealModelEmitsNonWhitespaceWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["TINYCHAT_RUN_REAL_MODEL_UNIT_TEST"] == "1" else { return }

        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".build/coreai-exports/qwen3-0.6b-macos/qwen3_0_6b_4bit_dynamic", directoryHint: .isDirectory)

        let engine = CoreAIChatEngine(modelURL: fixture)
        var text = ""
        var reasoning = ""
        for try await event in engine.responseEvents(
            for: ChatRequest(
                prompt: "Say hello in one short sentence.",
                thinkingEnabled: false,
                priorMessages: []
            )
        ) {
            switch event {
            case .text(let delta):
                text += delta
            case .reasoning(let delta):
                reasoning += delta
            }
        }

        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Issue.record("CoreAI emitted text=\(text.debugDescription), reasoning=\(reasoning.debugDescription)")
        }
        #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // ── Helpers ──

    private func tempRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "cache-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
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


    private func makeZipWithEntry(name: String, data: Data) -> Data {
        let nameBytes = Array(name.utf8)
        let fileNameLength = UInt16(nameBytes.count)
        let extraLength: UInt16 = 0
        let compressedSize = UInt32(data.count)

        var zip = Data()
        zip.append(contentsOf: leBytes(from: UInt32(0x0403_4B50))) // local file header signature
        zip.append(contentsOf: leBytes(from: UInt16(0x0014)))       // version needed
        zip.append(contentsOf: leBytes(from: UInt16(0)))            // flags
        zip.append(contentsOf: leBytes(from: UInt16(0)))            // compression method (store)
        zip.append(contentsOf: leBytes(from: UInt16(0)))            // mod time
        zip.append(contentsOf: leBytes(from: UInt16(0)))            // mod date
        zip.append(contentsOf: leBytes(from: UInt32(0)))            // crc-32
        zip.append(contentsOf: leBytes(from: compressedSize))       // compressed size
        zip.append(contentsOf: leBytes(from: compressedSize))       // uncompressed size
        zip.append(contentsOf: leBytes(from: fileNameLength))       // file name length
        zip.append(contentsOf: leBytes(from: extraLength))          // extra field length
        zip.append(contentsOf: nameBytes)
        zip.append(data)

        let centralDirOffset = UInt32(zip.count)
        zip.append(contentsOf: leBytes(from: UInt32(0x0201_4B50))) // central directory signature
        zip.append(contentsOf: leBytes(from: UInt16(0x0014)))       // version made by
        zip.append(contentsOf: leBytes(from: UInt16(0x0014)))       // version needed
        zip.append(contentsOf: leBytes(from: UInt16(0)))            // flags
        zip.append(contentsOf: leBytes(from: UInt16(0)))            // compression method
        zip.append(contentsOf: leBytes(from: UInt16(0)))            // mod time
        zip.append(contentsOf: leBytes(from: UInt16(0)))            // mod date
        zip.append(contentsOf: leBytes(from: UInt32(0)))            // crc-32
        zip.append(contentsOf: leBytes(from: compressedSize))       // compressed size
        zip.append(contentsOf: leBytes(from: compressedSize))       // uncompressed size
        zip.append(contentsOf: leBytes(from: fileNameLength))       // file name length
        zip.append(contentsOf: leBytes(from: UInt16(0)))            // extra field length
        zip.append(contentsOf: leBytes(from: UInt16(0)))            // comment length
        zip.append(contentsOf: leBytes(from: UInt16(0)))            // disk number start
        zip.append(contentsOf: leBytes(from: UInt16(0)))            // internal attrs
        zip.append(contentsOf: leBytes(from: UInt32(0)))            // external attrs
        zip.append(contentsOf: leBytes(from: centralDirOffset))     // local header offset
        zip.append(contentsOf: nameBytes)

        let centralDirSize = UInt32(zip.count - Int(centralDirOffset))
        zip.append(contentsOf: leBytes(from: UInt32(0x0605_4B50))) // EOCD signature
        zip.append(contentsOf: leBytes(from: UInt16(0)))            // disk number
        zip.append(contentsOf: leBytes(from: UInt16(0)))            // CD disk start
        zip.append(contentsOf: leBytes(from: UInt16(1)))            // CD records on disk
        zip.append(contentsOf: leBytes(from: UInt16(1)))            // total CD records
        zip.append(contentsOf: leBytes(from: centralDirSize))       // CD size
        zip.append(contentsOf: leBytes(from: centralDirOffset))     // CD offset
        zip.append(contentsOf: leBytes(from: UInt16(0)))            // comment length

        return zip
    }

    private func leBytes(from value: UInt16) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }

    private func leBytes(from value: UInt32) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }

    private func dataSHA256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @Test @MainActor func reasoningParserSeparatesThinkBlock() {
        let parsed = ReasoningParser.split("<think>Check carefully.</think>Final answer.")

        #expect(parsed.reasoning == "Check carefully.")
        #expect(parsed.text == "Final answer.")
    }
}

