import XCTest
@testable import WatchMyBackCore

final class ModelProviderTests: XCTestCase {
    func testDefaultSettingsUseBuiltInGemma() {
        let settings = AppSettings()

        XCTAssertEqual(settings.modelSelection.provider, .builtInGemma)
        XCTAssertEqual(settings.modelSelection.modelID, BuiltInModelCatalog.gemma4E2B.id)
        XCTAssertFalse(settings.modelSelection.cloudClassificationAllowed)
        XCTAssertEqual(settings.builtInModelStatus.installState, .missing)
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

        XCTAssertEqual(statuses.first(where: { $0.provider == .builtInGemma })?.isUsable, true)
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
