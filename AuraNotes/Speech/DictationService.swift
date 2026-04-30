//
//  DictationService.swift
//  AuraNotes
//
//  On-device speech-to-text via the macOS 26 Speech framework
//  (SpeechAnalyzer + SpeechTranscriber). The service owns the
//  audio engine and analyzer lifecycle; consumers receive a stream
//  of (text, isFinal) updates and decide how to render them.
//

@preconcurrency import AVFoundation
import Foundation
import Speech

/// One transcript update. `isFinal == false` means the recognizer
/// may still revise this run of words; `true` means it's committed.
struct DictationUpdate: Sendable {
    let text: String
    let isFinal: Bool
}

enum DictationError: Error, LocalizedError {
    case localeUnsupported
    case modelUnavailable
    case microphoneDenied
    case speechDenied
    case audioEngine(String)

    var errorDescription: String? {
        switch self {
        case .localeUnsupported: return "Dictation isn't available for this language yet."
        case .modelUnavailable:  return "The on-device speech model couldn't be installed."
        case .microphoneDenied:  return "Microphone access is required to dictate. Enable it in System Settings ▸ Privacy & Security ▸ Microphone."
        case .speechDenied:      return "Speech recognition access is required. Enable it in System Settings ▸ Privacy & Security ▸ Speech Recognition."
        case .audioEngine(let m): return "Audio engine error: \(m)"
        }
    }
}

/// Owns the speech pipeline. Single active session at a time.
actor DictationService {
    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var pipeline: AudioPipeline?

    /// Starts a session. Calls `onUpdate` on the main actor for each
    /// volatile or final transcript chunk. Throws on permission/model failure.
    func start(
        locale: Locale = .current,
        onUpdate: @escaping @Sendable @MainActor (DictationUpdate) -> Void
    ) async throws {
        try await stop()

        try await Self.requestSpeechAuthorization()
        try await Self.requestMicrophoneAuthorization()

        let supported = await SpeechTranscriber.supportedLocales
        let chosen = supported.first { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
            ?? supported.first { $0.language.languageCode == locale.language.languageCode }
            ?? Locale(identifier: "en-US")
        guard supported.contains(where: { $0.identifier(.bcp47) == chosen.identifier(.bcp47) }) else {
            throw DictationError.localeUnsupported
        }

        let transcriber = SpeechTranscriber(
            locale: chosen,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        self.transcriber = transcriber

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        guard let bestFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw DictationError.modelUnavailable
        }

        let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputContinuation = inputContinuation
        try await analyzer.start(inputSequence: inputStream)

        self.pipeline = AudioPipeline(targetFormat: bestFormat, continuation: inputContinuation)

        resultsTask = Task { [transcriber] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    let isFinal = result.isFinal
                    await MainActor.run { onUpdate(DictationUpdate(text: text, isFinal: isFinal)) }
                }
            } catch {
                // Stream ended (stop) or recognizer errored — nothing to do.
            }
        }

        try startAudioEngine()
    }

    func stop() async throws {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil

        inputContinuation?.finish()
        inputContinuation = nil

        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        analyzer = nil
        transcriber = nil

        resultsTask?.cancel()
        resultsTask = nil

        pipeline = nil
    }

    // MARK: - Audio engine

    private func startAudioEngine() throws {
        let engine = AVAudioEngine()
        self.engine = engine

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard let pipeline else { throw DictationError.audioEngine("no pipeline") }
        pipeline.prepare(sourceFormat: inputFormat)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            pipeline.feed(buffer)
        }

        do {
            try engine.start()
        } catch {
            throw DictationError.audioEngine(error.localizedDescription)
        }
    }

    // MARK: - Authorization

    private static func requestSpeechAuthorization() async throws {
        let status = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        switch status {
        case .authorized: return
        default: throw DictationError.speechDenied
        }
    }

    private static func requestMicrophoneAuthorization() async throws {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        if !granted { throw DictationError.microphoneDenied }
    }
}

/// Audio-tap-side pipeline. Lives outside the actor so the realtime
/// audio thread can convert and yield without an actor hop. The class
/// is `@unchecked Sendable` because AVAudioConverter isn't Sendable
/// but is only ever touched from the audio thread that the tap runs on.
private final class AudioPipeline: @unchecked Sendable {
    private let targetFormat: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private var converter: AVAudioConverter?

    init(targetFormat: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation) {
        self.targetFormat = targetFormat
        self.continuation = continuation
    }

    func prepare(sourceFormat: AVAudioFormat) {
        if sourceFormat == targetFormat {
            converter = nil
        } else {
            converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        }
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        let out: AVAudioPCMBuffer
        if let converter {
            let ratio = targetFormat.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
            guard let dst = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
            var fed = false
            var error: NSError?
            converter.convert(to: dst, error: &error) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return buffer
            }
            if error != nil || dst.frameLength == 0 { return }
            out = dst
        } else {
            out = buffer
        }
        continuation.yield(AnalyzerInput(buffer: out))
    }
}
