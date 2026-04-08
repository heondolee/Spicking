import AVFoundation
import Foundation
import QuartzCore
import Speech

@MainActor
final class AudioEngineService {
    var onAudioPCMData: ((Data) -> Void)?
    var onSpeechDetected: (() -> Void)?
    var onLiveUserTranscription: ((String, Bool) -> Void)?
    var onAssistantPlaybackChanged: ((Bool) -> Void)?
    var onAssistantPlaybackFinished: ((String) -> Void)?
    var inputEnabled = true

    private let inputEngine = AVAudioEngine()
    private let outputEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let targetInputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true)!
    private let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true)!
    private var inputConverter: AVAudioConverter?
    private var lastSpeechDetectedAt: CFTimeInterval = 0
    private var currentAssistantItemID: String?
    private var currentPlaybackStartedAt: CFTimeInterval?
    private var scheduledPlaybackMilliseconds: Double = 0
    private var pendingAssistantBuffers = 0
    private var currentAssistantStreamEnded = false
    private let speechThreshold: Float = 0.010
    private let assistantPlaybackSpeechThreshold: Float = 0.060
    private let speechDetectionCooldown: CFTimeInterval = 0.35
    private let speechRecognitionSilenceTimeout: CFTimeInterval = 1.25
    private let assistantPlaybackGracePeriod: CFTimeInterval = 0.18
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var speechRecognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var speechRecognitionTask: SFSpeechRecognitionTask?
    private var speechRecognitionAuthorized = false
    private var lastRecognitionResult = ""
    private var consecutiveAssistantSpeechDetections = 0
    private var lastAssistantPlaybackEndedAt: CFTimeInterval = 0
    private var speechRecognitionRestartAllowedAt: CFTimeInterval = 0
    private var assistantPlaybackActive = false {
        didSet {
            if assistantPlaybackActive != oldValue {
                onAssistantPlaybackChanged?(assistantPlaybackActive)
            }
        }
    }

    var hasRecentSpeechActivity: Bool {
        CACurrentMediaTime() - lastSpeechDetectedAt <= 1.7
    }

    func start() async throws {
        try configureAudioSession()
        await configureSpeechRecognition()
        try configureOutput()
        try configureInput()
        try inputEngine.start()
        if !outputEngine.isRunning {
            try outputEngine.start()
        }
    }

    func stop() {
        inputEngine.inputNode.removeTap(onBus: 0)
        inputEngine.stop()
        playerNode.stop()
        outputEngine.stop()
        currentAssistantItemID = nil
        currentPlaybackStartedAt = nil
        scheduledPlaybackMilliseconds = 0
        pendingAssistantBuffers = 0
        currentAssistantStreamEnded = false
        assistantPlaybackActive = false
        inputEnabled = true
        stopSpeechRecognition(markFinal: false)
    }

    func enqueueAssistantAudio(base64: String, itemID: String) {
        guard let pcmData = Data(base64Encoded: base64) else { return }
        let bytesPerFrame = Int(playbackFormat.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0 else { return }

        let frameCount = AVAudioFrameCount(pcmData.count / bytesPerFrame)
        guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: frameCount) else {
            return
        }

        buffer.frameLength = frameCount
        pcmData.withUnsafeBytes { rawBuffer in
            guard let source = rawBuffer.baseAddress, let destination = buffer.int16ChannelData?.pointee else { return }
            destination.update(from: source.assumingMemoryBound(to: Int16.self), count: Int(frameCount))
        }

        if currentAssistantItemID != itemID {
            currentAssistantItemID = itemID
            currentPlaybackStartedAt = nil
            scheduledPlaybackMilliseconds = 0
            pendingAssistantBuffers = 0
            currentAssistantStreamEnded = false
        }

        stopSpeechRecognition(markFinal: false)
        speechRecognitionRestartAllowedAt = CACurrentMediaTime() + 0.25

        let durationMilliseconds = Double(frameCount) / playbackFormat.sampleRate * 1_000
        scheduledPlaybackMilliseconds += durationMilliseconds
        pendingAssistantBuffers += 1
        assistantPlaybackActive = true

        playerNode.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleScheduledBufferFinished()
            }
        }
        if !playerNode.isPlaying {
            playerNode.play()
            currentPlaybackStartedAt = CACurrentMediaTime()
        }
    }

    func markAssistantStreamEnded() {
        currentAssistantStreamEnded = true
        finishPlaybackIfPossible()
    }

    func interruptPlayback() -> RealtimePlaybackSnapshot? {
        guard let itemID = currentAssistantItemID else { return nil }

        let now = CACurrentMediaTime()
        let playbackStartedAt = currentPlaybackStartedAt ?? now
        let elapsedMilliseconds = max(0, (now - playbackStartedAt) * 1_000)
        let playedMilliseconds = Int(min(elapsedMilliseconds, scheduledPlaybackMilliseconds))

        playerNode.stop()
        playerNode.reset()
        currentAssistantItemID = nil
        currentPlaybackStartedAt = nil
        scheduledPlaybackMilliseconds = 0
        pendingAssistantBuffers = 0
        currentAssistantStreamEnded = false
        assistantPlaybackActive = false
        lastAssistantPlaybackEndedAt = CACurrentMediaTime()
        speechRecognitionRestartAllowedAt = lastAssistantPlaybackEndedAt + assistantPlaybackGracePeriod

        return RealtimePlaybackSnapshot(itemID: itemID, playedMilliseconds: playedMilliseconds)
    }

    private func handleScheduledBufferFinished() {
        pendingAssistantBuffers = max(0, pendingAssistantBuffers - 1)
        finishPlaybackIfPossible()
    }

    private func finishPlaybackIfPossible() {
        guard currentAssistantStreamEnded, pendingAssistantBuffers == 0 else { return }
        let finishedItemID = currentAssistantItemID
        playerNode.stop()
        playerNode.reset()
        currentAssistantItemID = nil
        currentPlaybackStartedAt = nil
        scheduledPlaybackMilliseconds = 0
        currentAssistantStreamEnded = false
        assistantPlaybackActive = false
        lastAssistantPlaybackEndedAt = CACurrentMediaTime()
        speechRecognitionRestartAllowedAt = lastAssistantPlaybackEndedAt + assistantPlaybackGracePeriod
        if let finishedItemID {
            onAssistantPlaybackFinished?(finishedItemID)
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setMode(.default)
        try session.setPreferredSampleRate(24_000)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func configureOutput() throws {
        if outputEngine.attachedNodes.contains(playerNode) == false {
            outputEngine.attach(playerNode)
            outputEngine.connect(playerNode, to: outputEngine.mainMixerNode, format: playbackFormat)
        }
        playerNode.volume = 1.0
        outputEngine.mainMixerNode.outputVolume = 1.0
        if !outputEngine.isRunning {
            try outputEngine.start()
        }
    }

    private func configureInput() throws {
        let inputNode = inputEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        inputConverter = AVAudioConverter(from: inputFormat, to: targetInputFormat)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { [weak self] buffer, _ in
            self?.handleInputBuffer(buffer, inputFormat: inputFormat)
        }
    }

    private func handleInputBuffer(_ buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) {
        guard inputEnabled else { return }
        let now = CACurrentMediaTime()
        let shouldAcceptUserInput = assistantPlaybackActive == false && now >= speechRecognitionRestartAllowedAt

        if shouldAcceptUserInput {
            detectSpeech(in: buffer)
            appendToSpeechRecognition(buffer)
            finishSpeechRecognitionIfNeeded()
        }

        guard let converter = inputConverter else { return }
        let ratio = targetInputFormat.sampleRate / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up) + 32)
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetInputFormat, frameCapacity: outputCapacity) else {
            return
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        let status = converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
        guard status != .error, error == nil else { return }

        let byteCount = Int(convertedBuffer.frameLength) * Int(targetInputFormat.streamDescription.pointee.mBytesPerFrame)
        guard byteCount > 0, let channelData = convertedBuffer.int16ChannelData?.pointee else { return }

        guard shouldAcceptUserInput else { return }

        let data = Data(bytes: channelData, count: byteCount)
        onAudioPCMData?(data)
    }

    private func detectSpeech(in buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?.pointee else { return }

        let frameCount = Int(buffer.frameLength)
        if frameCount == 0 { return }

        var sum: Float = 0
        for index in 0..<frameCount {
            let sample = channelData[index]
            sum += sample * sample
        }

        let rms = sqrtf(sum / Float(frameCount))
        let now = CACurrentMediaTime()
        if assistantPlaybackActive {
            if now - lastAssistantPlaybackEndedAt < assistantPlaybackGracePeriod {
                return
            }

            if rms > assistantPlaybackSpeechThreshold {
                consecutiveAssistantSpeechDetections += 1
            } else {
                consecutiveAssistantSpeechDetections = 0
            }

            guard consecutiveAssistantSpeechDetections >= 4 else { return }
            consecutiveAssistantSpeechDetections = 0
        } else {
            consecutiveAssistantSpeechDetections = 0
            guard rms > speechThreshold else { return }
        }

        if now - lastSpeechDetectedAt > speechDetectionCooldown {
            lastSpeechDetectedAt = now
            startSpeechRecognitionIfNeeded()
            Task { @MainActor [weak self] in
                self?.onSpeechDetected?()
            }
        }
    }

    private func configureSpeechRecognition() async {
        let authorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        speechRecognitionAuthorized = authorizationStatus == .authorized
    }

    private func startSpeechRecognitionIfNeeded() {
        guard speechRecognitionAuthorized else { return }
        guard speechRecognitionRequest == nil else { return }
        guard let speechRecognizer, speechRecognizer.isAvailable else { return }
        guard assistantPlaybackActive == false else { return }
        guard CACurrentMediaTime() >= speechRecognitionRestartAllowedAt else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = false

        lastRecognitionResult = ""
        speechRecognitionRequest = request
        speechRecognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let self else { return }
            guard let result else { return }

            let transcript = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else { return }

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lastRecognitionResult = transcript
                self.onLiveUserTranscription?(transcript, result.isFinal)
                if result.isFinal {
                    self.stopSpeechRecognition(markFinal: false)
                }
            }
        }
    }

    private func appendToSpeechRecognition(_ buffer: AVAudioPCMBuffer) {
        speechRecognitionRequest?.append(buffer)
    }

    private func finishSpeechRecognitionIfNeeded() {
        guard speechRecognitionRequest != nil else { return }
        let now = CACurrentMediaTime()
        guard now - lastSpeechDetectedAt > speechRecognitionSilenceTimeout else { return }
        stopSpeechRecognition(markFinal: false)
    }

    private func stopSpeechRecognition(markFinal: Bool) {
        if markFinal, !lastRecognitionResult.isEmpty {
            onLiveUserTranscription?(lastRecognitionResult, true)
        }
        speechRecognitionRequest?.endAudio()
        speechRecognitionTask?.cancel()
        speechRecognitionTask = nil
        speechRecognitionRequest = nil
        lastRecognitionResult = ""
    }
}
