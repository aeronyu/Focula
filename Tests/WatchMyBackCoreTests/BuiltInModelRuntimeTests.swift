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
        {"focusState":"on_goal","activityCategory":"coding","activitySummary":"Building the app locally","confidence":0.93,"evidenceCodes":["goal_match"],"nudgeSuggested":false}
        """.data(using: .utf8)!

        let result = try BuiltInGemmaClient.parseSidecarResponse(payload)

        XCTAssertEqual(result.focusState, .onGoal)
        XCTAssertEqual(result.activityCategory, "coding")
        XCTAssertEqual(result.activitySummary, "Building the app locally")
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
            modelID: BuiltInModelCatalog.defaultModel.id,
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

    func testBuiltInModelStorageFolderUsesRepositoryName() {
        XCTAssertEqual(
            ModelSupportPaths.storageFolderName(for: BuiltInModelCatalog.gemma4E2B4Bit.repository),
            "mlx-community__gemma-4-e2b-it-4bit"
        )
        XCTAssertEqual(
            ModelSupportPaths.storageFolderName(for: BuiltInModelCatalog.gemma4E2B8Bit.repository),
            "mlx-community__gemma-4-e2b-it-8bit"
        )
    }

    func testModelFolderMetadataRecognizesCatalogAndLegacyFolders() {
        let catalogFolder = ModelSupportPaths.builtInModelFolder(
            for: URL(fileURLWithPath: "/tmp/mlx-community__gemma-4-e2b-it-4bit")
        )
        let legacyFolder = ModelSupportPaths.builtInModelFolder(
            for: URL(fileURLWithPath: "/tmp/google__gemma-4-E2B-it")
        )

        XCTAssertEqual(catalogFolder.displayName, BuiltInModelCatalog.defaultModel.displayName)
        XCTAssertFalse(catalogFolder.isLegacy)
        XCTAssertEqual(legacyFolder.modelID, BuiltInModelCatalog.defaultModel.id)
        XCTAssertTrue(legacyFolder.isLegacy)
    }
}
