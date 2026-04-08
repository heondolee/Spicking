import Foundation

@MainActor
final class RealtimeSessionService {
    var onConnectionStateChanged: ((RealtimeConnectionState) -> Void)?
    var onUserTranscriptUpdated: ((String, String, Bool) -> Void)?
    var onAssistantTranscriptUpdated: ((String, String, Bool) -> Void)?
    var onAssistantAudioChunk: ((String, String) -> Void)?
    var onAssistantSpeakingChanged: ((Bool) -> Void)?
    var onServerSpeechStarted: (() -> Void)?
    var onError: ((String) -> Void)?

    private let configuration: AppConfiguration
    private let tokenService: RealtimeTokenService
    private let urlSession: URLSession
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveLoopTask: Task<Void, Never>?
    private var awaitingTextResponseContinuation: CheckedContinuation<String, Error>?
    private var textResponseBuffer = ""
    private var assistantSpeaking = false {
        didSet {
            if assistantSpeaking != oldValue {
                onAssistantSpeakingChanged?(assistantSpeaking)
            }
        }
    }

    init(configuration: AppConfiguration, urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.tokenService = RealtimeTokenService(configuration: configuration)
        self.urlSession = urlSession
    }

    func connect(topic: String) async throws {
        onConnectionStateChanged?(.connecting)
        let token = try await tokenService.fetchToken()

        guard var components = URLComponents(string: "wss://api.openai.com/v1/realtime") else {
            throw URLError(.badURL)
        }
        components.queryItems = [URLQueryItem(name: "model", value: token.model)]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("Bearer \(token.ephemeralKey)", forHTTPHeaderField: "Authorization")

        let task = urlSession.webSocketTask(with: request)
        webSocketTask = task
        task.resume()
        startReceiveLoop()

        try await send([
            "type": "session.update",
            "session": [
                "type": "realtime",
                "model": token.model,
                "instructions": PromptLibrary.sessionInstructions(topic: topic),
                "output_modalities": ["audio"],
                "audio": [
                    "input": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": 24_000,
                        ],
                        "transcription": [
                            "model": "gpt-4o-mini-transcribe",
                            "language": "en",
                        ],
                        "noise_reduction": [
                            "type": "near_field",
                        ],
                        "turn_detection": [
                            "type": "server_vad",
                            "threshold": 0.72,
                            "prefix_padding_ms": 250,
                            "silence_duration_ms": 850,
                            "interrupt_response": true,
                            "create_response": false,
                        ],
                    ],
                    "output": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": 24_000,
                        ],
                        "voice": token.voice,
                    ],
                ],
            ],
        ])

        onConnectionStateChanged?(.connected)
        try await requestKickoff(topic: topic)
    }

    func disconnect() {
        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        assistantSpeaking = false
        onConnectionStateChanged?(.disconnected)
    }

    func appendInputAudio(_ data: Data) {
        let payload = [
            "type": "input_audio_buffer.append",
            "audio": data.base64EncodedString(),
        ]

        Task {
            do {
                try await send(payload)
            } catch {
                onError?(error.localizedDescription)
            }
        }
    }

    func interruptActiveResponse(playbackSnapshot: RealtimePlaybackSnapshot?) async {
        do {
            try await send(["type": "response.cancel"])
            if let snapshot = playbackSnapshot {
                try await send([
                    "type": "conversation.item.truncate",
                    "item_id": snapshot.itemID,
                    "content_index": 0,
                    "audio_end_ms": snapshot.playedMilliseconds,
                ])
            }
            assistantSpeaking = false
        } catch {
            onError?(error.localizedDescription)
        }
    }

    func requestReviewJSON() async throws -> String {
        textResponseBuffer = ""

        return try await withCheckedThrowingContinuation { continuation in
            awaitingTextResponseContinuation = continuation

            Task {
                do {
                    try await send([
                        "type": "response.create",
                        "response": [
                            "output_modalities": ["text"],
                            "instructions": PromptLibrary.reviewInstructions,
                        ],
                    ])
                } catch {
                    awaitingTextResponseContinuation = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func requestKickoff(topic: String) async throws {
        try await send([
            "type": "response.create",
            "response": [
                "instructions": PromptLibrary.kickoffInstructions(topic: topic),
            ],
        ])
    }

    func requestAssistantReply() async throws {
        try await send([
            "type": "response.create",
            "response": [
                "instructions": """
                Continue the live English conversation naturally.
                Speak in English only.
                Respond to the user's latest message, keep it short, and ask exactly one follow-up question.
                """,
            ],
        ])
    }

    private func startReceiveLoop() {
        receiveLoopTask?.cancel()
        receiveLoopTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    guard let message = try await self.webSocketTask?.receive() else {
                        break
                    }
                    switch message {
                    case .string(let text):
                        self.handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleMessage(text)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    if !Task.isCancelled {
                        self.onConnectionStateChanged?(.failed)
                        self.onError?(error.localizedDescription)
                    }
                    break
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = payload["type"] as? String
        else {
            return
        }

        switch type {
        case "session.created", "session.updated":
            onConnectionStateChanged?(.connected)
        case "error":
            if let error = payload["error"] as? [String: Any],
               let message = error["message"] as? String {
                onError?(message)
            } else {
                onError?("Unknown Realtime error")
            }
        case "input_audio_buffer.speech_started":
            onServerSpeechStarted?()
        case "response.output_audio.delta", "response.audio.delta":
            let itemID = (payload["item_id"] as? String) ?? "assistant_audio"
            let delta = (payload["delta"] as? String) ?? ""
            if !delta.isEmpty {
                assistantSpeaking = true
                onAssistantAudioChunk?(itemID, delta)
            }
        case "response.output_audio.done", "response.audio.done":
            assistantSpeaking = false
        case "response.output_audio_transcript.delta", "response.audio_transcript.delta":
            if let itemID = payload["item_id"] as? String,
               let delta = payload["delta"] as? String {
                onAssistantTranscriptUpdated?(itemID, delta, false)
            }
        case "response.output_audio_transcript.done", "response.audio_transcript.done":
            if let itemID = payload["item_id"] as? String,
               let transcript = payload["transcript"] as? String {
                onAssistantTranscriptUpdated?(itemID, transcript, true)
            }
        case "conversation.item.input_audio_transcription.delta":
            if let itemID = payload["item_id"] as? String,
               let delta = payload["delta"] as? String {
                onUserTranscriptUpdated?(itemID, delta, false)
            }
        case "conversation.item.input_audio_transcription.completed":
            if let itemID = payload["item_id"] as? String,
               let transcript = payload["transcript"] as? String {
                onUserTranscriptUpdated?(itemID, transcript, true)
            }
        case "response.output_text.delta":
            if let delta = payload["delta"] as? String {
                textResponseBuffer += delta
            }
        case "response.output_text.done":
            if let text = payload["text"] as? String {
                textResponseBuffer = text
            }
            resolveTextResponseIfNeeded()
        case "response.done":
            resolveTextResponseIfNeeded()
            assistantSpeaking = false
        case "response.cancelled":
            assistantSpeaking = false
        default:
            break
        }
    }

    private func resolveTextResponseIfNeeded() {
        guard let continuation = awaitingTextResponseContinuation else { return }
        awaitingTextResponseContinuation = nil
        continuation.resume(returning: textResponseBuffer)
        textResponseBuffer = ""
    }

    private func send(_ payload: [String: Any]) async throws {
        guard let webSocketTask else {
            throw NSError(domain: "RealtimeSessionService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Realtime session is not connected."])
        }

        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "RealtimeSessionService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not encode Realtime event."])
        }
        try await webSocketTask.send(.string(text))
    }
}

enum PromptLibrary {
    static func sessionInstructions(topic: String) -> String {
        """
        You are a private English speaking coach inside an iPhone speaking app.
        Your job is to help the user speak more naturally and fluently in spoken English.
        Important language rule: always reply in English only.
        Even if the user speaks Korean, asks in Korean, or requests Korean, still answer in English only.
        Never switch to Korean, never explain in Korean, and never give bilingual output during the live conversation.
        Stay on the selected topic: \(topic).
        Keep spoken replies short, warm, natural, and easy to answer.
        Ask one question at a time.
        If the user struggles, simplify your English instead of switching languages.
        If the user's sentence sounds unnatural, continue the conversation naturally and model better English in your own response instead of giving long grammar lectures.
        """
    }

    static func kickoffInstructions(topic: String) -> String {
        """
        Start a friendly English conversation practice session about "\(topic)".
        Speak in English only.
        Say hello briefly, mention the topic, and ask exactly one open-ended question to get the user talking.
        """
    }

    static let reviewInstructions = """
    Analyze the user's English in the conversation so far.
    Return JSON only, with no markdown and no extra commentary.
    Use this exact schema:
    {
      "suggestions": [
        {
          "originalText": "string",
          "minimalRewrite": "string",
          "naturalRewrite": "string",
          "reasonKo": "string",
          "intentKo": "string"
        }
      ]
    }
    Rules:
    - Return 3 to 5 suggestions only.
    - Focus only on user sentences that are worth improving.
    - "minimalRewrite" should stay close to the user's wording.
    - "naturalRewrite" should sound natural but still realistic for an English learner.
    - "naturalRewrite" must be meaningfully different from "originalText". Do not repeat the original sentence with only punctuation, capitalization, or tiny edits.
    - If the original sentence is already natural enough, skip it and choose another user sentence instead.
    - "intentKo" must be a natural Korean interpretation of what the user meant, written like a smooth translation rather than a label.
    - "reasonKo" must be in Korean and explain concretely why the new sentence sounds smoother, clearer, or more natural in conversation.
    """
}
