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
                let configured = selected.provider == .openAICompatible
                return ModelRuntimeStatus(
                    provider: .openAICompatible,
                    modelID: configured ? selected.modelID : ModelProvider.openAICompatible.defaultModelID,
                    installState: configured ? .ready : .missing,
                    statusMessage: configured ? "Manual endpoint configured." : "Select and configure a manual endpoint.",
                    storagePath: nil,
                    isVisionCapable: true,
                    isUsable: configured
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

public struct BuiltInModelFolder: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public var path: String
    public var folderName: String
    public var displayName: String
    public var modelID: String?
    public var isLegacy: Bool

    public init(
        path: String,
        folderName: String,
        displayName: String,
        modelID: String?,
        isLegacy: Bool
    ) {
        self.path = path
        self.folderName = folderName
        self.displayName = displayName
        self.modelID = modelID
        self.isLegacy = isLegacy
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

    public static func builtInModelsRoot(fileManager: FileManager = .default) throws -> URL {
        let folder = try builtInRuntimeRoot(fileManager: fileManager)
            .appendingPathComponent("Models", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    public static func builtInModelRoot(
        for descriptor: BuiltInModelDescriptor = BuiltInModelCatalog.defaultModel,
        fileManager: FileManager = .default
    ) throws -> URL {
        let folder = try builtInModelRoot(forRepository: descriptor.repository, fileManager: fileManager)
        try fileManager.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        return folder
    }

    public static func builtInModelRoot(
        forRepository repository: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        try builtInModelsRoot(fileManager: fileManager)
            .appendingPathComponent(storageFolderName(for: repository), isDirectory: true)
    }

    public static func storageFolderName(for repository: String) -> String {
        repository
            .replacingOccurrences(of: "/", with: "__")
            .replacingOccurrences(of: ":", with: "_")
    }

    public static func installedBuiltInModelFolders(fileManager: FileManager = .default) throws -> [BuiltInModelFolder] {
        let root = try builtInModelsRoot(fileManager: fileManager)
        guard fileManager.fileExists(atPath: root.path) else { return [] }

        let urls = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return try urls.compactMap { url in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { return nil }
            return builtInModelFolder(for: url)
        }
        .sorted { $0.folderName.localizedCaseInsensitiveCompare($1.folderName) == .orderedAscending }
    }

    public static func builtInModelFolder(for url: URL) -> BuiltInModelFolder {
        let folderName = url.lastPathComponent
        if let descriptor = BuiltInModelCatalog.all.first(where: { storageFolderName(for: $0.repository) == folderName }) {
            return BuiltInModelFolder(
                path: url.path,
                folderName: folderName,
                displayName: descriptor.displayName,
                modelID: descriptor.id,
                isLegacy: false
            )
        }

        if let legacyRepository = BuiltInModelCatalog.legacyDefaultRepositories.first(where: { storageFolderName(for: $0) == folderName }) {
            return BuiltInModelFolder(
                path: url.path,
                folderName: folderName,
                displayName: "Legacy Gemma folder (\(legacyRepository))",
                modelID: BuiltInModelCatalog.defaultModel.id,
                isLegacy: true
            )
        }

        return BuiltInModelFolder(
            path: url.path,
            folderName: folderName,
            displayName: folderName,
            modelID: nil,
            isLegacy: false
        )
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
