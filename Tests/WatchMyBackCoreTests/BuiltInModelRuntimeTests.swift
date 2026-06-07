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

    func testBuiltInRuntimeUnavailableIsDistinctFromMissingInstall() {
        let result = BuiltInGemmaClient.runtimeUnavailableFallback()

        XCTAssertEqual(result.focusState, .unknown)
        XCTAssertEqual(result.activityCategory, "built_in_model_runtime_error")
        XCTAssertEqual(result.evidenceCodes, ["builtin_gemma_sidecar_unavailable"])
        XCTAssertNil(result.activitySummary)
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

    func testApplicationSupportRootMigratesLegacyFolderToFocula() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("focula-support-\(UUID().uuidString)", isDirectory: true)
        let support = root.appendingPathComponent("Application Support", isDirectory: true)
        let legacy = support.appendingPathComponent("Watch My Back", isDirectory: true)
        let marker = legacy.appendingPathComponent("marker.txt")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("legacy model data".utf8).write(to: marker)
        defer { try? FileManager.default.removeItem(at: root) }

        let migrated = try ModelSupportPaths.applicationSupportRoot(base: support)

        XCTAssertEqual(migrated.lastPathComponent, "Focula")
        XCTAssertTrue(FileManager.default.fileExists(atPath: migrated.appendingPathComponent("marker.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
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
