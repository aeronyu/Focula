import Foundation
import Darwin
import FoculaCore

@MainActor
final class BuiltInRuntimeController {
    private static let pythonRequirementsVersion = "2026-06-05-gemma4-mlx-vlm-0.4.3"
    private static let pythonRequirements = [
        "mlx-vlm==0.4.3",
        "huggingface_hub",
        "pillow"
    ]

    private var sidecarProcess: Process?
    private var runningModelID: String?
    private let port: Int

    init(port: Int = BuiltInRuntimeController.availablePort()) {
        self.port = port
    }

    var endpoint: URL {
        URL(string: "http://127.0.0.1:\(port)/classify")!
    }

    func currentStatus(for descriptor: BuiltInModelDescriptor = BuiltInModelCatalog.defaultModel) -> ModelRuntimeStatus {
        guard descriptor.isInstallable else {
            return ModelRuntimeStatus(
                provider: .builtInGemma,
                modelID: descriptor.id,
                installState: .missing,
                statusMessage: "\(descriptor.displayName) is not supported by the built-in MLX runtime yet.",
                storagePath: nil,
                isVisionCapable: true,
                isUsable: false
            )
        }

        do {
            let modelRoot = try ModelSupportPaths.builtInModelRoot(for: descriptor)
            let pythonRoot = try ModelSupportPaths.pythonEnvironmentRoot()
            let modelReady = FileManager.default.fileExists(atPath: modelRoot.appendingPathComponent("config.json").path)
            let pythonReady = FileManager.default.fileExists(atPath: pythonRoot.appendingPathComponent("bin/python").path)
            let storagePath = modelRoot.path
            let selectedSidecarRunning = sidecarProcess?.isRunning == true && runningModelID == descriptor.id

            if modelReady && pythonReady {
                return ModelRuntimeStatus(
                    provider: .builtInGemma,
                    modelID: descriptor.id,
                    installState: .ready,
                    statusMessage: selectedSidecarRunning
                        ? "\(descriptor.displayName) sidecar running."
                        : "\(descriptor.displayName) installed.",
                    storagePath: storagePath,
                    isVisionCapable: true,
                    isUsable: true
                )
            }

            return ModelRuntimeStatus(
                provider: .builtInGemma,
                modelID: descriptor.id,
                installState: .missing,
                statusMessage: "Install \(descriptor.displayName) before local classification.",
                storagePath: storagePath,
                isVisionCapable: true,
                isUsable: false
            )
        } catch {
            return ModelRuntimeStatus(
                provider: .builtInGemma,
                modelID: descriptor.id,
                installState: .failed,
                statusMessage: "Could not inspect built-in runtime: \(error.localizedDescription)",
                storagePath: nil,
                isVisionCapable: true,
                isUsable: false
            )
        }
    }

    func installDefaultModel() async throws -> ModelRuntimeStatus {
        try await installModel(BuiltInModelCatalog.defaultModel)
    }

    func installModel(_ descriptor: BuiltInModelDescriptor) async throws -> ModelRuntimeStatus {
        guard descriptor.isInstallable else {
            throw BuiltInRuntimeError.unsupportedModelRuntime(descriptor.displayName)
        }
        stop()
        let runtimeRoot = try ModelSupportPaths.builtInRuntimeRoot()
        let pythonRoot = try ModelSupportPaths.pythonEnvironmentRoot()
        let modelRoot = try ModelSupportPaths.builtInModelRoot(for: descriptor)
        let python = pythonRoot.appendingPathComponent("bin/python")

        try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)

        try await ensurePythonEnvironment(pythonRoot: pythonRoot)

        try FileManager.default.createDirectory(at: modelRoot, withIntermediateDirectories: true)
        try await runProcess(
            executable: python,
            arguments: [
                "-c",
                """
                import os
                from huggingface_hub import snapshot_download
                snapshot_download(repo_id=os.environ["FOCULA_MODEL_REPO"], local_dir=os.environ["FOCULA_MODEL_DIR"])
                """
            ],
            environment: [
                "FOCULA_MODEL_REPO": descriptor.repository,
                "FOCULA_MODEL_DIR": modelRoot.path
            ]
        )

        return currentStatus(for: descriptor)
    }

    func deleteDefaultModel() throws -> ModelRuntimeStatus {
        try deleteModel(BuiltInModelCatalog.defaultModel)
    }

    func deleteModel(_ descriptor: BuiltInModelDescriptor) throws -> ModelRuntimeStatus {
        try deleteModelFolders(paths: [ModelSupportPaths.builtInModelRoot(for: descriptor).path])
        return currentStatus(for: descriptor)
    }

    func deleteModelFolders(paths: [String]) throws {
        stop()
        let modelsRoot = try ModelSupportPaths.builtInModelsRoot().standardizedFileURL.path
        let safeRootPrefix = modelsRoot.hasSuffix("/") ? modelsRoot : "\(modelsRoot)/"

        for path in Set(paths) {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard url.path.hasPrefix(safeRootPrefix) else {
                throw BuiltInRuntimeError.unsafeModelDeletePath(path)
            }
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func availablePort() -> Int {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else { return 8765 }
        defer { close(socketDescriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(0).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(socketDescriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { return 8765 }

        var boundAddress = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getsockname(socketDescriptor, socketAddress, &length)
            }
        }
        guard nameResult == 0 else { return 8765 }

        return Int(UInt16(bigEndian: boundAddress.sin_port))
    }

    func ensureRunning(model descriptor: BuiltInModelDescriptor = BuiltInModelCatalog.defaultModel) async throws {
        guard descriptor.isInstallable else {
            throw BuiltInRuntimeError.unsupportedModelRuntime(descriptor.displayName)
        }

        if sidecarProcess?.isRunning == true && runningModelID == descriptor.id {
            return
        }
        if sidecarProcess?.isRunning == true {
            stop()
        }

        let status = currentStatus(for: descriptor)
        guard status.installState == .ready else {
            throw BuiltInRuntimeError.notInstalled
        }

        let pythonRoot = try ModelSupportPaths.pythonEnvironmentRoot()
        let python = pythonRoot.appendingPathComponent("bin/python")
        try await ensurePythonEnvironment(pythonRoot: pythonRoot)
        let modelRoot = try ModelSupportPaths.builtInModelRoot(for: descriptor)
        guard let script = Bundle.module.url(
            forResource: "builtin_gemma_sidecar",
            withExtension: "py",
            subdirectory: "Runtime"
        ) else {
            throw BuiltInRuntimeError.missingSidecarScript
        }

        let process = Process()
        process.executableURL = python
        process.arguments = [
            script.path,
            "--model-path", modelRoot.path,
            "--port", "\(port)"
        ]
        process.environment = ProcessInfo.processInfo.environment.merging(["PYTHONUNBUFFERED": "1"]) { _, new in new }
        try process.run()
        sidecarProcess = process
        runningModelID = descriptor.id

        for _ in 0..<10 {
            if !process.isRunning {
                sidecarProcess = nil
                runningModelID = nil
                throw BuiltInRuntimeError.processFailed("sidecar exited before it became healthy")
            }
            if await healthCheck() {
                return
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        throw BuiltInRuntimeError.processFailed("sidecar did not answer /health")
    }

    private func ensurePythonEnvironment(pythonRoot: URL) async throws {
        let python = pythonRoot.appendingPathComponent("bin/python")
        if FileManager.default.fileExists(atPath: python.path),
           try await !pythonMeetsMinimumVersion(python) {
            try FileManager.default.removeItem(at: pythonRoot)
        }

        if !FileManager.default.fileExists(atPath: python.path) {
            try await createPythonEnvironment(at: pythonRoot)
        }

        let marker = pythonRoot.appendingPathComponent(".focula-requirements-\(Self.pythonRequirementsVersion)")
        if FileManager.default.fileExists(atPath: marker.path) {
            return
        }

        try await installPythonRequirements(python: python)
        try Self.pythonRequirementsVersion.write(to: marker, atomically: true, encoding: .utf8)
    }

    private func createPythonEnvironment(at pythonRoot: URL) async throws {
        if let uv = Self.firstExecutable(named: "uv") {
            try await runProcess(
                executable: uv,
                arguments: ["venv", "--python", "3.11", pythonRoot.path],
                environment: [:]
            )
            return
        }

        guard let python = try await Self.firstPythonExecutableAtLeast310() else {
            throw BuiltInRuntimeError.missingPython310
        }
        try await runProcess(
            executable: python,
            arguments: ["-m", "venv", pythonRoot.path],
            environment: [:]
        )
    }

    private func installPythonRequirements(python: URL) async throws {
        if let uv = Self.firstExecutable(named: "uv") {
            try await runProcess(
                executable: uv,
                arguments: ["pip", "install", "--python", python.path] + Self.pythonRequirements,
                environment: [:]
            )
            return
        }

        try await runProcess(
            executable: python,
            arguments: ["-m", "pip", "install", "--upgrade", "pip"],
            environment: [:]
        )
        try await runProcess(
            executable: python,
            arguments: ["-m", "pip", "install", "--upgrade"] + Self.pythonRequirements,
            environment: [:]
        )
    }

    private func pythonMeetsMinimumVersion(_ python: URL) async throws -> Bool {
        let output = try await Self.runProcessCapturingOutput(
            executable: python,
            arguments: [
                "-c",
                "import sys; print('1' if sys.version_info >= (3, 10) else '0')"
            ],
            environment: [:]
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    private static func firstPythonExecutableAtLeast310() async throws -> URL? {
        for candidate in pythonCandidates() where FileManager.default.isExecutableFile(atPath: candidate.path) {
            let output = try await runProcessCapturingOutput(
                executable: candidate,
                arguments: [
                    "-c",
                    "import sys; print('1' if sys.version_info >= (3, 10) else '0')"
                ],
                environment: [:]
            )
            if output.trimmingCharacters(in: .whitespacesAndNewlines) == "1" {
                return candidate
            }
        }
        return nil
    }

    private static func firstExecutable(named name: String) -> URL? {
        executableCandidates(named: name).first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    private static func executableCandidates(named name: String) -> [URL] {
        let pathCandidates = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent(name) }
        return pathCandidates + [
            URL(fileURLWithPath: "/opt/homebrew/bin").appendingPathComponent(name),
            URL(fileURLWithPath: "/usr/local/bin").appendingPathComponent(name),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin")
                .appendingPathComponent(name)
        ]
    }

    private static func pythonCandidates() -> [URL] {
        [
            "python3.13",
            "python3.12",
            "python3.11",
            "python3.10",
            "python3"
        ].flatMap(executableCandidates(named:))
    }

    func stop() {
        if sidecarProcess?.isRunning == true {
            sidecarProcess?.terminate()
        }
        sidecarProcess = nil
        runningModelID = nil
    }

    private func runProcess(
        executable: URL,
        arguments: [String],
        environment: [String: String]
    ) async throws {
        _ = try await Self.runProcessCapturingOutput(
            executable: executable,
            arguments: arguments,
            environment: environment
        )
    }

    private static func runProcessCapturingOutput(
        executable: URL,
        arguments: [String],
        environment: [String: String]
    ) async throws -> String {
        try await Task.detached {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                throw BuiltInRuntimeError.processFailed(output.isEmpty ? "no process output" : output)
            }
            return output
        }.value
    }

    private func healthCheck() async -> Bool {
        do {
            let url = URL(string: "http://127.0.0.1:\(port)/health")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 1
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }
}

enum BuiltInRuntimeError: LocalizedError {
    case notInstalled
    case unsupportedModelRuntime(String)
    case missingPython310
    case missingSidecarScript
    case processFailed(String)
    case unsafeModelDeletePath(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "Built-in Gemma is not installed."
        case .unsupportedModelRuntime(let modelName):
            "\(modelName) is not supported by the built-in MLX runtime yet."
        case .missingPython310:
            "Built-in Gemma requires Python 3.10 or newer to install mlx-vlm 0.4.3."
        case .missingSidecarScript:
            "Built-in sidecar script is missing from the app bundle."
        case .processFailed(let output):
            "Built-in runtime command failed: \(output)"
        case .unsafeModelDeletePath(let path):
            "Refusing to delete a path outside Focula model storage: \(path)"
        }
    }
}
