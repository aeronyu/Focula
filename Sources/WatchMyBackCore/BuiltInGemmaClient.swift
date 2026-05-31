import Foundation

public final class BuiltInGemmaClient: VisionClassifying {
    private let endpoint: URL
    private let session: URLSession

    public init(
        endpoint: URL = URL(string: "http://127.0.0.1:8765/classify")!,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.session = session
    }

    public func classify(
        imageData: Data,
        contextImageData: [Data] = [],
        goal: Goal,
        appName: String,
        bundleIdentifier: String?
    ) async -> VisionClassifierResult {
        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try makeRequestBody(
                imageData: imageData,
                contextImageData: contextImageData,
                goal: goal,
                appName: appName,
                bundleIdentifier: bundleIdentifier
            )

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else {
                return Self.runtimeUnavailableFallback()
            }

            return (try? Self.parseSidecarResponse(data)) ?? .fallback()
        } catch {
            return Self.runtimeUnavailableFallback()
        }
    }

    private func makeRequestBody(
        imageData: Data,
        contextImageData: [Data],
        goal: Goal,
        appName: String,
        bundleIdentifier: String?
    ) throws -> Data {
        let payload = BuiltInSidecarRequest(
            imageBase64: imageData.base64EncodedString(),
            contextImageBase64: contextImageData.map { $0.base64EncodedString() },
            goal: GoalPayload(goal),
            appName: appName,
            bundleIdentifier: bundleIdentifier
        )
        return try JSONEncoder().encode(payload)
    }

    public static func parseSidecarResponse(_ data: Data) throws -> VisionClassifierResult {
        try JSONDecoder().decode(VisionClassifierResult.self, from: data)
            .sanitizedForActivityLog()
    }

    public static func notReadyFallback() -> VisionClassifierResult {
        VisionClassifierResult(
            focusState: .unknown,
            activityCategory: "built_in_model_not_ready",
            activitySummary: nil,
            confidence: 0,
            evidenceCodes: ["builtin_gemma_sidecar_unavailable"],
            nudgeSuggested: false
        )
    }

    public static func runtimeUnavailableFallback() -> VisionClassifierResult {
        VisionClassifierResult(
            focusState: .unknown,
            activityCategory: "built_in_model_runtime_error",
            activitySummary: nil,
            confidence: 0,
            evidenceCodes: ["builtin_gemma_sidecar_unavailable"],
            nudgeSuggested: false
        )
    }
}

private struct BuiltInSidecarRequest: Encodable {
    let imageBase64: String
    let contextImageBase64: [String]
    let goal: GoalPayload
    let appName: String
    let bundleIdentifier: String?
}

private struct GoalPayload: Encodable {
    let title: String
    let description: String
    let allowedApps: [String]
    let blockedApps: [String]
    let onGoalExamples: [String]
    let offGoalExamples: [String]

    init(_ goal: Goal) {
        title = goal.title
        description = goal.description
        allowedApps = goal.allowedApps
        blockedApps = goal.blockedApps
        onGoalExamples = goal.onGoalExamples
        offGoalExamples = goal.offGoalExamples
    }
}
