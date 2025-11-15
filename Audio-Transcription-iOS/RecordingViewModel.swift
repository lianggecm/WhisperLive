//
//  RecordingViewModel.swift
//  Lecture2Quiz
//
//  Created by ParkMazorika on 4/27/25.
//

import AVFoundation
import Combine
import SwiftWhisper

/// ViewModel responsible for managing audio recording and transcription logic.
class AudioViewModel: ObservableObject {
    @Published var isRecording = false            // Indicates if recording is active
    @Published var isPaused = false               // Indicates if recording is currently paused
    @Published var timeLabel = "00:00"            // Timer label formatted as mm:ss
    @Published var transcriptionList: [String] = []  // Live transcription output
    @Published var isLoading = false              // True while waiting for server response
    @Published var finalScript: String = ""       // Final script from completed segments

    private var timer: Timer?
    private var elapsedTime: Int = 0

    private var audioStreamer: AudioStreamer?     // Handles audio capture and streaming
    private var localTranscriber: LocalTranscriber?   // Manages local transcription

    private var segments: [Segment] = []  // Stores all transcription segments

    init() {
        self.localTranscriber = LocalTranscriber()
    }

    /// Starts audio recording and initializes the transcriber.
    func startRecording() {
        audioStreamer = AudioStreamer(transcriber: localTranscriber!)

        self.isRecording = true
        self.isPaused = false
        self.timeLabel = "00:00"
        self.elapsedTime = 0
        self.startTimer()
        self.audioStreamer?.startStreaming()

        audioStreamer?.onTranscriptionUpdate = { [weak self] segments in
            self?.handleTranscriptionUpdate(segments: segments)
        }
    }

    /// Pauses the recording and stops the timer.
    func pauseRecording() {
        isPaused = true
        audioStreamer?.pauseStreaming()
        timer?.invalidate()
    }

    /// Resumes recording and restarts the timer.
    func resumeRecording() {
        isPaused = false
        audioStreamer?.resumeStreaming()
        startTimer()
    }

    /// Stops recording and finalizes connection to server.
    func stopRecording() {
        isRecording = false
        isPaused = false
        timer?.invalidate()

        audioStreamer?.stopStreaming()
    }

    /// Starts the recording timer (1-second interval).
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.elapsedTime += 1
            let minutes = self.elapsedTime / 60
            let seconds = self.elapsedTime % 60
            self.timeLabel = String(format: "%02d:%02d", minutes, seconds)
        }
    }

    /// Finalizes the transcription by joining all completed segments into one string.
    func finalizeTranscription() {
        isLoading = false
        let completedText = segments
            .map { $0.text.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
        finalScript = completedText
        print("Final transcript:\n\(finalScript)")
    }

    private func handleTranscriptionUpdate(segments: [Segment]) {
        // Using a dictionary to ensure segments are unique based on their start/end times
        var segmentDict = Dictionary(uniqueKeysWithValues: self.segments.map { ("\($0.startTime)-\($0.endTime)", $0) })
        for segment in segments {
            segmentDict["\(segment.startTime)-\(segment.endTime)"] = segment
        }

        // Sort segments by start time
        self.segments = segmentDict.values.sorted { $0.startTime < $1.startTime }

        // Update the UI
        DispatchQueue.main.async {
            // Since there is no 'completed' property, we treat all segments as final
            let allText = self.segments
                .map { $0.text.trimmingCharacters(in: .whitespaces) }

            self.transcriptionList = allText
            self.finalScript = allText.joined(separator: " ")
        }
    }
}
