//
//  LocalTranscriber.swift
//  WhisperLive_iOS_Client
//
//  Created by ParkMazorika on 11/12/25.
//

import Foundation
import SwiftWhisper
import AVFoundation

class LocalTranscriber {
    private var whisper: Whisper?

    init() {
        guard let modelURL = Bundle.main.url(forResource: "ggml-tiny.en", withExtension: "bin") else {
            fatalError("Could not find model file.")
        }
        self.whisper = Whisper(fromFileURL: modelURL)
    }

    func transcribe(audioData: Data, completionHandler: @escaping (Result<[Segment], Error>) -> Void) {
        let pcmArray = pcm(data: audioData)

        Task {
            do {
                guard let whisper = self.whisper else {
                    throw NSError(domain: "LocalTranscriber", code: -1, userInfo: [NSLocalizedDescriptionKey: "Whisper model not initialized."])
                }
                let segments = try await whisper.transcribe(audioFrames: pcmArray)
                completionHandler(.success(segments))
            } catch {
                completionHandler(.failure(error))
            }
        }
    }

    private func pcm(data: Data) -> [Float] {
        let floats = stride(from: 0, to: data.count, by: 2).map {
            return data[$0..<$0 + 2].withUnsafeBytes {
                let short = Int16(littleEndian: $0.load(as: Int16.self))
                return max(-1.0, min(Float(short) / 32767.0, 1.0))
            }
        }
        return floats
    }
}
