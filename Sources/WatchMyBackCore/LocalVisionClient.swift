import Foundation

public struct VisionClassifierResult: Codable, Equatable, Sendable {
    public var focusState: FocusState
    public var activityCategory: String
    public var confidence: Double
    public var evidenceCodes: [String]
    public var nudgeSuggested: Bool

    public init(
        focusState: FocusState,
        activityCategory: String,
        confidence: Double,
        evidenceCodes: [String],
        nudgeSuggested: Bool
    ) {
        self.focusState = focusState
        self.activityCategory = activityCategory
        self.confidence = confidence
        self.evidenceCodes = evidenceCodes
        self.nudgeSuggested = nudgeSuggested
    }

    public static func fallback() -> VisionClassifierResult {
        VisionClassifierResult(
            focusState: .unknown,
            activityCategory: "unknown",
            confidence: 0,
            evidenceCodes: ["classifier_unavailable"],
            nudgeSuggested: false
        )
    }
}

public protocol VisionClassifying {
    func classify(
        imageData: Data,
        goal: Goal,
        appName: String,
        bundleIdentifier: String?
    ) async -> VisionClassifierResult
}

public final class LocalVisionClient: VisionClassifying {
    private let endpoint: URL
    private let model: String
    private let session: URLSession

    public init(
        endpoint: URL = URL(string: "http://127.0.0.1:1234/v1/chat/completions")!,
        model: String = "local-vision",
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.model = model
        self.session = session
    }

    public func classify(
        imageData: Data,
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
                goal: goal,
                appName: appName,
                bundleIdentifier: bundleIdentifier
            )

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else {
                return .fallback()
            }

            return (try? Self.parseChatCompletionResponse(data)) ?? .fallback()
        } catch {
            return .fallback()
        }
    }

    private func makeRequestBody(
        imageData: Data,
        goal: Goal,
        appName: String,
        bundleIdentifier: String?
    ) throws -> Data {
        let prompt = """
        Classify this Mac activity for the user's active goal.
        Return strict JSON only. Schema:
        {"focusState":"on_goal|maybe|off_goal|unknown","activityCategory":"short_snake_case","confidence":0.0,"evidenceCodes":["short_code"],"nudgeSuggested":false}

        Goal: \(goal.title)
        Description: \(goal.description)
        Allowed apps: \(goal.allowedApps.joined(separator: ", "))
        Blocked apps: \(goal.blockedApps.joined(separator: ", "))
        On-goal examples: \(goal.onGoalExamples.joined(separator: " | "))
        Off-goal examples: \(goal.offGoalExamples.joined(separator: " | "))
        Current app: \(appName)
        Bundle id: \(bundleIdentifier ?? "unknown")
        Do not quote or store visible text. Use evidence codes only.
        """

        let body: [String: Any] = [
            "model": model,
            "temperature": 0,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(imageData.base64EncodedString())"
                            ]
                        ]
                    ]
                ]
            ]
        ]

        return try JSONSerialization.data(withJSONObject: body)
    }

    public static func parseChatCompletionResponse(_ data: Data) throws -> VisionClassifierResult {
        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = response.choices.first?.message.content else {
            throw VisionParseError.missingContent
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{", trimmed.last == "}" else {
            throw VisionParseError.nonStrictJSON
        }

        guard let contentData = trimmed.data(using: .utf8) else {
            throw VisionParseError.invalidUTF8
        }

        return try JSONDecoder().decode(VisionClassifierResult.self, from: contentData)
    }
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }

        let message: Message
    }

    let choices: [Choice]
}

public enum VisionParseError: Error, Equatable {
    case missingContent
    case nonStrictJSON
    case invalidUTF8
}
