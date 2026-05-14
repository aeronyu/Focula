import XCTest
@testable import WatchMyBackCore

final class ModelProviderTests: XCTestCase {
    func testDefaultSettingsUseBuiltInGemma() {
        let settings = AppSettings()

        XCTAssertEqual(settings.modelSelection.provider, .builtInGemma)
        XCTAssertEqual(settings.modelSelection.modelID, BuiltInModelCatalog.defaultModel.id)
        XCTAssertFalse(settings.modelSelection.cloudClassificationAllowed)
        XCTAssertEqual(settings.builtInModelStatus.installState, .missing)
    }

    func testBuiltInCatalogIncludesQuantizedGemmaVariants() {
        XCTAssertEqual(BuiltInModelCatalog.defaultModel.id, "mlx-community/gemma-4-e2b-it-4bit")
        XCTAssertEqual(BuiltInModelCatalog.all.map(\.precision), ["4-bit MLX", "8-bit MLX", "BF16 MLX"])
        XCTAssertEqual(
            BuiltInModelCatalog.all.map(\.repository),
            [
                "mlx-community/gemma-4-e2b-it-4bit",
                "mlx-community/gemma-4-e2b-it-8bit",
                "mlx-community/gemma-4-e2b-it-bf16"
            ]
        )
    }

    func testLegacyBuiltInModelIDMigratesToDefaultQuantizedModel() throws {
        let payload = """
        {
          "endpoint": "http:\\/\\/127.0.0.1:1234\\/v1\\/chat\\/completions",
          "model": "google\\/gemma-4-E2B-it",
          "modelSelection": {
            "provider": "builtInGemma",
            "modelID": "google\\/gemma-4-E2B-it",
            "cloudClassificationAllowed": false
          },
          "builtInModelStatus": {
            "provider": "builtInGemma",
            "modelID": "google\\/gemma-4-E2B-it",
            "installState": "missing",
            "statusMessage": "old",
            "isVisionCapable": true,
            "isUsable": false
          },
          "modelTelemetry": {
            "parseFailureCount": 0,
            "successCount": 0
          },
          "sampleIntervalSeconds": 60,
          "paused": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppSettings.self, from: payload)

        XCTAssertEqual(decoded.model, BuiltInModelCatalog.defaultModel.id)
        XCTAssertEqual(decoded.modelSelection.modelID, BuiltInModelCatalog.defaultModel.id)
        XCTAssertEqual(decoded.builtInModelStatus.modelID, BuiltInModelCatalog.defaultModel.id)
    }

    func testProviderSwitchPersistsInSettingsBlob() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-my-back-settings-\(UUID().uuidString).sqlite")
            .path
        let store = try DatabaseStore(path: path)
        let selection = ModelSelection(
            provider: .oMLX,
            modelID: "mlx-community/gemma-4-e2b-it-4bit",
            endpoint: URL(string: "http://127.0.0.1:8123/v1/chat/completions")!,
            cloudClassificationAllowed: false
        )
        var settings = AppSettings()
        settings.modelSelection = selection

        try store.saveSettings(settings)

        XCTAssertEqual(try store.fetchSettings().modelSelection, selection)
    }

    func testCloudProviderIsBlockedUntilUserOptsIn() {
        let blocked = ModelSelection(
            provider: .cloudOptIn,
            modelID: "gpt-4.1-mini",
            endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
            cloudClassificationAllowed: false
        )
        let allowed = ModelSelection(
            provider: .cloudOptIn,
            modelID: "gpt-4.1-mini",
            endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
            cloudClassificationAllowed: true
        )

        XCTAssertFalse(blocked.canSendScreenshots)
        XCTAssertTrue(allowed.canSendScreenshots)
    }

    func testUnavailableOptionalProvidersDoNotBlockBuiltInGemma() {
        let detector = ModelRuntimeDetector(commandProbe: StaticCommandProbe(existingCommands: []))
        let statuses = detector.statuses(selected: AppSettings().modelSelection)

        XCTAssertEqual(statuses.first(where: { $0.provider == .builtInGemma })?.installState, .missing)
        XCTAssertEqual(statuses.first(where: { $0.provider == .oMLX })?.isUsable, false)
        XCTAssertEqual(statuses.first(where: { $0.provider == .lmStudio })?.isUsable, false)
    }
}

private struct StaticCommandProbe: CommandProbing {
    let existingCommands: Set<String>

    func commandExists(_ name: String) -> Bool {
        existingCommands.contains(name)
    }
}
