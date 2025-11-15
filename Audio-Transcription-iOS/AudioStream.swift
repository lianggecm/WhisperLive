//
//  AudioStream.swift
//  Lecture2Quiz
//
//  Created by ParkMazorika on 4/27/25.
//

import AVFoundation
import AudioKit
import SwiftWhisper

/// Captures audio input using AudioKit and streams it for transcription.
class AudioStreamer {
    private var transcriber: LocalTranscriber?
    private let engine = AudioKit.Engine()
    private var mic: InputDevice?
    private var tap: Tap?
    private var isStreaming = false
    private var formatConverter: FormatConverter?

    // Buffering properties
    private var audioBuffer = Data()
    private var isTranscribing = false
    private let bufferSizeInBytes: Int = 16000 * 2 * 5 // 5 seconds of 16kHz, 16-bit mono audio

    var onTranscriptionUpdate: (([Segment]) -> Void)?

    init(transcriber: LocalTranscriber) {
        self.transcriber = transcriber
        setupAudioKit()
    }

    private func setupAudioKit() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
            try session.setActive(true)

            mic = engine.input

            guard let mic = mic, let inputFormat = mic.avAudioNode.outputFormat(forBus: 0) else {
                print("Microphone or its format is not available.")
                return
            }

            let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
            formatConverter = FormatConverter(inputFormat: inputFormat, outputFormat: outputFormat)

            let mixer = Mixer(mic)
            engine.output = mixer

            tap = Tap(mixer) { [weak self] buffer in
                self?.processAudioBuffer(buffer)
            }

        } catch {
            print("AudioKit setup failed: \(error.localizedDescription)")
        }
    }

    /// Starts capturing and streaming audio data.
    func startStreaming() {
        guard !isStreaming, let mic = mic, let tap = tap else {
            print("Already streaming or AudioKit not set up.")
            return
        }

        mic.start()
        tap.start()

        do {
            try engine.start()
            isStreaming = true
            print("AudioKit engine started.")
        } catch {
            print("Failed to start AudioKit engine: \(error.localizedDescription)")
        }
    }

    /// Buffers audio and triggers transcription.
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let pcmData = convertToPCMData(buffer: buffer) else {
            print("Could not convert buffer to PCM data.")
            return
        }

        audioBuffer.append(pcmData)

        guard !isTranscribing, audioBuffer.count >= bufferSizeInBytes else {
            return
        }

        isTranscribing = true
        let bufferCopy = audioBuffer
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
                self.isTranscribing = false
            }
        }
    }

    /// Safely converts the buffer to the required PCM format.
    private func convertToPCMData(buffer: AVAudioPCMBuffer) -> Data? {
        guard let formatConverter = formatConverter,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: formatConverter.outputFormat, frameCapacity: buffer.frameCapacity) else {
            return nil
        }

        var error: NSError?
        let success = formatConverter.convert(to: pcmBuffer, from: buffer, error: &error)

        if !success {
            print("Format conversion failed: \(error?.localizedDescription ?? "Unknown error")")
            return nil
        }

        let byteLength = Int(pcmBuffer.frameLength) * 2
        return Data(bytes: pcmBuffer.int16ChannelData!.pointee, count: byteLength)
    }

    /// Pauses audio streaming.
    func pauseStreaming() {
        mic?.stop()
        tap?.stop()
        engine.pause()
        print("Audio streaming paused.")
    }

    /// Resumes audio streaming.
    func resumeStreaming() {
        mic?.start()
        tap?.start()
        do {
            try engine.start()
            print("Audio streaming resumed.")
        } catch {
             print("Failed to resume AudioKit engine: \(error.localizedDescription)")
        }
    }

    /// Stops the AudioKit engine and resets the state.
    func stopStreaming() {
        guard isStreaming else {
            print("Already stopped.")
            return
        }

        mic?.stop()
        tap?.stop()
        engine.stop()

        audioBuffer.removeAll()
        isStreaming = false
        print("AudioKit engine stopped.")
    }
}
