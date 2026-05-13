import XCTest
@testable import WatchMyBackCore

final class BuiltInModelRuntimeTests: XCTestCase {
    func testBuiltInModelInstallStateTransitions() {
        XCTAssertEqual(BuiltInModelInstallState.missing.nextForDownloadStart(), .downloading)
        XCTAssertEqual(BuiltInModelInstallState.downloading.nextForDownloadSuccess(), .ready)
        XCTAssertEqual(BuiltInModelInstallState.downloading.nextForDownloadFailure(), .failed)
        XCTAssertEqual(BuiltInModelInstallState.ready.nextForDelete(), .missing)
    }

    func testParsesStrictClassifierJSONFromBuiltInSidecar() throws {
        let payload = """
        {"focusState":"on_goal","activityCategory":"coding","confidence":0.93,"evidenceCodes":["goal_match"],"nudgeSuggested":false}
        """.data(using: .utf8)!

        let result = try BuiltInGemmaClient.parseSidecarResponse(payload)

        XCTAssertEqual(result.focusState, .onGoal)
        XCTAssertEqual(result.activityCategory, "coding")
        XCTAssertEqual(result.confidence, 0.93, accuracy: 0.001)
        XCTAssertEqual(result.evidenceCodes, ["goal_match"])
        XCTAssertFalse(result.nudgeSuggested)
    }

    func testModelDownloadStateStoresNoScreenshotFields() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-my-back-model-state-\(UUID().uuidString).sqlite")
            .path
        let store = try DatabaseStore(path: path)
        var settings = AppSettings()
        settings.builtInModelStatus = ModelRuntimeStatus(
            provider: .builtInGemma,
            modelID: BuiltInModelCatalog.gemma4E2B.id,
            installState: .ready,
            statusMessage: "Ready",
            storagePath: "/tmp/model",
            isVisionCapable: true,
            isUsable: true
        )

        try store.saveSettings(settings)

        XCTAssertEqual(try store.fetchSettings().builtInModelStatus.installState, .ready)
        XCTAssertFalse(try store.schemaContainsScreenshotStorage())
    }
}
