//
//  tinychatUITests.swift
//  tinychatUITests
//
//  Created by Matthew Barnson on 7/1/26.
//

import XCTest
import CryptoKit

final class tinychatUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDeterministicChatSendStopAndPersistence() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--reset-chat-state",
            "--use-deterministic-chat-engine",
            "--auto-send-prompt",
            "Hello tinychat",
        ]
        app.launch()

        let streamingMessage = app.staticTexts["streaming-assistant-message"]
        XCTAssertTrue(streamingMessage.waitForExistence(timeout: 5))

        let assistantMessage = app.staticTexts["assistant-message"]
        XCTAssertTrue(assistantMessage.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["copy-message-button"].waitForExistence(timeout: 2))

        app.terminate()

        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["--use-deterministic-chat-engine"]
        relaunched.launch()

        XCTAssertTrue(relaunched.staticTexts["assistant-message"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRealModelSmokeWhenEnabled() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["TINYCHAT_RUN_REAL_MODEL_UI_TEST"] == "1",
            "Set TINYCHAT_RUN_REAL_MODEL_UI_TEST=1 to run the real CoreAI smoke."
        )
        let fixture = realModelFixtureURL()
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: fixture.appending(path: "metadata.json").path(percentEncoded: false)),
            "Seed or export Qwen3 0.6B before running real model smoke."
        )
        try installRealModelFixtureIntoAppSupport(from: fixture)


        let app = XCUIApplication()
        app.launchArguments = [
            "--reset-chat-state",
            "--disable-thinking",
            "--auto-send-prompt",
            "Say hello in one short sentence.",
        ]
        app.launch()

        if app.staticTexts["model-install-error"].exists {
            XCTFail("model-install-error shown: \(app.staticTexts["model-install-error"].label); app=\(app.debugDescription)")
            return
        }
        XCTAssertTrue(app.staticTexts["model-status-installed"].waitForExistence(timeout: 10))

        let assistantMessage = app.staticTexts["assistant-message"]
        if !assistantMessage.waitForExistence(timeout: 180) {
            if app.staticTexts["chat-error"].exists {
                XCTFail(app.staticTexts["chat-error"].label)
            } else if app.staticTexts["assistant-message-error"].exists {
                XCTFail(app.staticTexts["assistant-message-error"].label)
            } else {
                XCTFail("Timed out waiting for real CoreAI assistant output.")
            }
        }

        if app.staticTexts["chat-error"].exists {
            XCTFail(app.staticTexts["chat-error"].label)
        }
        if app.staticTexts["assistant-message-error"].exists {
            XCTFail(app.staticTexts["assistant-message-error"].label)
        }
    }


    @MainActor
    func testFirstRunDownloadButtonUsesManifest() throws {
        let (manifestURL, _) = try createTestManifestAndZip()
        defer { try? FileManager.default.removeItem(at: manifestURL.deletingLastPathComponent()) }
        addTeardownBlock {
            let cleanupApp = XCUIApplication()
            cleanupApp.terminate()
            cleanupApp.launchArguments = ["--reset-model-cache"]
            cleanupApp.launch()
            _ = cleanupApp.staticTexts["model-status-missing"].waitForExistence(timeout: 10)
            cleanupApp.terminate()
        }

        let app = XCUIApplication()
        app.launchArguments = [
            "--reset-chat-state",
            "--reset-model-cache",
            "--model-release-manifest-url",
            manifestURL.path(percentEncoded: false),
        ]
        app.launch()

        let downloadButton = app.buttons["download-model-button"]
        guard downloadButton.waitForExistence(timeout: 30) else {
            XCTFail("download-model-button never appeared; manifestURL=\(manifestURL.path(percentEncoded: false)); app=\(app.debugDescription)")
            return
        }

#if os(macOS)
        downloadButton.click()
#else
        downloadButton.tap()
#endif

        if !app.staticTexts["model-status-installed"].waitForExistence(timeout: 120) {
            let progress = app.staticTexts["model-download-progress"].exists
                ? app.staticTexts["model-download-progress"].label
                : "no progress label"
            let installError = app.staticTexts["model-install-error"].exists
                ? app.staticTexts["model-install-error"].label
                : "no install error label"
            XCTFail("model-status-installed never appeared after tapping download-model-button; progress=\(progress); \(installError); app=\(app.debugDescription)")
        }

        if app.staticTexts["model-install-error"].exists {
            XCTFail("model-install-error shown: " + app.staticTexts["model-install-error"].label)
        }

        let deleteButton = app.buttons["delete-model-button"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 10), "delete-model-button never appeared after fixture install")
#if os(macOS)
        deleteButton.click()
#else
        deleteButton.tap()
#endif
        XCTAssertTrue(app.staticTexts["model-status-missing"].waitForExistence(timeout: 30), "model-status-missing never appeared after deleting fixture model")

        app.terminate()
    }

    private func createTestManifestAndZip() throws -> (manifestURL: URL, zipURL: URL) {
        let tmpDir = FileManager.default.temporaryDirectory
            .appending(path: "tinychat-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let modelFile = tmpDir.appending(path: "model.mil")
        let fileData = "model-test-content".data(using: .utf8)!
        try fileData.write(to: modelFile)

        let zipURL = tmpDir.appending(path: "model.zip", directoryHint: .notDirectory)
        let zipData = makeStoredZipBytes(entryName: "test-model/model.mil", entryData: fileData)
        try zipData.write(to: zipURL)

        let sha = Self.sha256Hex(of: zipData)
        let zipSize = Int64(zipData.count)

        let manifest = [
            "artifacts": [
                [
                    "modelID": "qwen3-0.6b",
                    "displayName": "Qwen3 0.6B",
                    "version": "1.0.0-test",
                    "platform": "macOS",
                    "archiveURL": zipURL.absoluteString,
                    "archiveSHA256": sha,
                    "byteSize": zipSize,
                    "expandedDirectoryName": "test-model",
                    "expectedFiles": ["model.mil"],
                ],
            ],
        ]
        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted)
        let manifestURL = tmpDir.appending(path: "manifest.json", directoryHint: .notDirectory)
        try manifestData.write(to: manifestURL)

        return (manifestURL, zipURL)
    }

    private func makeStoredZipBytes(entryName: String, entryData: Data) -> Data {
        var zipData = Data()
        let nameBytes = entryName.utf8

        func appendLE<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { zipData.append(contentsOf: $0) }
        }

        appendLE(UInt32(0x0403_4B50))   // local file header signature
        appendLE(UInt16(20))             // version needed
        appendLE(UInt16(0))              // flags
        appendLE(UInt16(0))              // method = stored
        appendLE(UInt16(0))              // mod time
        appendLE(UInt16(0))              // mod date
        appendLE(UInt32(0))              // crc32 (extractor doesn't check)
        appendLE(UInt32(UInt32(entryData.count)))  // compressed size
        appendLE(UInt32(UInt32(entryData.count)))  // uncompressed size
        appendLE(UInt16(UInt16(nameBytes.count)))  // file name length
        appendLE(UInt16(0))              // extra field length
        zipData.append(contentsOf: nameBytes)
        zipData.append(entryData)

        return zipData
    }

    private static func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func realModelFixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".build/coreai-exports/qwen3-0.6b-macos/qwen3_0_6b_4bit_dynamic", directoryHint: .isDirectory)
    }

    private func installRealModelFixtureIntoAppSupport(from fixture: URL) throws {
        let destination = installedModelDirectory()
        let parent = destination.deletingLastPathComponent()

        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: fixture, to: destination)
    }

    private func installedModelDirectory() -> URL {
        realUserHomeDirectory()
            .appending(path: "Library/Containers/org.barnson.tinychat/Data/Library/Application Support/tinychat/Models/qwen3-0.6b/macOS", directoryHint: .isDirectory)
    }

    private func realUserHomeDirectory() -> URL {
        let components = URL(fileURLWithPath: #filePath).pathComponents
        if let usersIndex = components.firstIndex(of: "Users") {
            let usernameIndex = components.index(after: usersIndex)
            if components.indices.contains(usernameIndex) {
                let homePath = components[...usernameIndex].joined(separator: "/")
                return URL(fileURLWithPath: homePath, isDirectory: true)
            }
        }

        return FileManager.default.homeDirectoryForCurrentUser
    }
}
