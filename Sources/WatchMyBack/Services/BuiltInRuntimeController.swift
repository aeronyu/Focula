import Foundation
import Darwin
import WatchMyBackCore

@MainActor
final class BuiltInRuntimeController {
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
        stop()
        let runtimeRoot = try ModelSupportPaths.builtInRuntimeRoot()
        let pythonRoot = try ModelSupportPaths.pythonEnvironmentRoot()
        let modelRoot = try ModelSupportPaths.builtInModelRoot(for: descriptor)
        let python = pythonRoot.appendingPathComponent("bin/python")

        try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: python.path) {
            try await runProcess(
                executable: URL(fileURLWithPath: "/usr/bin/python3"),
                arguments: ["-m", "venv", pythonRoot.path],
                environment: [:]
            )
            try await runProcess(
                executable: python,
                arguments: ["-m", "pip", "install", "--upgrade", "pip"],
                environment: [:]
            )
            try await runProcess(
                executable: python,
                arguments: ["-m", "pip", "install", "mlx-vlm", "huggingface_hub", "pillow"],
                environment: [:]
            )
        }

        try FileManager.default.createDirectory(at: modelRoot, withIntermediateDirectories: true)
        try await runProcess(
            executable: python,
            arguments: [
                "-c",
                """
                import os
                from huggingface_hub import snapshot_download
                snapshot_download(repo_id=os.environ["WMB_MODEL_REPO"], local_dir=os.environ["WMB_MODEL_DIR"])
                """
            ],
            environment: [
                "WMB_MODEL_REPO": descriptor.repository,
                "WMB_MODEL_DIR": modelRoot.path
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

            guard process.terminationStatus == 0 else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? "no process output"
                throw BuiltInRuntimeError.processFailed(output)
            }
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
    case missingSidecarScript
    case processFailed(String)
    case unsafeModelDeletePath(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "Built-in Gemma is not installed."
        case .missingSidecarScript:
            "Built-in sidecar script is missing from the app bundle."
        case .processFailed(let output):
            "Built-in runtime command failed: \(output)"
        case .unsafeModelDeletePath(let path):
            "Refusing to delete a path outside Watch My Back model storage: \(path)"
        }
    }
}
