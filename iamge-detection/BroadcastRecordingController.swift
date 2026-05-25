//
//  BroadcastRecordingController.swift
//  iamge-detection
//

import Foundation
import ReplayKit
import UIKit

enum BroadcastRecordingError: LocalizedError {
    case extensionNotEmbedded
    case extensionUnavailable
    case alreadyBroadcasting
    case notBroadcasting
    case stopFailed(String)
    case simulatorUnsupported

    var errorDescription: String? {
        switch self {
        case .extensionNotEmbedded:
            return "The screen broadcast extension is not embedded in this app build. Reinstall from Xcode and ensure BroadcastUploadExtension is included."
        case .extensionUnavailable:
            return "The screen broadcast extension is not available."
        case .alreadyBroadcasting:
            return "A system screen recording is already active."
        case .notBroadcasting:
            return "No system screen recording is active. Stop from Control Center first."
        case .stopFailed(let message):
            return "Could not stop screen recording: \(message)"
        case .simulatorUnsupported:
            return "System screen broadcast requires a physical iPhone or iPad. It does not work in the Simulator."
        }
    }
}

@MainActor
final class BroadcastRecordingController {
    static let shared = BroadcastRecordingController()

    private var onReadyHandler: (() -> Void)?
    private var onCaptureEndedHandler: (() -> Void)?
    private var isObservingRecordingReady = false
    private var captureObserver: NSObjectProtocol?

    var isBroadcasting: Bool {
        syncBroadcastStateWithSystem()
        return UIScreen.main.isCaptured
    }

    /// Clears persisted broadcast flags when iOS reports capture is off.
    func syncBroadcastStateWithSystem() {
        BroadcastRecordingHandoff.syncBroadcastActive(isSystemCaptured: UIScreen.main.isCaptured)
    }

    private init() {}

    func validateCanStartBroadcast() throws {
        #if targetEnvironment(simulator)
        throw BroadcastRecordingError.simulatorUnsupported
        #endif

        guard BroadcastConstants.isExtensionEmbedded else {
            throw BroadcastRecordingError.extensionNotEmbedded
        }
    }

    func beginObservingBroadcastState(
        onStarted: @escaping @MainActor () -> Void,
        onCaptureEnded: @escaping @MainActor () -> Void
    ) {
        endObservingBroadcastState()
        onCaptureEndedHandler = onCaptureEnded
        syncBroadcastStateWithSystem()

        var wasCaptured = UIScreen.main.isCaptured

        captureObserver = NotificationCenter.default.addObserver(
            forName: UIScreen.capturedDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.syncBroadcastStateWithSystem()

                let isCaptured = UIScreen.main.isCaptured
                if isCaptured, !wasCaptured {
                    wasCaptured = true
                    onStarted()
                } else if !isCaptured, wasCaptured {
                    wasCaptured = false
                    self.onCaptureEndedHandler?()
                }
            }
        }
    }

    func endObservingBroadcastState() {
        if let captureObserver {
            NotificationCenter.default.removeObserver(captureObserver)
            self.captureObserver = nil
        }
        onCaptureEndedHandler = nil
    }

    func requestStopBroadcast() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            BroadcastConstants.stopBroadcastNotification,
            nil,
            nil,
            true
        )
    }

    func stopBroadcastAndWaitForHandoff(timeout: TimeInterval = 90) async throws -> URL {
        if isBroadcasting {
            requestStopBroadcast()
        }

        return try await waitForRecordingHandoff(timeout: timeout)
    }

    func waitForRecordingHandoff(timeout: TimeInterval = 90) async throws -> URL {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let url = BroadcastRecordingHandoff.pendingRecordingURL() {
                return url
            }
            try await Task.sleep(for: .milliseconds(250))
        }

        if let url = BroadcastRecordingHandoff.pendingRecordingURL() {
            return url
        }

        if isBroadcasting {
            throw BroadcastRecordingError.stopFailed(
                "The broadcast is still active. Stop it from Control Center, then try again."
            )
        }

        throw BroadcastRecordingError.stopFailed(
            "Timed out waiting for the saved recording. Record for at least a few seconds before stopping."
        )
    }

    func observeRecordingReady(onReady: @escaping @MainActor () -> Void) {
        removeRecordingReadyObserver()
        onReadyHandler = onReady

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let controller = Unmanaged<BroadcastRecordingController>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in
                    controller.onReadyHandler?()
                }
            },
            BroadcastConstants.recordingReadyNotification.rawValue,
            nil,
            .deliverImmediately
        )
        isObservingRecordingReady = true
    }

    func removeRecordingReadyObserver() {
        guard isObservingRecordingReady else { return }
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            BroadcastConstants.recordingReadyNotification,
            nil
        )
        isObservingRecordingReady = false
        onReadyHandler = nil
    }
}
