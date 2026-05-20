//
//  ImageClassifierViewModel.swift
//  iamge-detection
//

import PhotosUI
import QuartzCore
import SwiftUI
import UIKit

enum ClassificationInputMode: String, CaseIterable, Identifiable {
    case gallery
    case screenCapture

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gallery: "Gallery"
        case .screenCapture: "Screen Record"
        }
    }
}

@MainActor
@Observable
final class ImageClassifierViewModel {
    var inputMode: ClassificationInputMode = .gallery
    var selectedImage: UIImage?
    var matches: [ClassificationMatch] = []
    var isLoading = false
    var errorMessage: String?
    var modelReady = false
    var temperature: Float = 100
    var isScreenRecording = false
    var isProcessingRecording = false
    var recordingStartedAt: Date?
    var savedRecordingURL: URL?
    var recordingFPS: Float = 0
    var totalFramesExpected = 0
    var framesProcessed = 0
    var frameTimeline: [FrameClassificationSummary] = []
    var temporaryFramePreview: UIImage?
    var temporaryFrameTimestamp: TimeInterval = 0
    var lastInferenceMilliseconds: Double = 0

    var classificationLabels: [String] {
        MobileCLIPClassifier.labels
    }

    private var classifier: MobileCLIPClassifier?
    private let broadcastController = BroadcastRecordingController.shared
    private var screenRecordingTask: Task<Void, Never>?

    var savedRecordingName: String? {
        savedRecordingURL?.lastPathComponent
    }

    init() {
        broadcastController.observeRecordingReady { [weak self] in
            self?.handleRecordingReadyNotification()
        }
    }

    func loadModelIfNeeded() async {
        guard classifier == nil else { return }
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try MobileCLIPClassifier()
            }.value
            classifier = loaded
            modelReady = true
        } catch {
            errorMessage = error.localizedDescription
        }

        if !isProcessingRecording {
            isLoading = false
        }
    }

    func ensureModelReady() async throws {
        if classifier == nil {
            await loadModelIfNeeded()
        }
        guard classifier != nil else {
            throw ClassifierError.modelLoadFailed("Models failed to load.")
        }
    }

    func handlePhotoSelection(_ item: PhotosPickerItem?) {
        guard let item else { return }
        resetBroadcastUIState()
        isLoading = true
        errorMessage = nil
        matches = []

        Task {
            do {
                try await ensureModelReady()
                let image = try await GalleryImageLoader.loadFullResolution(from: item)
                selectedImage = image
                matches = try await runClassification(on: image)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func classifySelectedImage() {
        guard let selectedImage else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await ensureModelReady()
                matches = try await runClassification(on: selectedImage)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func handleBroadcastStarted() {
        guard !isProcessingRecording else { return }

        errorMessage = nil
        matches = []
        framesProcessed = 0
        frameTimeline = []
        temporaryFramePreview = nil
        temporaryFrameTimestamp = 0
        totalFramesExpected = 0
        recordingFPS = 0
        savedRecordingURL = nil
        recordingStartedAt = Date()
        isScreenRecording = true

        ScreenCaptureOverlayWindowController.shared.present(viewModel: self) { [weak self] in
            self?.finishScreenRecording()
        }
    }

    func finishScreenRecording() {
        guard isScreenRecording || broadcastController.isBroadcasting else { return }
        guard !isProcessingRecording else { return }

        isProcessingRecording = true
        screenRecordingTask?.cancel()
        screenRecordingTask = Task {
            await completeRecordingAfterBroadcast(shouldRequestStop: true)
        }
    }

    func handleBroadcastCaptureEnded() {
        guard isScreenRecording || broadcastController.isBroadcasting else { return }
        guard !isProcessingRecording else { return }

        isProcessingRecording = true
        screenRecordingTask?.cancel()
        screenRecordingTask = Task {
            await completeRecordingAfterBroadcast(shouldRequestStop: false)
        }
    }

    private func completeRecordingAfterBroadcast(shouldRequestStop: Bool) async {
        isScreenRecording = false
        recordingStartedAt = nil
        ScreenCaptureOverlayWindowController.shared.dismiss()
        isProcessingRecording = true
        isLoading = true
        errorMessage = nil

        do {
            let recordingURL: URL
            if shouldRequestStop {
                recordingURL = try await broadcastController.stopBroadcastAndWaitForHandoff()
            } else {
                recordingURL = try await broadcastController.waitForRecordingHandoff()
            }

            let claimedURL = BroadcastRecordingHandoff.consumeRecordingReady() ?? recordingURL
            try await processSavedRecording(at: claimedURL)
        } catch {
            temporaryFramePreview = nil
            temporaryFrameTimestamp = 0
            if let url = BroadcastRecordingHandoff.consumeRecordingReady() {
                do {
                    try await processSavedRecording(at: url)
                } catch {
                    errorMessage = error.localizedDescription
                }
            } else {
                errorMessage = error.localizedDescription
            }
        }

        isProcessingRecording = false
        isLoading = false
    }

    func handleAppBecameActive() {
        if broadcastController.isBroadcasting, !isScreenRecording {
            handleBroadcastStarted()
        }

        if BroadcastRecordingHandoff.isRecordingReady, !isProcessingRecording, !isScreenRecording {
            screenRecordingTask?.cancel()
            screenRecordingTask = Task {
                await processPendingRecordingIfNeeded()
            }
        }
    }

    func handleRecordingReadyNotification() {
        guard BroadcastRecordingHandoff.isRecordingReady else { return }
        guard !isProcessingRecording else { return }

        screenRecordingTask?.cancel()
        screenRecordingTask = Task {
            isScreenRecording = false
            recordingStartedAt = nil
            ScreenCaptureOverlayWindowController.shared.dismiss()
            await processPendingRecordingIfNeeded()
        }
    }

    private func processPendingRecordingIfNeeded() async {
        guard let url = BroadcastRecordingHandoff.consumeRecordingReady() else { return }

        isProcessingRecording = true
        isLoading = true
        errorMessage = nil

        do {
            try await processSavedRecording(at: url)
        } catch {
            errorMessage = error.localizedDescription
            temporaryFramePreview = nil
            temporaryFrameTimestamp = 0
        }

        isProcessingRecording = false
        isLoading = false
    }

    private func processSavedRecording(at recordingURL: URL) async throws {
        matches = []
        framesProcessed = 0
        frameTimeline = []
        temporaryFramePreview = nil
        temporaryFrameTimestamp = 0
        totalFramesExpected = 0
        recordingFPS = 0
        savedRecordingURL = recordingURL

        try await ensureModelReady()
        guard let classifier else {
            throw ClassifierError.modelLoadFailed("Models failed to load.")
        }

        let labels = classificationLabels
        let temp = temperature

        let metadata = try await ScreenRecordingFrameExtractor.loadMetadata(from: recordingURL)
        recordingFPS = metadata.fps
        totalFramesExpected = metadata.estimatedFrameCount

        let updateProgress: @Sendable (Int, TimeInterval, UIImage?) async -> Void = { [weak self] count, timestamp, preview in
            await MainActor.run {
                guard let self else { return }
                self.framesProcessed = count
                if let preview {
                    self.temporaryFramePreview = preview
                    self.temporaryFrameTimestamp = timestamp
                }
            }
        }

        let processed = try await Task.detached(priority: .userInitiated) {
            var frameResults: [[ClassificationMatch]] = []
            var timedFrames: [(
                timestamp: TimeInterval,
                matches: [ClassificationMatch],
                thumbnail: UIImage?,
                bottomCropThumbnail: UIImage?
            )] = []
            var lastPreview: UIImage?

            try await ScreenRecordingFrameExtractor.forEachFrame(from: recordingURL) { frame in
                let results = try classifier.classify(
                    pixelBuffer: frame.pixelBuffer,
                    labels: labels,
                    temperature: temp
                )

                frameResults.append(results)
                let previews = ImagePreprocessor.modelInputPreviews(from: frame.pixelBuffer)
                let preview = ImagePreprocessor.uiImage(from: frame.pixelBuffer)
                lastPreview = preview
                timedFrames.append((
                    timestamp: frame.timestamp,
                    matches: results,
                    thumbnail: preview,
                    bottomCropThumbnail: previews.bottomCrop
                ))
                await updateProgress(frame.index + 1, frame.timestamp, preview)
            }

            return (frameResults, timedFrames, lastPreview)
        }.value

        selectedImage = processed.2
        temporaryFramePreview = nil
        temporaryFrameTimestamp = 0

        matches = ScreenRecordingAggregator.aggregate(
            frameResults: processed.0,
            labels: labels,
            temperature: temp
        )
        frameTimeline = ScreenRecordingAggregator.timeline(
            frames: processed.1,
            fps: metadata.fps
        )
    }

    func resetBroadcastUIState() {
        screenRecordingTask?.cancel()
        screenRecordingTask = nil
        ScreenCaptureOverlayWindowController.shared.dismiss()
        isScreenRecording = false
        isProcessingRecording = false
        recordingStartedAt = nil
        temporaryFramePreview = nil
        temporaryFrameTimestamp = 0
    }

    func handleInputModeChange(from oldMode: ClassificationInputMode, to newMode: ClassificationInputMode) {
        if oldMode == .screenCapture {
            resetBroadcastUIState()
        }
        if newMode == .gallery {
            framesProcessed = 0
        }
    }

    private func runClassification(on image: UIImage) async throws -> [ClassificationMatch] {
        guard let classifier else {
            throw ClassifierError.modelLoadFailed("Model is not loaded yet.")
        }

        let labels = classificationLabels
        let temp = temperature
        let start = CACurrentMediaTime()

        let results = try await Task.detached {
            try classifier.classify(image: image, labels: labels, temperature: temp)
        }.value

        lastInferenceMilliseconds = (CACurrentMediaTime() - start) * 1000
        return results
    }
}
