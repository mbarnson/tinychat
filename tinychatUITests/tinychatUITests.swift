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
        app.launchArguments = ["--reset-chat-state", "--use-deterministic-chat-engine"]
        app.launch()

        let composer = app.textViews["message-composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap()
        composer.typeText("Hello tinychat")

        let sendButton = app.buttons["send-button"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 2))
        XCTAssertTrue(sendButton.isEnabled)
        sendButton.tap()

        let streamingMessage = app.staticTexts["streaming-assistant-message"]
        XCTAssertTrue(streamingMessage.waitForExistence(timeout: 5))

        let stopButton = app.buttons["stop-button"]
        if stopButton.waitForExistence(timeout: 1) {
            stopButton.tap()
        }

        let assistantMessage = app.staticTexts["assistant-message"]
        XCTAssertTrue(assistantMessage.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["copy-message-button"].waitForExistence(timeout: 2))

        app.terminate()

        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["--use-deterministic-chat-engine"]
        relaunched.launch()

        XCTAssertTrue(relaunched.staticTexts["assistant-message"].waitForExistence(timeout: 5))
    }
}
