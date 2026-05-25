//
//  BroadcastPickerView.swift
//  iamge-detection
//

import ReplayKit
import SwiftUI
import UIKit

struct BroadcastStartButton: View {
    @Bindable var viewModel: ImageClassifierViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SystemBroadcastPickerRepresentable(
                    onBroadcastStarted: {
                        viewModel.handleBroadcastStarted()
                    },
                    onBroadcastEnded: {
                        viewModel.handleBroadcastCaptureEnded()
                    }
                )
                .frame(width: 60, height: 60)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Start System Recording")
                        .font(.headline)
                    Text("Tap the record button, then confirm in the iOS broadcast sheet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            if !BroadcastConstants.isExtensionEmbedded {
                Text("Broadcast extension missing from app bundle. Clean build and reinstall on device.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .onAppear {
            do {
                try BroadcastRecordingController.shared.validateCanStartBroadcast()
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }
}

private struct SystemBroadcastPickerRepresentable: UIViewRepresentable {
    let onBroadcastStarted: () -> Void
    let onBroadcastEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBroadcastStarted: onBroadcastStarted, onBroadcastEnded: onBroadcastEnded)
    }

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        picker.preferredExtension = BroadcastConstants.extensionBundleID
        picker.showsMicrophoneButton = false
        picker.backgroundColor = .clear
        context.coordinator.startObserving()
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        uiView.preferredExtension = BroadcastConstants.extensionBundleID
    }

    static func dismantleUIView(_ uiView: RPSystemBroadcastPickerView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    final class Coordinator {
        private let onBroadcastStarted: () -> Void
        private let onBroadcastEnded: () -> Void
        private var observer: NSObjectProtocol?
        private var wasCaptured = false

        init(onBroadcastStarted: @escaping () -> Void, onBroadcastEnded: @escaping () -> Void) {
            self.onBroadcastStarted = onBroadcastStarted
            self.onBroadcastEnded = onBroadcastEnded
        }

        func startObserving() {
            BroadcastRecordingHandoff.syncBroadcastActive(isSystemCaptured: UIScreen.main.isCaptured)
            wasCaptured = UIScreen.main.isCaptured

            observer = NotificationCenter.default.addObserver(
                forName: UIScreen.capturedDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                BroadcastRecordingHandoff.syncBroadcastActive(isSystemCaptured: UIScreen.main.isCaptured)

                let isCaptured = UIScreen.main.isCaptured
                if isCaptured, !self.wasCaptured {
                    self.wasCaptured = true
                    self.onBroadcastStarted()
                } else if !isCaptured, self.wasCaptured {
                    self.wasCaptured = false
                    self.onBroadcastEnded()
                }
            }
        }

        func stopObserving() {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
        }
    }
}
