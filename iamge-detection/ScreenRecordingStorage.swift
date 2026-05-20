//
//  ScreenRecordingStorage.swift
//  iamge-detection
//

import Foundation

enum ScreenRecordingStorage {
    static var recordingsDirectory: URL {
        if let shared = BroadcastRecordingHandoff.recordingsDirectory {
            return shared
        }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func makeRecordingURL() -> URL {
        BroadcastRecordingHandoff.makeRecordingURL()
            ?? recordingsDirectory.appendingPathComponent("screen-recording-\(UUID().uuidString).mp4")
    }
}
