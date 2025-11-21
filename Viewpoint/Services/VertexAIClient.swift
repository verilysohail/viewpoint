import Foundation

class VertexAIClient {
    private let projectID: String
    private let region: String
    private let model: AIModel

    init(projectID: String, region: String, model: AIModel) {
        self.projectID = projectID
        self.region = region
        self.model = model
    }

    // Get access token from gcloud credentials file
    private func getAccessToken() -> String? {
        // Read the Application Default Credentials file directly
        // Get the actual user's home directory (not sandboxed)
        // The sandboxed HOME points to the container, so we need to go up several levels
        let sandboxedHome = FileManager.default.homeDirectoryForCurrentUser.path
        Logger.shared.info("Sandboxed home: \(sandboxedHome)")

        // Extract username from sandboxed path: /Users/username/Library/Containers/...
        // We'll construct the real home directory from the username
        let username = NSUserName()
        let actualHomeDir = "/Users/\(username)"

        Logger.shared.info("Using actual HOME directory: \(actualHomeDir)")

        let credentialsPath = URL(fileURLWithPath: actualHomeDir)
            .appendingPathComponent(".config")
            .appendingPathComponent("gcloud")
            .appendingPathComponent("application_default_credentials.json")

        Logger.shared.info("Looking for credentials at: \(credentialsPath.path)")

        guard FileManager.default.fileExists(atPath: credentialsPath.path) else {
            Logger.shared.error("Application default credentials not found. Run: gcloud auth application-default login")
            return nil
        }

        do {
            let data = try Data(contentsOf: credentialsPath)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                Logger.shared.error("Invalid credentials file format")
                return nil
            }

            // Check if we have a refresh token to exchange for an access token
            guard let refreshToken = json["refresh_token"] as? String,
                  let clientId = json["client_id"] as? String,
                  let clientSecret = json["client_secret"] as? String else {
                Logger.shared.error("Missing required fields in credentials file")
                return nil
            }

            // Exchange refresh token for access token via OAuth2
            return try exchangeRefreshToken(refreshToken: refreshToken, clientId: clientId, clientSecret: clientSecret)

        } catch {
            Logger.shared.error("Failed to read credentials: \(error)")
            return nil
        }
    }

    private func exchangeRefreshToken(refreshToken: String, clientId: String, clientSecret: String) throws -> String? {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]

        let bodyString = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        let semaphore = DispatchSemaphore(value: 0)
        var accessToken: String?
        var requestError: Error?

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            if let error = error {
                requestError = error
                Logger.shared.error("Token exchange failed: \(error)")
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["access_token"] as? String else {
                Logger.shared.error("Invalid token response")
                return
            }

            accessToken = token
            Logger.shared.info("Successfully obtained access token (length: \(token.count))")
        }

        task.resume()
        semaphore.wait()

        if let error = requestError {
            throw error
        }

        return accessToken
    }

    // MARK: - Streaming Response

    func streamCompletion(
        messages: [ChatMessage],
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (Result<TokenUsage, Error>) -> Void
    ) {
        Task {
            do {
                let endpoint = buildEndpoint()
                let request = try buildRequest(endpoint: endpoint, messages: messages)

                let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    Logger.shared.error("Response is not HTTPURLResponse")
                    throw VertexAIError.invalidResponse
                }

                Logger.shared.info("Streaming response status: \(httpResponse.statusCode)")

                guard httpResponse.statusCode == 200 else {
                    Logger.shared.error("HTTP error: \(httpResponse.statusCode)")
                    throw VertexAIError.httpError(httpResponse.statusCode)
                }

                // Accumulate all response data
                var responseData = Data()
                for try await byte in asyncBytes {
                    responseData.append(byte)
                }

                Logger.shared.info("Received \(responseData.count) bytes total")

                // Parse as JSON array
                guard let jsonArray = try? JSONSerialization.jsonObject(with: responseData) as? [[String: Any]] else {
                    Logger.shared.error("Failed to parse response as JSON array")
                    throw VertexAIError.invalidResponse
                }

                Logger.shared.info("Parsed JSON array with \(jsonArray.count) chunks")

                var inputTokens = 0
                var outputTokens = 0

                // Process each chunk in the array
                for (index, chunk) in jsonArray.enumerated() {
                    // Log the full chunk structure for debugging
                    Logger.shared.info("Chunk \(index + 1) keys: \(chunk.keys.joined(separator: ", "))")

                    // Check for errors in response
                    if let error = chunk["error"] as? [String: Any] {
                        Logger.shared.error("Vertex AI returned error: \(error)")
                        throw VertexAIError.invalidResponse
                    }

                    // Extract text from this chunk
                    if let candidates = chunk["candidates"] as? [[String: Any]] {
                        Logger.shared.info("Found \(candidates.count) candidates")

                        let firstCandidate = candidates.first
                        Logger.shared.info("First candidate keys: \(firstCandidate?.keys.joined(separator: ", ") ?? "none")")

                        // Check finish reason for blocked/filtered responses
                        if let finishReason = firstCandidate?["finishReason"] as? String {
                            Logger.shared.info("Finish reason: \(finishReason)")
                            if finishReason != "STOP" {
                                Logger.shared.warning("Response may be incomplete. Finish reason: \(finishReason)")
                            }
                        }

                        // Check for safety ratings
                        if let safetyRatings = firstCandidate?["safetyRatings"] as? [[String: Any]] {
                            Logger.shared.info("Safety ratings present: \(safetyRatings.count) ratings")
                        }

                        if let content = firstCandidate?["content"] as? [String: Any] {
                            Logger.shared.info("Content keys: \(content.keys.joined(separator: ", "))")
                            if let parts = content["parts"] as? [[String: Any]] {
                                Logger.shared.info("Found \(parts.count) parts")
                                if let text = parts.first?["text"] as? String {
                                    Logger.shared.info("Chunk \(index + 1): extracted text (\(text.count) chars)")
                                    await MainActor.run {
                                        onChunk(text)
                                    }
                                } else {
                                    Logger.shared.warning("No 'text' field in first part. Part keys: \(parts.first?.keys.joined(separator: ", ") ?? "none")")
                                }
                            } else {
                                Logger.shared.warning("'parts' is not an array or missing. Content: \(content)")
                            }
                        } else {
                            Logger.shared.warning("'content' is not a dict or missing from first candidate")
                        }
                    } else {
                        Logger.shared.warning("'candidates' is not an array or missing")
                    }

                    // Extract usage metadata (use the last one which has complete counts)
                    if let usage = chunk["usageMetadata"] as? [String: Any] {
                        inputTokens = usage["promptTokenCount"] as? Int ?? inputTokens
                        outputTokens = usage["candidatesTokenCount"] as? Int ?? outputTokens
                    }
                }

                Logger.shared.info("Streaming complete. Processed \(jsonArray.count) chunks")

                let usage = TokenUsage(inputTokens: inputTokens, outputTokens: outputTokens)
                await MainActor.run {
                    onComplete(.success(usage))
                }

            } catch {
                Logger.shared.error("Vertex AI streaming error: \(error)")
                Logger.shared.error("Error details: \(error.localizedDescription)")
                await MainActor.run {
                    onComplete(.failure(error))
                }
            }
        }
    }

    // MARK: - Request Building

    private func buildEndpoint() -> String {
        if model.usesGlobalRegion {
            // Global models use the non-regional endpoint
            return "https://aiplatform.googleapis.com/v1/projects/\(projectID)/locations/global/publishers/google/models/\(model.rawValue):streamGenerateContent"
        } else {
            // Regional models use the regional endpoint
            return "https://\(region)-aiplatform.googleapis.com/v1/projects/\(projectID)/locations/\(region)/publishers/google/models/\(model.rawValue):streamGenerateContent"
        }
    }

    private func buildRequest(endpoint: String, messages: [ChatMessage]) throws -> URLRequest {
        guard let url = URL(string: endpoint) else {
            throw VertexAIError.invalidURL
        }

        // Get access token from gcloud
        guard let accessToken = getAccessToken() else {
            throw VertexAIError.authenticationFailed
        }

        Logger.shared.info("Building request to: \(endpoint)")
        Logger.shared.info("Using access token starting with: \(String(accessToken.prefix(20)))...")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        // Gemini request format - convert system message to user message
        var geminiMessages: [[String: Any]] = []

        for msg in messages {
            if msg.role == .system {
                // Add system message as a user message
                geminiMessages.append([
                    "role": "user",
                    "parts": [["text": msg.content]]
                ])
            } else {
                geminiMessages.append([
                    "role": msg.role == .user ? "user" : "model",
                    "parts": [["text": msg.content]]
                ])
            }
        }

        let body: [String: Any] = [
            "contents": geminiMessages,
            "generationConfig": [
                "temperature": 0.7,
                "topP": 0.95,
                "topK": 40,
                "maxOutputTokens": 2048
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}

// MARK: - Supporting Types

struct ChatMessage {
    enum Role {
        case system
        case user
        case assistant
    }

    let role: Role
    let content: String
}

struct TokenUsage {
    let inputTokens: Int
    let outputTokens: Int

    func estimatedCost(model: AIModel) -> Double {
        let inputCost = Double(inputTokens) / 1_000_000.0 * model.inputCostPer1M
        let outputCost = Double(outputTokens) / 1_000_000.0 * model.outputCostPer1M
        return inputCost + outputCost
    }
}

enum VertexAIError: Error, LocalizedError {
    case invalidURL
    case httpError(Int)
    case invalidResponse
    case missingCredentials
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Vertex AI endpoint URL"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .invalidResponse:
            return "Invalid response from Vertex AI"
        case .missingCredentials:
            return "Missing Vertex AI credentials. Please configure in Settings → AI."
        case .authenticationFailed:
            return "Failed to authenticate with gcloud. Please run 'gcloud auth application-default login' in Terminal."
        }
    }
}
