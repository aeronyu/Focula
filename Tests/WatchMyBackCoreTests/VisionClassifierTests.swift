import XCTest
@testable import WatchMyBackCore

final class VisionClassifierTests: XCTestCase {
    func testParsesStrictClassifierJSONFromChatCompletion() throws {
        let payload = """
        {
          "choices": [
            {
              "message": {
                "content": "{\\"focusState\\":\\"on_goal\\",\\"activityCategory\\":\\"coding\\",\\"confidence\\":0.91,\\"evidenceCodes\\":[\\"allowed_app\\",\\"goal_match\\"],\\"nudgeSuggested\\":false}"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let result = try LocalVisionClient.parseChatCompletionResponse(payload)

        XCTAssertEqual(result.focusState, .onGoal)
        XCTAssertEqual(result.activityCategory, "coding")
        XCTAssertEqual(result.confidence, 0.91, accuracy: 0.001)
        XCTAssertEqual(result.evidenceCodes, ["allowed_app", "goal_match"])
        XCTAssertFalse(result.nudgeSuggested)
    }

    func testMalformedClassifierOutputFallsBackToUnknown() {
        let result = VisionClassifierResult.fallback()

        XCTAssertEqual(result.focusState, .unknown)
        XCTAssertEqual(result.activityCategory, "unknown")
        XCTAssertEqual(result.confidence, 0)
        XCTAssertFalse(result.nudgeSuggested)
    }
}
