//
//  OutputSourceBadge.swift
//  iamge-detection
//

import SwiftUI

enum OutputSource: String, CaseIterable, Identifiable {
    case mobileCLIP = "MobileCLIP"
    case whisper = "Whisper"
    case vision = "Vision"
    case audioTone = "Audio"
    case foundationModels = "Apple Intelligence"
    case stitched = "Stitched"

    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .mobileCLIP: .blue
        case .whisper: .purple
        case .vision: .green
        case .audioTone: .orange
        case .foundationModels: .pink
        case .stitched: .secondary
        }
    }
}

struct SourceBadge: View {
    let source: OutputSource

    var body: some View {
        Text(source.rawValue)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(source.tint.opacity(0.14), in: Capsule())
            .foregroundStyle(source.tint)
    }
}

struct SourceBadgeRow: View {
    let sources: [OutputSource]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(sources) { source in
                SourceBadge(source: source)
            }
        }
    }
}

enum OutputSourceCatalog {
    static func classificationSources(screenRecording: Bool, hasAudioInput: Bool) -> [OutputSource] {
        guard screenRecording else { return [.mobileCLIP] }
        if hasAudioInput {
            return [.mobileCLIP, .whisper]
        }
        return [.mobileCLIP]
    }

    static func segmentLabelSources(hasAudio: Bool) -> [OutputSource] {
        hasAudio ? [.mobileCLIP, .whisper] : [.mobileCLIP]
    }

    static func contentSummarySources(for entry: FrameClassificationSummary) -> [OutputSource] {
        var sources: [OutputSource] = [.mobileCLIP]

        if let summary = entry.contentSummary {
            if summary.contains("On screen:") || summary.contains("Visual:") {
                sources.append(.vision)
            }
            if summary.contains("Spoken:") {
                sources.append(.whisper)
            }
            if summary.contains("Audio:"),
               entry.audioTranscript?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                sources.append(.audioTone)
            }
        }

        return orderedUnique(sources)
    }

    static func recordingSummarySources(isAI: Bool) -> [OutputSource] {
        isAI ? [.foundationModels] : [.stitched, .vision, .whisper, .mobileCLIP]
    }

    private static func orderedUnique(_ sources: [OutputSource]) -> [OutputSource] {
        var seen = Set<OutputSource>()
        return sources.filter { seen.insert($0).inserted }
    }
}
