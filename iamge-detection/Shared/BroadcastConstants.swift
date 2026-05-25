//
//  BroadcastConstants.swift
//  Shared between main app and Broadcast Upload Extension
//

import Foundation

enum BroadcastConstants {
    static let appGroupID = "group.com.abui.iamge-detection.shared"
    static let recordingsFolderName = "Recordings"

    /// Frames written to the saved MP4 during broadcast (1 frame per second).
    static let targetRecordingFPS: Double = 1

    /// Classify one saved frame every N seconds during post-processing.
    static let classificationIntervalSeconds: Int = 3

    static let recordingReadyKey = "recordingReady"
    static let lastRecordingPathKey = "lastRecordingPath"
    static let recordingFinishedAtKey = "recordingFinishedAt"
    static let broadcastActiveKey = "broadcastActive"

    static let recordingReadyNotification = CFNotificationName(
        "com.abui.iamge-detection.recordingReady" as CFString
    )

    static let stopBroadcastNotification = CFNotificationName(
        "com.abui.iamge-detection.stopBroadcast" as CFString
    )

    /// Fallback if the embedded plug-in cannot be discovered at runtime.
    static let fallbackExtensionBundleID = "com.abui.iamge-detection.BroadcastUploadExtension"

    /// Bundle ID of the embedded Broadcast Upload Extension inside the app.
    static var extensionBundleID: String {
        resolvedExtensionBundleID ?? fallbackExtensionBundleID
    }

    static var resolvedExtensionBundleID: String? {
        guard let pluginsURL = Bundle.main.builtInPlugInsURL,
              let contents = try? FileManager.default.contentsOfDirectory(
                at: pluginsURL,
                includingPropertiesForKeys: nil
              ) else {
            return nil
        }

        return contents
            .filter { $0.pathExtension == "appex" }
            .compactMap { Bundle(url: $0)?.bundleIdentifier }
            .first { $0.localizedCaseInsensitiveContains("BroadcastUploadExtension") }
    }

    static var isExtensionEmbedded: Bool {
        resolvedExtensionBundleID != nil
    }
}
