//
//  ContentView.swift
//  iamge-detection
//

import AVFoundation
import AVKit
import PhotosUI
import SwiftUI

struct ContentView: View {
    @State private var viewModel = ImageClassifierViewModel()
    @State private var selectedItem: PhotosPickerItem?
    @State private var recordingPlayer: AVPlayer?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if !viewModel.modelReady || (viewModel.isLoading && !viewModel.isProcessingRecording) {
                        modelLoadPrompt
                    }

                    if let whisperError = viewModel.whisperLoadError, viewModel.modelReady {
                        Text("Whisper unavailable: \(whisperError)")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }

                    inputModePicker

                    imagePreview

                    labelsSection

                    temperatureSlider

                    inputControls

                    if viewModel.savedRecordingName != nil || viewModel.framesProcessed > 0 {
                        recordingStatus
                    }

                    if viewModel.isLoading {
                        HStack(spacing: 12) {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 4) {
                                Text(loadingMessage)
                                    .foregroundStyle(.secondary)
                                if let detail = processingProgressDetail {
                                    Text(detail)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }

                    if !viewModel.matches.isEmpty {
                        resultsSection
                    }

                    if !viewModel.frameTimeline.isEmpty {
                        timelineSection
                    }
                }
                .padding()
            }
            .navigationTitle("Content Classifier")
            .task {
                await viewModel.loadStartupModelsIfNeeded()
            }
            .onChange(of: selectedItem) { _, newValue in
                viewModel.handlePhotoSelection(newValue)
            }
            .onChange(of: viewModel.inputMode) { oldValue, newValue in
                viewModel.handleInputModeChange(from: oldValue, to: newValue)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    viewModel.handleAppBecameActive()
                }
            }
            .onChange(of: viewModel.savedRecordingURL) { _, newURL in
                if let newURL {
                    configurePlaybackAudioSession()
                    let player = AVPlayer(url: newURL)
                    player.isMuted = false
                    recordingPlayer = player
                } else {
                    recordingPlayer = nil
                }
            }
        }
    }

    private var loadingMessage: String {
        if viewModel.isProcessingRecording {
            switch viewModel.recordingProcessingPhase {
            case .preparingAudio:
                return "Extracting audio from recording…"
            case .loadingWhisper:
                return "Loading Whisper for transcription…"
            case .processingAudio:
                return "Transcribing and scoring audio…"
            case .processingVideo:
                return "Classifying video frames with MobileCLIP…"
            case .idle:
                return "Processing saved recording…"
            }
        }
        if viewModel.inputMode == .screenCapture, viewModel.isScreenRecording {
            return "System screen recording is active…"
        }
        return viewModel.modelReady ? "Running MobileCLIP…" : "Loading MobileCLIP and Whisper…"
    }

    private var processingProgressDetail: String? {
        guard viewModel.isProcessingRecording else { return nil }

        switch viewModel.recordingProcessingPhase {
        case .processingAudio where viewModel.totalAudioSegmentsExpected > 0:
            return "\(viewModel.audioSegmentsProcessed)/\(viewModel.totalAudioSegmentsExpected) audio windows"
        case .processingVideo where viewModel.totalFramesExpected > 0:
            return "\(viewModel.framesProcessed)/\(viewModel.totalFramesExpected) video frames"
        case .preparingAudio, .loadingWhisper:
            if let size = viewModel.savedRecordingSizeText {
                return "Recording size: \(size)"
            }
            return nil
        default:
            return nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MobileCLIP2-S3")
                .font(.headline)
            Text("Classify educational, commercial, or entertainment content from gallery photos or system-wide screen recordings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var modelLoadPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.isLoading, !viewModel.isProcessingRecording {
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Loading models…")
                            .font(.subheadline.bold())
                        Text("MobileCLIP compiles on first launch (1–2 min). Whisper base may download (~150 MB) the first time.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if viewModel.modelReady {
                            Label("MobileCLIP ready", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        if viewModel.whisperReady {
                            Label("Whisper ready", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else if viewModel.isLoading {
                            Label("Loading Whisper…", systemImage: "arrow.down.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("Models are not loaded yet.")
                    .font(.subheadline.bold())
                Text("MobileCLIP and Whisper load automatically when the app opens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let whisperError = viewModel.whisperLoadError {
                    Text(whisperError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button("Load Models") {
                    Task { await viewModel.loadStartupModelsIfNeeded() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var inputModePicker: some View {
        Picker("Input", selection: $viewModel.inputMode) {
            ForEach(ClassificationInputMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .disabled(viewModel.isProcessingRecording)
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let image = previewImage {
            ZStack(alignment: .bottomLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if viewModel.isProcessingRecording, viewModel.temporaryFramePreview != nil {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Screen sample · \(formatTimestamp(viewModel.temporaryFrameTimestamp))")
                            .font(.caption.bold())
                        Text("Preview · frame \(viewModel.framesProcessed)/\(max(viewModel.totalFramesExpected, 1)) · every \(BroadcastConstants.classificationIntervalSeconds)s")
                            .font(.caption2)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                    .padding(10)
                }
            }
        } else {
            ContentUnavailableView {
                Label(previewPlaceholderTitle, systemImage: previewPlaceholderIcon)
            } description: {
                Text(previewPlaceholderDescription)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                    .foregroundStyle(.quaternary)
            )
        }
    }

    private var previewImage: UIImage? {
        if viewModel.isProcessingRecording, let temporary = viewModel.temporaryFramePreview {
            return temporary
        }
        return viewModel.selectedImage
    }

    private var previewPlaceholderTitle: String {
        viewModel.inputMode == .screenCapture ? "No recording analyzed yet" : "No image yet"
    }

    private var previewPlaceholderIcon: String {
        viewModel.inputMode == .screenCapture ? "record.circle" : "photo"
    }

    private var previewPlaceholderDescription: String {
        if viewModel.inputMode == .screenCapture {
            return "Start a system screen recording, stop it, then the saved video is classified every \(BroadcastConstants.classificationIntervalSeconds) seconds."
        }
        return "Tap Add from Gallery to pick a photo."
    }

    private var labelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Labels · \(viewModel.allPrompts.count) prompts")
                .font(.subheadline.bold())
            VStack(alignment: .leading, spacing: 10) {
                ForEach(viewModel.allPrompts, id: \.self) { label in
                    Label {
                        Text(label)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "tag.fill")
                            .font(.caption)
                    }
                    .foregroundStyle(.primary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var temperatureSlider: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Softmax temperature")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(Int(viewModel.temperature))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $viewModel.temperature, in: 1...200, step: 1)
                .disabled(viewModel.isLoading || viewModel.isProcessingRecording)
        }
    }

    @ViewBuilder
    private var inputControls: some View {
        switch viewModel.inputMode {
        case .gallery:
            galleryButton
        case .screenCapture:
            screenCaptureButton
        }
    }

    private var galleryButton: some View {
        VStack(spacing: 12) {
            PhotosPicker(
                selection: $selectedItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label(
                    viewModel.selectedImage == nil ? "Add from Gallery" : "Change from Gallery",
                    systemImage: "photo.on.rectangle.angled"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isLoading && !viewModel.modelReady)

            if viewModel.selectedImage != nil, viewModel.inputMode == .gallery {
                Button("Run inference") {
                    viewModel.classifySelectedImage()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .disabled(viewModel.isLoading || !viewModel.modelReady)
            }
        }
    }

    private var screenCaptureButton: some View {
        VStack(spacing: 12) {
            if viewModel.isScreenRecording {
                VStack(alignment: .leading, spacing: 12) {
                    Label("System recording active", systemImage: "record.circle")
                        .font(.subheadline.bold())
                        .foregroundStyle(.red)

                    Button(role: .destructive) {
                        viewModel.finishScreenRecording()
                    } label: {
                        Label("Stop and Classify", systemImage: "stop.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            } else if viewModel.isProcessingRecording {
                VStack(alignment: .leading, spacing: 8) {
                    Label(processingPhaseLabel, systemImage: "waveform.and.magnifyingglass")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let size = viewModel.savedRecordingSizeText {
                        Text("Recording size: \(size)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                BroadcastStartButton(viewModel: viewModel)
                    .disabled(!viewModel.modelReady)
            }

            Text("Tap the red record button, confirm the broadcast sheet, then switch apps freely. Tap Stop and Classify to end and analyze, or stop from Control Center.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var processingPhaseLabel: String {
        switch viewModel.recordingProcessingPhase {
        case .preparingAudio:
            return "Extracting audio…"
        case .loadingWhisper:
            return "Loading Whisper…"
        case .processingAudio:
            if viewModel.totalAudioSegmentsExpected > 0 {
                return "Audio \(viewModel.audioSegmentsProcessed)/\(viewModel.totalAudioSegmentsExpected)"
            }
            return "Processing audio…"
        case .processingVideo:
            if viewModel.totalFramesExpected > 0 {
                return "Video \(viewModel.framesProcessed)/\(viewModel.totalFramesExpected)"
            }
            return "Classifying video…"
        case .idle:
            return "Processing saved recording…"
        }
    }

    private var recordingStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let name = viewModel.savedRecordingName {
                Label(name, systemImage: "film")
                    .font(.subheadline)
            }
            if let size = viewModel.savedRecordingSizeText {
                Text("Recording size: \(size)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let recordingPlayer {
                VideoPlayer(player: recordingPlayer)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            if viewModel.recordingFPS > 0 {
                Text(String(format: "%.0f FPS recording", viewModel.recordingFPS))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if viewModel.framesProcessed > 0 {
                Text("\(viewModel.framesProcessed) frames classified")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Per-frame timeline")
                .font(.headline)

            ForEach(viewModel.frameTimeline) { entry in
                HStack(alignment: .center, spacing: 12) {
                    timelineThumbnail(entry.thumbnail, placeholderIcon: "photo")

                    if entry.bottomCropThumbnail != nil {
                        VStack(spacing: 2) {
                            timelineThumbnail(entry.bottomCropThumbnail, placeholderIcon: "crop")
                            Text("Bottom crop")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(formatTimestamp(entry.timestamp))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(entry.label)
                                .font(.caption.bold())
                        }
                        if let videoPrompt = entry.videoMatchedPrompt {
                            Text("Video: \(videoPrompt)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if let matchedPrompt = entry.matchedPrompt {
                            Text(matchedPrompt)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let audioLabel = entry.audioLabel,
                           let audioPrompt = entry.audioMatchedPrompt {
                            Text("Audio (\(audioLabel)): \(audioPrompt)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let tone = entry.audioTone, !tone.isEmpty {
                            Label(tone, systemImage: "waveform.badge.magnifyingglass")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let transcript = entry.audioTranscript, !transcript.isEmpty {
                            Label(transcript, systemImage: "text.quote")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if entry.audioTone == nil, entry.audioLabel != nil {
                            Text("No speech detected")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text(String(format: "%.1f%%", entry.probability * 100))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func configurePlaybackAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
    }

    private func formatTimestamp(_ timestamp: TimeInterval) -> String {
        let totalSeconds = max(0, Int(timestamp))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    @ViewBuilder
    private func timelineThumbnail(_ image: UIImage?, placeholderIcon: String) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: placeholderIcon)
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let top = viewModel.matches.first {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Best match")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(top.label)
                        .font(.title3.bold())
                    if let matchedPrompt = top.matchedPrompt {
                        Text(matchedPrompt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(String(format: "cosine %.3f · %.1f%%", top.score, top.probability * 100))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }

            Text("Categories")
                .font(.headline)

            ForEach(viewModel.matches) { match in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(match.label)
                            .font(.subheadline.bold())
                        if let matchedPrompt = match.matchedPrompt {
                            Text(matchedPrompt)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.1f%%", match.probability * 100))
                            .monospacedDigit()
                            .fontWeight(.medium)
                        Text(String(format: "%.3f", match.score))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            if !viewModel.promptMatches.isEmpty {
                Text("Top prompts")
                    .font(.headline)
                    .padding(.top, 4)

                ForEach(viewModel.promptMatches.prefix(8)) { match in
                    HStack(alignment: .top) {
                        Text(match.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text(String(format: "%.1f%%", match.probability * 100))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
