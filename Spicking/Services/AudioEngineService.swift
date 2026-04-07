import AVFoundation
import Foundation
import QuartzCore

@MainActor
final class AudioEngineService {
    var onAudioPCMData: ((Data) -> Void)?
    var onSpeechDetected: (() -> Void)?

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
    private let speechThreshold: Float = 0.010
    private let speechDetectionCooldown: CFTimeInterval = 0.35

    func start() async throws {
        try configureAudioSession()
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
        }

        let durationMilliseconds = Double(frameCount) / playbackFormat.sampleRate * 1_000
        scheduledPlaybackMilliseconds += durationMilliseconds

        playerNode.scheduleBuffer(buffer, completionHandler: nil)
        if !playerNode.isPlaying {
            playerNode.play()
            currentPlaybackStartedAt = CACurrentMediaTime()
        }
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

        return RealtimePlaybackSnapshot(itemID: itemID, playedMilliseconds: playedMilliseconds)
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
        try session.setMode(.voiceChat)
        try session.setPreferredSampleRate(24_000)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func configureOutput() throws {
        if outputEngine.attachedNodes.contains(playerNode) == false {
            outputEngine.attach(playerNode)
            outputEngine.connect(playerNode, to: outputEngine.mainMixerNode, format: playbackFormat)
        }
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
        detectSpeech(in: buffer)

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
        if rms > speechThreshold, now - lastSpeechDetectedAt > speechDetectionCooldown {
            lastSpeechDetectedAt = now
            Task { @MainActor [weak self] in
                self?.onSpeechDetected?()
            }
        }
    }
}
