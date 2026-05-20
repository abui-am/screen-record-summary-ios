//
//  SampleHandler.swift
//  BroadcastUploadExtension
//

import os.log
import ReplayKit

final class SampleHandler: RPBroadcastSampleHandler {
    private static let logger = Logger(
        subsystem: "com.abui.iamge-detection.BroadcastUploadExtension",
        category: "SampleHandler"
    )

    private var writer: ScreenRecordingWriter?
    private var outputURL: URL?
    private var didFinalizeRecording = false
    private var stopObserverRegistered = false

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        BroadcastRecordingHandoff.clearRecordingState()
        BroadcastRecordingHandoff.setBroadcastActive(true)
        registerStopObserver()

        guard BroadcastRecordingHandoff.recordingsDirectory != nil else {
            finishWithMessage(
                "App Group is unavailable. Enable group.com.abui.iamge-detection.shared in Signing & Capabilities for both targets."
            )
            return
        }

        guard let url = BroadcastRecordingHandoff.makeRecordingURL() else {
            finishWithMessage("Could not create a recording file in the shared App Group container.")
            return
        }

        do {
            outputURL = url
            writer = try ScreenRecordingWriter(outputURL: url)
            Self.logger.info("Broadcast started. Writing to \(url.path, privacy: .public)")
        } catch {
            finishWithMessage(error.localizedDescription)
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }

        autoreleasepool {
            do {
                try writer?.append(sampleBuffer: sampleBuffer)
            } catch {
                Self.logger.error("Append failed: \(error.localizedDescription, privacy: .public)")
                finishWithMessage(error.localizedDescription)
            }
        }
    }

    override func broadcastFinished() {
        unregisterStopObserver()
        BroadcastRecordingHandoff.setBroadcastActive(false)
        finalizeRecordingIfNeeded()
    }

    private func handleStopRequestFromHost() {
        Self.logger.info("Received stop request from host app.")
        finalizeRecordingIfNeeded()
        stopReplayKitBroadcastWithoutAlert()
    }

    private func finalizeRecordingIfNeeded() {
        guard !didFinalizeRecording else { return }
        didFinalizeRecording = true

        do {
            try writer?.finish()
            if let outputURL, FileManager.default.fileExists(atPath: outputURL.path) {
                BroadcastRecordingHandoff.markRecordingReady(at: outputURL)
                Self.logger.info("Saved recording to \(outputURL.path, privacy: .public)")
            } else {
                Self.logger.error("Broadcast finished without a saved recording file.")
            }
        } catch {
            Self.logger.error("Finish failed: \(error.localizedDescription, privacy: .public)")
            finishWithMessage(error.localizedDescription)
        }
    }

    private func registerStopObserver() {
        guard !stopObserverRegistered else { return }
        stopObserverRegistered = true

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let handler = Unmanaged<SampleHandler>.fromOpaque(observer).takeUnretainedValue()
                handler.handleStopRequestFromHost()
            },
            BroadcastConstants.stopBroadcastNotification.rawValue,
            nil,
            .deliverImmediately
        )
    }

    private func unregisterStopObserver() {
        guard stopObserverRegistered else { return }
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            BroadcastConstants.stopBroadcastNotification,
            nil
        )
        stopObserverRegistered = false
    }

    private func stopReplayKitBroadcastWithoutAlert() {
        let selector = NSSelectorFromString("finishBroadcastWithError:")
        guard responds(to: selector) else { return }
        perform(selector, with: nil)
    }

    private func finishWithMessage(_ message: String) {
        let error = NSError(
            domain: "BroadcastUploadExtension",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
        finishBroadcastWithError(error)
    }
}
