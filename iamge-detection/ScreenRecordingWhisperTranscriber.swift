//
//  ScreenRecordingWhisperTranscriber.swift
//  iamge-detection
//

import Foundation
@preconcurrency import WhisperKit

enum WhisperTranscriberError: LocalizedError {
    case loadFailed(String)
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .loadFailed(let message):
            return "Failed to load Whisper model: \(message)"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        }
    }
}

/// On-device Whisper base transcription via WhisperKit. Loads off the main thread.
final class ScreenRecordingWhisperTranscriber {
    static let sharedModelName = "base"

    private let whisperKit: WhisperKit

    init() async throws {
        do {
            whisperKit = try await WhisperKit(
                WhisperKitConfig(model: Self.sharedModelName)
            )
        } catch {
            throw WhisperTranscriberError.loadFailed(error.localizedDescription)
        }
    }

    func transcribe(wavURL: URL) async throws -> String {
        let path = wavURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            return ""
        }

        do {
            let results = try await whisperKit.transcribe(audioPath: path)
            return results
                .compactMap(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw WhisperTranscriberError.transcriptionFailed(error.localizedDescription)
        }
    }
}
