//
//  ContentView.swift
//  iamge-detection
//

import PhotosUI
import SwiftUI

struct ContentView: View {
    @State private var viewModel = ImageClassifierViewModel()
    @State private var selectedItem: PhotosPickerItem?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if !viewModel.modelReady {
                        modelLoadPrompt
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
                                if viewModel.isProcessingRecording, viewModel.totalFramesExpected > 0 {
                                    Text("\(viewModel.framesProcessed)/\(viewModel.totalFramesExpected) frames")
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
                await viewModel.loadModelIfNeeded()
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
        }
    }

    private var loadingMessage: String {
        if viewModel.isProcessingRecording {
            return "Processing saved recording with MobileCLIP…"
        }
        if viewModel.inputMode == .screenCapture, viewModel.isScreenRecording {
            return "System screen recording is active…"
        }
        return viewModel.modelReady ? "Running MobileCLIP…" : "Loading models…"
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
                        Text("Loading MobileCLIP models…")
                            .font(.subheadline.bold())
                        Text("First launch on device can take 1–2 minutes while Core ML compiles.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Models are not loaded yet.")
                    .font(.subheadline.bold())
                Text("Models load automatically when the app opens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Load Models") {
                    Task { await viewModel.loadModelIfNeeded() }
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
                        Text("1 FPS preview · frame \(viewModel.framesProcessed)/\(max(viewModel.totalFramesExpected, 1))")
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
            return "Start a system screen recording, stop it, then the saved video is classified at 1 frame per second."
        }
        return "Tap Add from Gallery to pick a photo."
    }

    private var labelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Categories")
                .font(.subheadline.bold())
            VStack(alignment: .leading, spacing: 6) {
                ForEach(viewModel.classificationLabels, id: \.self) { label in
                    Label(label, systemImage: "tag.fill")
                        .font(.subheadline)
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
                Label("Processing saved recording…", systemImage: "waveform.and.magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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

    private var recordingStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let name = viewModel.savedRecordingName {
                Label(name, systemImage: "film")
                    .font(.subheadline)
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
                                .lineLimit(2)
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
                        .font(.title2.bold())
                    Text(String(format: "cosine %.3f · %.1f%%", top.score, top.probability * 100))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }

            Text("All scores")
                .font(.headline)

            ForEach(viewModel.matches) { match in
                HStack(alignment: .firstTextBaseline) {
                    Text(match.label)
                        .lineLimit(2)
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
        }
    }
}

#Preview {
    ContentView()
}
