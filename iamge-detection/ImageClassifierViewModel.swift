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

enum RecordingProcessingPhase: Equatable {
    case idle
    case preparingAudio
    case loadingWhisper
    case processingAudio
    case processingVideo
}

@MainActor
@Observable
final class ImageClassifierViewModel {
    var inputMode: ClassificationInputMode = .gallery
    var selectedImage: UIImage?
    var matches: [ClassificationMatch] = []
    var promptMatches: [ClassificationMatch] = []
    var isLoading = false
    var errorMessage: String?
    var modelReady = false
    var whisperReady = false
    var whisperLoadError: String?
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
    var recordingProcessingPhase: RecordingProcessingPhase = .idle
    var totalAudioSegmentsExpected = 0
    var audioSegmentsProcessed = 0
    var savedRecordingByteCount: Int64 = 0

    var classificationLabels: [String] {
        MobileCLIPClassifier.labels
    }

    var allPrompts: [String] {
        MobileCLIPClassifier.allPrompts
    }

    private var classifier: MobileCLIPClassifier?
    private var whisperTranscriber: ScreenRecordingWhisperTranscriber?
    private let broadcastController = BroadcastRecordingController.shared
    private var screenRecordingTask: Task<Void, Never>?

    var savedRecordingName: String? {
        savedRecordingURL?.lastPathComponent
    }

    var savedRecordingSizeText: String? {
        guard savedRecordingByteCount > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: savedRecordingByteCount, countStyle: .file)
    }

    init() {
        broadcastController.observeRecordingReady { [weak self] in
            self?.handleRecordingReadyNotification()
        }
    }

    func loadModelIfNeeded() async {
        await loadStartupModelsIfNeeded()
    }

    func loadStartupModelsIfNeeded() async {
        let needsCLIP = classifier == nil
        let needsWhisper = whisperTranscriber == nil
        guard needsCLIP || needsWhisper else { return }
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        whisperLoadError = nil

        await withTaskGroup(of: Void.self) { group in
            if needsCLIP {
                group.addTask { await self.loadCLIPModel() }
            }
            if needsWhisper {
                group.addTask { await self.loadWhisperModel() }
            }
        }

        if !isProcessingRecording {
            isLoading = false
        }
    }

    private func loadCLIPModel() async {
        guard classifier == nil else { return }

        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try MobileCLIPClassifier()
            }.value
            classifier = loaded
            modelReady = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadWhisperModel() async {
        guard whisperTranscriber == nil else { return }

        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try await ScreenRecordingWhisperTranscriber()
            }.value
            whisperTranscriber = loaded
            whisperReady = true
        } catch {
            whisperLoadError = error.localizedDescription
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
        promptMatches = []

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
        promptMatches = []
        framesProcessed = 0
        frameTimeline = []
        temporaryFramePreview = nil
        temporaryFrameTimestamp = 0
        totalFramesExpected = 0
        recordingFPS = 0
        savedRecordingURL = nil
        savedRecordingByteCount = 0
        recordingProcessingPhase = .idle
        totalAudioSegmentsExpected = 0
        audioSegmentsProcessed = 0
        recordingStartedAt = Date()
        isScreenRecording = true
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
        broadcastController.syncBroadcastStateWithSystem()
        if !broadcastController.isBroadcasting {
            isScreenRecording = false
            recordingStartedAt = nil
        }
    }

    func handleAppBecameActive() {
        broadcastController.syncBroadcastStateWithSystem()

        if broadcastController.isBroadcasting {
            if !isScreenRecording {
                handleBroadcastStarted()
            }
        } else {
            isScreenRecording = false
            recordingStartedAt = nil
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
        promptMatches = []
        framesProcessed = 0
        frameTimeline = []
        temporaryFramePreview = nil
        temporaryFrameTimestamp = 0
        totalFramesExpected = 0
        recordingFPS = 0
        savedRecordingURL = recordingURL
        savedRecordingByteCount = Self.fileSize(at: recordingURL)
        recordingProcessingPhase = .preparingAudio
        totalAudioSegmentsExpected = 0
        audioSegmentsProcessed = 0

        try await ensureModelReady()
        guard let classifier else {
            throw ClassifierError.modelLoadFailed("Models failed to load.")
        }

        let labels = classificationLabels
        let temp = temperature

        let metadata = try await ScreenRecordingFrameExtractor.loadMetadata(from: recordingURL)
        recordingFPS = metadata.fps
        totalFramesExpected = metadata.estimatedFrameCount

        let hasAudio = await ScreenRecordingAudioExtractor.hasAudioTrack(in: recordingURL)

        if hasAudio, whisperTranscriber == nil {
            recordingProcessingPhase = .loadingWhisper
            await loadWhisperModel()
        }
        let transcriberForProcessing = whisperTranscriber

        let updateProgress: @Sendable (Int, TimeInterval, UIImage?) async -> Void = { [weak self] count, timestamp, preview in
            await MainActor.run {
                guard let self else { return }
                self.recordingProcessingPhase = .processingVideo
                self.framesProcessed = count
                if let preview {
                    self.temporaryFramePreview = preview
                    self.temporaryFrameTimestamp = timestamp
                }
            }
        }

        let updateAudioProgress: @Sendable (RecordingProcessingPhase, Int, Int) async -> Void = { [weak self] phase, processed, total in
            await MainActor.run {
                guard let self else { return }
                self.recordingProcessingPhase = phase
                self.audioSegmentsProcessed = processed
                self.totalAudioSegmentsExpected = total
            }
        }

        let processed = try await Task.detached(priority: .userInitiated) {
            var frameResults: [[ClassificationMatch]] = []
            var timedFrames: [(
                timestamp: TimeInterval,
                matches: [ClassificationMatch],
                thumbnail: UIImage?,
                bottomCropThumbnail: UIImage?,
                audioTranscript: String?,
                audioTone: String?,
                audioLabel: String?,
                videoMatchedPrompt: String?,
                audioMatchedPrompt: String?
            )] = []
            var lastPreview: UIImage?

            var classifiedCount = 0

            var transcriber: ScreenRecordingWhisperTranscriber?
            var audioSegments: [ScreenRecordingAudioSegment] = []
            if hasAudio {
                await updateAudioProgress(.preparingAudio, 0, 0)
                audioSegments = try await ScreenRecordingAudioExtractor.exportClassificationWindows(from: recordingURL)
                transcriber = transcriberForProcessing
            }

            var audioByTimestamp: [TimeInterval: (transcript: String, tone: String, matches: [ClassificationMatch])] = [:]
            if let transcriber {
                for (index, segment) in audioSegments.enumerated() {
                    await updateAudioProgress(.processingAudio, index, audioSegments.count)
                    let transcript: String
                    if FileManager.default.fileExists(atPath: segment.wavURL.path) {
                        transcript = (try? await transcriber.transcribe(wavURL: segment.wavURL)) ?? ""
                    } else {
                        transcript = ""
                    }
                    let tone = FileManager.default.fileExists(atPath: segment.wavURL.path)
                        ? ScreenRecordingAudioToneAnalyzer.analyze(
                            wavURL: segment.wavURL,
                            transcript: transcript,
                            durationSeconds: TimeInterval(BroadcastConstants.classificationIntervalSeconds)
                        )
                        : AudioToneAnalysis(
                            description: "silent or unreadable audio",
                            energy: "silent",
                            character: "silent",
                            pace: nil
                        )
                    let audioMatches = try classifier.classify(
                        transcript: transcript,
                        tone: tone.description,
                        temperature: temp
                    ).categories
                    audioByTimestamp[segment.timestamp] = (transcript, tone.description, audioMatches)
                    try? FileManager.default.removeItem(at: segment.wavURL)
                    await updateAudioProgress(.processingAudio, index + 1, audioSegments.count)
                }
            } else if !audioSegments.isEmpty {
                for (index, segment) in audioSegments.enumerated() {
                    await updateAudioProgress(.processingAudio, index, audioSegments.count)
                    guard FileManager.default.fileExists(atPath: segment.wavURL.path) else {
                        await updateAudioProgress(.processingAudio, index + 1, audioSegments.count)
                        continue
                    }
                    let tone = ScreenRecordingAudioToneAnalyzer.analyze(
                        wavURL: segment.wavURL,
                        durationSeconds: TimeInterval(BroadcastConstants.classificationIntervalSeconds)
                    )
                    let audioMatches = try classifier.classify(
                        transcript: "",
                        tone: tone.description,
                        temperature: temp
                    ).categories
                    audioByTimestamp[segment.timestamp] = ("", tone.description, audioMatches)
                    try? FileManager.default.removeItem(at: segment.wavURL)
                    await updateAudioProgress(.processingAudio, index + 1, audioSegments.count)
                }
            }

            await updateAudioProgress(.processingVideo, audioSegments.count, audioSegments.count)
            if audioSegments.isEmpty {
                await updateAudioProgress(.processingVideo, 0, 0)
            }

            try await ScreenRecordingFrameExtractor.forEachFrame(from: recordingURL) { frame in
                guard ScreenRecordingFrameExtractor.shouldClassify(at: frame.timestamp) else { return }

                let videoResult = try classifier.classify(
                    pixelBuffer: frame.pixelBuffer,
                    temperature: temp
                )

                let roundedTimestamp = TimeInterval(Int(frame.timestamp.rounded(.down)))
                let audioInfo = audioByTimestamp[roundedTimestamp]
                let mergedMatches = ScreenRecordingAggregator.mergeVideoAndAudio(
                    videoMatches: videoResult.categories,
                    audioMatches: audioInfo?.matches,
                    labels: labels,
                    temperature: temp,
                    transcript: audioInfo?.transcript,
                    audioTone: audioInfo?.tone
                )

                classifiedCount += 1
                frameResults.append(mergedMatches)
                let previews = ImagePreprocessor.modelInputPreviews(from: frame.pixelBuffer)
                let preview = ImagePreprocessor.uiImage(from: frame.pixelBuffer)
                lastPreview = preview
                timedFrames.append((
                    timestamp: frame.timestamp,
                    matches: mergedMatches,
                    thumbnail: preview,
                    bottomCropThumbnail: previews.bottomCrop,
                    audioTranscript: audioInfo?.transcript,
                    audioTone: audioInfo?.tone,
                    audioLabel: audioInfo?.matches.first?.label,
                    videoMatchedPrompt: videoResult.categories.first?.matchedPrompt,
                    audioMatchedPrompt: audioInfo?.matches.first?.matchedPrompt
                ))
                await updateProgress(classifiedCount, frame.timestamp, preview)
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
        recordingProcessingPhase = .idle
    }

    func resetBroadcastUIState() {
        screenRecordingTask?.cancel()
        screenRecordingTask = nil
        isScreenRecording = false
        isProcessingRecording = false
        recordingStartedAt = nil
        temporaryFramePreview = nil
        temporaryFrameTimestamp = 0
        recordingProcessingPhase = .idle
        totalAudioSegmentsExpected = 0
        audioSegmentsProcessed = 0
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

        let temp = temperature
        let start = CACurrentMediaTime()

        let results = try await Task.detached {
            try classifier.classify(image: image, temperature: temp)
        }.value

        lastInferenceMilliseconds = (CACurrentMediaTime() - start) * 1000
        promptMatches = results.prompts
        return results.categories
    }

    private static func fileSize(at url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }
}
