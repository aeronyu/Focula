import XCTest
@testable import WatchMyBackCore

final class VisionClassifierTests: XCTestCase {
    func testParsesStrictClassifierJSONFromChatCompletion() throws {
        let payload = """
        {
          "choices": [
            {
              "message": {
                "content": "{\\"focusState\\":\\"on_goal\\",\\"activityCategory\\":\\"coding\\",\\"activitySummary\\":\\"Working in the code editor\\",\\"confidence\\":0.91,\\"evidenceCodes\\":[\\"allowed_app\\",\\"goal_match\\"],\\"nudgeSuggested\\":false}"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let result = try LocalVisionClient.parseChatCompletionResponse(payload)

        XCTAssertEqual(result.focusState, .onGoal)
        XCTAssertEqual(result.activityCategory, "coding")
        XCTAssertEqual(result.activitySummary, "Working in the code editor")
        XCTAssertEqual(result.confidence, 0.91, accuracy: 0.001)
        XCTAssertEqual(result.evidenceCodes, ["allowed_app", "goal_match"])
        XCTAssertFalse(result.nudgeSuggested)
    }

    func testMalformedClassifierOutputFallsBackToUnknown() {
        let result = VisionClassifierResult.fallback()

        XCTAssertEqual(result.focusState, .unknown)
        XCTAssertEqual(result.activityCategory, "unknown")
        XCTAssertNil(result.activitySummary)
        XCTAssertEqual(result.confidence, 0)
        XCTAssertFalse(result.nudgeSuggested)
    }

    func testActivitySummaryRedactorRemovesSensitiveFragments() {
        let redacted = ActivitySummaryRedactor.redact(
            "Reviewing \"secret launch notes\" at https://example.com with me@example.com and ticket 123456"
        )

        XCTAssertEqual(redacted, "Reviewing [text] at [link] with [email] and ticket [number]")
    }
}
