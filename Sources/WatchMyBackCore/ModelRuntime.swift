import Foundation

public protocol CommandProbing {
    func commandExists(_ name: String) -> Bool
}

public struct PATHCommandProbe: CommandProbing {
    private let paths: [String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        paths = (environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin")
            .split(separator: ":")
            .map(String.init)
    }

    public func commandExists(_ name: String) -> Bool {
        paths.contains { path in
            FileManager.default.isExecutableFile(atPath: URL(fileURLWithPath: path).appendingPathComponent(name).path)
        }
    }
}

public struct ModelRuntimeDetector {
    private let commandProbe: CommandProbing

    public init(commandProbe: CommandProbing = PATHCommandProbe()) {
        self.commandProbe = commandProbe
    }

    public func statuses(
        selected: ModelSelection,
        builtInStatus: ModelRuntimeStatus = .builtInDefault()
    ) -> [ModelRuntimeStatus] {
        ModelProvider.allCases.map { provider in
            switch provider {
            case .builtInGemma:
                return builtInStatus
            case .oMLX:
                let available = commandProbe.commandExists("omlx-cli")
                return ModelRuntimeStatus(
                    provider: .oMLX,
                    modelID: selected.provider == .oMLX ? selected.modelID : "omlx-selected-model",
                    installState: available ? .ready : .missing,
                    statusMessage: available ? "oMLX CLI detected." : "oMLX not detected. Built-in Gemma remains available.",
                    storagePath: nil,
                    isVisionCapable: available,
                    isUsable: available
                )
            case .lmStudio:
                let available = commandProbe.commandExists("lms")
                return ModelRuntimeStatus(
                    provider: .lmStudio,
                    modelID: selected.provider == .lmStudio ? selected.modelID : "lm-studio-selected-model",
                    installState: available ? .ready : .missing,
                    statusMessage: available ? "LM Studio CLI detected." : "LM Studio not detected. Built-in Gemma remains available.",
                    storagePath: nil,
                    isVisionCapable: available,
                    isUsable: available
                )
            case .openAICompatible:
                return ModelRuntimeStatus(
                    provider: .openAICompatible,
                    modelID: selected.provider == .openAICompatible ? selected.modelID : "local-vision",
                    installState: .ready,
                    statusMessage: "Manual endpoint available when configured.",
                    storagePath: nil,
                    isVisionCapable: true,
                    isUsable: true
                )
            case .cloudOptIn:
                let allowed = selected.provider == .cloudOptIn && selected.cloudClassificationAllowed
                return ModelRuntimeStatus(
                    provider: .cloudOptIn,
                    modelID: selected.provider == .cloudOptIn ? selected.modelID : "cloud-vision",
                    installState: allowed ? .ready : .missing,
                    statusMessage: allowed ? "Cloud screenshots explicitly enabled." : "Cloud provider blocked until explicit opt-in.",
                    storagePath: nil,
                    isVisionCapable: true,
                    isUsable: allowed
                )
            }
        }
    }
}

public enum ModelSupportPaths {
    public static let appSupportFolderName = "Watch My Back"

    public static func applicationSupportRoot(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = base.appendingPathComponent(appSupportFolderName, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    public static func builtInRuntimeRoot(fileManager: FileManager = .default) throws -> URL {
        let folder = try applicationSupportRoot(fileManager: fileManager)
            .appendingPathComponent("BuiltInRuntime", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    public static func builtInModelRoot(fileManager: FileManager = .default) throws -> URL {
        let folder = try builtInRuntimeRoot(fileManager: fileManager)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(BuiltInModelCatalog.gemma4E2B.repository.replacingOccurrences(of: "/", with: "__"), isDirectory: true)
        try fileManager.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        return folder
    }

    public static func pythonEnvironmentRoot(fileManager: FileManager = .default) throws -> URL {
        try builtInRuntimeRoot(fileManager: fileManager)
            .appendingPathComponent("PythonEnv", isDirectory: true)
    }
}

public struct ModelRouter {
    public static func classifier(
        for settings: AppSettings,
        builtInClient: VisionClassifying? = nil
    ) -> VisionClassifying {
        let selection = settings.modelSelection

        switch selection.provider {
        case .builtInGemma:
            return builtInClient ?? BuiltInGemmaClient()
        case .oMLX, .lmStudio, .openAICompatible:
            return LocalVisionClient(
                endpoint: selection.endpoint ?? settings.endpoint,
                model: selection.modelID.isEmpty ? settings.model : selection.modelID
            )
        case .cloudOptIn:
            guard selection.cloudClassificationAllowed else {
                return CloudOptInBlockedClassifier()
            }
            return LocalVisionClient(
                endpoint: selection.endpoint ?? settings.endpoint,
                model: selection.modelID.isEmpty ? settings.model : selection.modelID
            )
        }
    }
}

public struct CloudOptInBlockedClassifier: VisionClassifying {
    public init() {}

    public func classify(
        imageData: Data,
        goal: Goal,
        appName: String,
        bundleIdentifier: String?
    ) async -> VisionClassifierResult {
        VisionClassifierResult(
            focusState: .unknown,
            activityCategory: "cloud_blocked",
            confidence: 0,
            evidenceCodes: ["cloud_opt_in_required"],
            nudgeSuggested: false
        )
    }
}
