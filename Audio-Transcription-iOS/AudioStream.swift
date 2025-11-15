//  AudioStream.swift
//  Lecture2Quiz
//
//  Created by ParkMazorika on 4/27/25.
//

import AVFoundation

/// Streams audio input to a WebSocket after converting and normalizing.
class AudioStreamer {
    private let engine = AVAudioEngine()
    private let inputNode: AVAudioInputNode
    private var inputFormat: AVAudioFormat?
    private var isPaused: Bool = false
    private var transcriber: LocalTranscriber?
    private var isStreaming: Bool = false

    // Buffering properties
    private var audioBuffer = Data()
    private var isTranscribing = false
    private let bufferSizeInBytes: Int = 16000 * 2 * 5 // 5 seconds of 16kHz, 16-bit mono audio

    var onTranscriptionUpdate: (([Segment]) -> Void)?

    private var bufferSize: AVAudioFrameCount = 1600  // ~100ms of audio
    private var sampleRate: Double = 16000
    private var channels: UInt32 = 1

    private var converter: AVAudioConverter?

    init(transcriber: LocalTranscriber) {
        self.inputNode = engine.inputNode
        self.transcriber = transcriber
        // Converter will be created later, once the session is active.
    }

    /// Starts capturing and streaming audio data.
    func startStreaming() {
        guard !isStreaming else {
            print("Already streaming.")
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // 1. Configure and activate the audio session.
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
                try session.setPreferredSampleRate(48000)
                try session.setPreferredInputNumberOfChannels(1)
                try session.setMode(.videoChat)
                try session.setActive(true, options: .notifyOthersOnDeactivation)
                self.sampleRate = session.sampleRate
                self.channels = UInt32(session.inputNumberOfChannels)
                print("Audio session configured. Sample rate: \(self.sampleRate), Channels: \(self.channels)")
            } catch {
                print("Failed to configure audio session: \(error.localizedDescription)")
                return // Stop if session setup fails
            }

            // 2. Setup the audio format.
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48000,
                channels: self.channels,
                interleaved: true
            )

            guard let hardwareFormat = format else {
                print("Failed to create audio format.")
                return
            }
            self.inputFormat = hardwareFormat

            // 2.5 Create the audio converter now that we have a valid hardware format.
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16000,
                channels: 1,
                interleaved: true
            )!

            self.converter = AVAudioConverter(from: hardwareFormat, to: outputFormat)
            if self.converter == nil {
                print("Failed to create audio converter.")
                return
            }

            // 3. Install the audio tap.
            self.inputNode.installTap(onBus: 0, bufferSize: self.bufferSize, format: hardwareFormat) { buffer, _ in
                self.processAudioBuffer(buffer)
            }

            // 4. Start the audio engine.
            do {
                try self.engine.start()
                self.isStreaming = true
                print("AVAudioEngine started.")
            } catch {
                print("Failed to start AVAudioEngine: \(error.localizedDescription)")
            }
        }
    }

    /// Converts audio, buffers it, and triggers transcription when the buffer is full.
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let pcmData = convertToPCMData(buffer) else {
            print("Failed to convert buffer to PCM data.")
            return
        }

        audioBuffer.append(pcmData)

        // Check if the buffer is full and no transcription is in progress
        guard !isTranscribing, audioBuffer.count >= bufferSizeInBytes else {
            return
        }

        isTranscribing = true
        let bufferCopy = audioBuffer

        // Clear the buffer for the next chunk
        audioBuffer.removeAll()

        transcriber?.transcribe(audioData: bufferCopy) { [weak self] result in
            guard let self = self else { return }

            DispatchQueue.main.async {
                switch result {
                case .success(let segments):
                    self.onTranscriptionUpdate?(segments)
                case .failure(let error):
                    print("Transcription failed: \(error.localizedDescription)")
                }

                // Allow the next transcription to start
                self.isTranscribing = false
            }
        }
    }

    /// Converts an AVAudioPCMBuffer to raw PCM Data.
    private func convertToPCMData(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let converter = self.converter else {
            print("Audio converter is nil.")
            return nil
        }

        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        )!

        guard let newBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: buffer.frameCapacity) else {
            print("Failed to allocate PCM buffer.")
            return nil
        }

        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        var error: NSError?
        converter.convert(to: newBuffer, error: &error, withInputFrom: inputBlock)
        if let error = error {
            print("Audio conversion failed: \(error.localizedDescription)")
            return nil
        }

        let byteLength = Int(newBuffer.frameLength) * MemoryLayout<Int16>.size
        return Data(bytes: newBuffer.int16ChannelData!.pointee, count: byteLength)
    }

    /// Pauses audio streaming by removing the input tap.
    func pauseStreaming() {
        guard !isPaused else { return }
        inputNode.removeTap(onBus: 0)
        isPaused = true
        print("Audio streaming paused.")
    }

    /// Resumes audio streaming by reinstalling the input tap.
    func resumeStreaming() {
        guard isPaused else { return }
        guard let inputFormat = inputFormat else {
            print("inputFormat is nil.")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
        isPaused = false
        print("Audio streaming resumed.")
    }

    /// Stops the AVAudioEngine and resets streaming state.
    func stopStreaming() {
        guard isStreaming else {
            print("Already stopped.")
            return
        }

        inputNode.removeTap(onBus: 0)
        engine.stop()
        isStreaming = false
        print("AVAudioEngine stopped.")
    }
}
