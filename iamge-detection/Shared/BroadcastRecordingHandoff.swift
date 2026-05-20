//
//  BroadcastRecordingHandoff.swift
//  Shared between main app and Broadcast Upload Extension
//

import CoreFoundation
import Foundation

enum BroadcastRecordingHandoff {
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: BroadcastConstants.appGroupID)
    }

    static var recordingsDirectory: URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: BroadcastConstants.appGroupID
        ) else {
            return nil
        }
        let directory = container.appendingPathComponent(BroadcastConstants.recordingsFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func makeRecordingURL() -> URL? {
        guard let directory = recordingsDirectory else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return directory.appendingPathComponent("screen-recording-\(timestamp).mp4")
    }

    static func setBroadcastActive(_ active: Bool) {
        defaults?.set(active, forKey: BroadcastConstants.broadcastActiveKey)
    }

    static var isBroadcastActive: Bool {
        defaults?.bool(forKey: BroadcastConstants.broadcastActiveKey) ?? false
    }

    static func markRecordingReady(at url: URL) {
        defaults?.set(url.path, forKey: BroadcastConstants.lastRecordingPathKey)
        defaults?.set(Date().timeIntervalSince1970, forKey: BroadcastConstants.recordingFinishedAtKey)
        defaults?.set(true, forKey: BroadcastConstants.recordingReadyKey)
        defaults?.synchronize()

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            BroadcastConstants.recordingReadyNotification,
            nil,
            nil,
            true
        )
    }

    static var isRecordingReady: Bool {
        defaults?.bool(forKey: BroadcastConstants.recordingReadyKey) ?? false
    }

    static func pendingRecordingURL() -> URL? {
        guard defaults?.bool(forKey: BroadcastConstants.recordingReadyKey) == true,
              let path = defaults?.string(forKey: BroadcastConstants.lastRecordingPathKey) else {
            return nil
        }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    @discardableResult
    static func consumeRecordingReady() -> URL? {
        guard let url = pendingRecordingURL() else { return nil }
        defaults?.set(false, forKey: BroadcastConstants.recordingReadyKey)
        defaults?.removeObject(forKey: BroadcastConstants.lastRecordingPathKey)
        return url
    }

    static func clearRecordingState() {
        defaults?.set(false, forKey: BroadcastConstants.recordingReadyKey)
        defaults?.set(false, forKey: BroadcastConstants.broadcastActiveKey)
        defaults?.removeObject(forKey: BroadcastConstants.lastRecordingPathKey)
    }
}
