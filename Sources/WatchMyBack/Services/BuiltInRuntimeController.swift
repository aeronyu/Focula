import Foundation
import WatchMyBackCore

@MainActor
final class BuiltInRuntimeController {
    private var sidecarProcess: Process?
    private let port = 8765

    var endpoint: URL {
        URL(string: "http://127.0.0.1:\(port)/classify")!
    }

    func currentStatus() -> ModelRuntimeStatus {
        do {
            let modelRoot = try ModelSupportPaths.builtInModelRoot()
            let pythonRoot = try ModelSupportPaths.pythonEnvironmentRoot()
            let modelReady = FileManager.default.fileExists(atPath: modelRoot.appendingPathComponent("config.json").path)
            let pythonReady = FileManager.default.fileExists(atPath: pythonRoot.appendingPathComponent("bin/python").path)
            let storagePath = modelRoot.path

            if modelReady && pythonReady {
                return ModelRuntimeStatus(
                    provider: .builtInGemma,
                    modelID: BuiltInModelCatalog.gemma4E2B.id,
                    installState: .ready,
                    statusMessage: sidecarProcess?.isRunning == true ? "Built-in Gemma sidecar running." : "Built-in Gemma installed.",
                    storagePath: storagePath,
                    isVisionCapable: true,
                    isUsable: true
                )
            }

            return ModelRuntimeStatus(
                provider: .builtInGemma,
                modelID: BuiltInModelCatalog.gemma4E2B.id,
                installState: .missing,
                statusMessage: "Install built-in Gemma before local classification.",
                storagePath: storagePath,
                isVisionCapable: true,
                isUsable: true
            )
        } catch {
            return ModelRuntimeStatus(
                provider: .builtInGemma,
                modelID: BuiltInModelCatalog.gemma4E2B.id,
                installState: .failed,
                statusMessage: "Could not inspect built-in runtime: \(error.localizedDescription)",
                storagePath: nil,
                isVisionCapable: true,
                isUsable: false
            )
        }
    }

    func installDefaultModel() async throws -> ModelRuntimeStatus {
        let runtimeRoot = try ModelSupportPaths.builtInRuntimeRoot()
        let pythonRoot = try ModelSupportPaths.pythonEnvironmentRoot()
        let modelRoot = try ModelSupportPaths.builtInModelRoot()
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
                "WMB_MODEL_REPO": BuiltInModelCatalog.gemma4E2B.repository,
                "WMB_MODEL_DIR": modelRoot.path
            ]
        )

        return currentStatus()
    }

    func deleteDefaultModel() throws -> ModelRuntimeStatus {
        stop()
        let modelRoot = try ModelSupportPaths.builtInModelRoot()
        if FileManager.default.fileExists(atPath: modelRoot.path) {
            try FileManager.default.removeItem(at: modelRoot)
        }
        return currentStatus()
    }

    func ensureRunning() async throws {
        if sidecarProcess?.isRunning == true {
            return
        }

        let status = currentStatus()
        guard status.installState == .ready else {
            throw BuiltInRuntimeError.notInstalled
        }

        let pythonRoot = try ModelSupportPaths.pythonEnvironmentRoot()
        let python = pythonRoot.appendingPathComponent("bin/python")
        let modelRoot = try ModelSupportPaths.builtInModelRoot()
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

        for _ in 0..<10 {
            if !process.isRunning {
                sidecarProcess = nil
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

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "Built-in Gemma is not installed."
        case .missingSidecarScript:
            "Built-in sidecar script is missing from the app bundle."
        case .processFailed(let output):
            "Built-in runtime command failed: \(output)"
        }
    }
}
