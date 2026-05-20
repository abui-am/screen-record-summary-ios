//
//  ScreenCaptureOverlayView.swift
//  iamge-detection
//

import SwiftUI

struct ScreenCaptureOverlayView: View {
    let viewModel: ImageClassifierViewModel
    let onStop: () -> Void
    let onResize: (CGSize) -> Void
    let onDrag: (CGSize) -> Void

    @State private var isExpanded = false
    @State private var pulse = false
    @State private var dragTranslation: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            dragHandle

            if isExpanded {
                expandedContent
            } else {
                collapsedContent
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
        .gesture(dragGesture)
        .onChange(of: isExpanded) { _, expanded in
            onResize(expanded ? ScreenCaptureOverlayMetrics.expandedSize : ScreenCaptureOverlayMetrics.collapsedSize)
        }
        .onAppear {
            onResize(ScreenCaptureOverlayMetrics.collapsedSize)
            withAnimation(.easeOut(duration: 1).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }

    private var dragHandle: some View {
        Capsule()
            .fill(.secondary.opacity(0.45))
            .frame(width: 36, height: 4)
            .padding(.bottom, 8)
            .accessibilityLabel("Drag overlay")
    }

    private var collapsedContent: some View {
        HStack(spacing: 10) {
            recordingIndicator

            VStack(alignment: .leading, spacing: 2) {
                Text("Recording screen")
                    .font(.caption.bold())
                elapsedLabel
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)

            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.red, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop and process recording")

            Button {
                isExpanded = true
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Expand overlay")
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                recordingIndicator
                Text("Recording screen")
                    .font(.caption.bold())
                Spacer()
                Button {
                    isExpanded = false
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            elapsedLabel
                .font(.title3.bold())
                .monospacedDigit()

            Text("Recording saves 1 frame per second. Classification runs after you stop.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Text("Stop from Control Center or tap Stop here, then return to classify the saved video.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button(role: .destructive, action: onStop) {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private var elapsedLabel: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(elapsedText(at: context.date))
        }
    }

    private var recordingIndicator: some View {
        ZStack {
            Circle()
                .stroke(Color.red.opacity(0.35), lineWidth: 2)
                .frame(width: 16, height: 16)
                .scaleEffect(pulse ? 1.6 : 1)
                .opacity(pulse ? 0 : 1)

            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
        }
        .accessibilityLabel("Recording")
    }

    private func elapsedText(at date: Date) -> String {
        guard let start = viewModel.recordingStartedAt else { return "00:00" }
        let elapsed = max(0, Int(date.timeIntervalSince(start)))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let delta = CGSize(
                    width: value.translation.width - dragTranslation.width,
                    height: value.translation.height - dragTranslation.height
                )
                dragTranslation = value.translation
                onDrag(delta)
            }
            .onEnded { _ in
                dragTranslation = .zero
            }
    }
}
