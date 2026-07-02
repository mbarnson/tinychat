//
//  tinychatUITests.swift
//  tinychatUITests
//
//  Created by Matthew Barnson on 7/1/26.
//

import XCTest

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
            XCTFail(app.staticTexts["model-install-error"].label)
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


    private func realModelFixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".build/coreai-exports/qwen3-0.6b-macos/qwen3_0_6b_4bit_dynamic", directoryHint: .isDirectory)
    }

    private func installRealModelFixtureIntoAppSupport(from fixture: URL) throws {
        let destination = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers/org.barnson.tinychat/Data/Library/Application Support/tinychat/Models/qwen3-0.6b/macOS", directoryHint: .isDirectory)
        let parent = destination.deletingLastPathComponent()

        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: fixture, to: destination)
    }
}
