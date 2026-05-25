//
//  RecordingFoundationSummarizer.swift
//  iamge-detection
//

import Foundation
import FoundationModels

enum FoundationSummarizerAvailability: Equatable, Sendable {
    case available
    case requiresIOS26
    case unavailable(String)

    var statusMessage: String? {
        switch self {
        case .available:
            return nil
        case .requiresIOS26:
            return "Apple Intelligence summaries require iOS 26."
        case .unavailable(let reason):
            return reason
        }
    }
}

enum SummarizerError: LocalizedError {
    case requiresIOS26
    case modelUnavailable(String)
    case emptyInput

    var errorDescription: String? {
        switch self {
        case .requiresIOS26:
            return "Apple Intelligence summaries require iOS 26."
        case .modelUnavailable(let reason):
            return reason
        case .emptyInput:
            return "Not enough content to summarize."
        }
    }
}

enum RecordingFoundationSummarizer {
    static func availability() -> FoundationSummarizerAvailability {
        guard #available(iOS 26, *) else {
            return .requiresIOS26
        }
        return FoundationSummarizerService.availability()
    }

    static func summarizeRecording(
        timeline: [FrameClassificationSummary],
        overallCategory: String?
    ) async throws -> String {
        guard #available(iOS 26, *) else {
            throw SummarizerError.requiresIOS26
        }
        return try await FoundationSummarizerService.summarizeRecording(
            timeline: timeline,
            overallCategory: overallCategory
        )
    }
}

@available(iOS 26, *)
private enum FoundationSummarizerService {
    private static let instructions = """
        You summarize screen recordings of short-form social video (TikTok, YouTube Shorts, Instagram Reels).
        Use only the provided segment notes. Do not invent usernames, brands, or topics that are not supported by the input.
        Write clear, factual prose in 2-4 sentences for a full recording, or 1 sentence for a chunk of segments.
        """

    static func availability() -> FoundationSummarizerAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable("This device does not support Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Turn on Apple Intelligence in Settings to generate summaries.")
        case .unavailable(.modelNotReady):
            return .unavailable("The on-device language model is still preparing. Try again shortly.")
        case .unavailable:
            return .unavailable("Apple Intelligence is unavailable right now.")
        @unknown default:
            return .unavailable("Apple Intelligence is unavailable right now.")
        }
    }

    static func summarizeRecording(
        timeline: [FrameClassificationSummary],
        overallCategory: String?
    ) async throws -> String {
        guard availability() == .available else {
            throw SummarizerError.modelUnavailable(availability().statusMessage ?? "Model unavailable.")
        }

        let segmentLines = buildSegmentLines(from: timeline)
        guard !segmentLines.isEmpty else {
            throw SummarizerError.emptyInput
        }

        let chunks = chunkLines(segmentLines, maxCharacters: 2_800)
        var chunkSummaries: [String] = []

        for chunk in chunks {
            let summary = try await summarizeChunk(
                chunk,
                overallCategory: overallCategory,
                isFinalPass: chunks.count == 1
            )
            if !summary.isEmpty {
                chunkSummaries.append(summary)
            }
        }

        guard !chunkSummaries.isEmpty else {
            throw SummarizerError.emptyInput
        }

        if chunkSummaries.count == 1 {
            return chunkSummaries[0]
        }

        let mergePrompt = """
        Combine these partial summaries of one screen recording into one cohesive 2-4 sentence overview.
        Partial summaries:
        \(chunkSummaries.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
        """
        return try await respond(prompt: mergePrompt)
    }

    private static func summarizeChunk(
        _ lines: [String],
        overallCategory: String?,
        isFinalPass: Bool
    ) async throws -> String {
        let categoryLine = overallCategory.map { "Overall classification: \($0)\n" } ?? ""
        let prompt: String
        if isFinalPass {
            prompt = """
            \(categoryLine)Summarize what the user watched in this screen recording based on these time-stamped segment notes:

            \(lines.joined(separator: "\n"))
            """
        } else {
            prompt = """
            \(categoryLine)Summarize this portion of a screen recording in 1-2 sentences:

            \(lines.joined(separator: "\n"))
            """
        }
        return try await respond(prompt: prompt)
    }

    private static func respond(prompt: String) async throws -> String {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func buildSegmentLines(from timeline: [FrameClassificationSummary]) -> [String] {
        timeline.compactMap { entry in
            let timestamp = formatTimestamp(entry.timestamp)
            if let summary = entry.contentSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                return "\(timestamp) — \(summary)"
            }

            var parts: [String] = [entry.label]
            if let transcript = entry.audioTranscript?.trimmingCharacters(in: .whitespacesAndNewlines), !transcript.isEmpty {
                parts.append("spoken: \(truncate(transcript, limit: 120))")
            }
            if let prompt = entry.videoMatchedPrompt ?? entry.matchedPrompt {
                parts.append("visual: \(truncate(prompt, limit: 100))")
            }
            guard parts.count > 1 else { return "\(timestamp) — \(parts[0])" }
            return "\(timestamp) — \(parts.joined(separator: "; "))"
        }
    }

    private static func chunkLines(_ lines: [String], maxCharacters: Int) -> [[String]] {
        guard !lines.isEmpty else { return [] }

        var chunks: [[String]] = []
        var current: [String] = []
        var currentCount = 0

        for line in lines {
            let added = current.isEmpty ? line.count : line.count + 1
            if currentCount + added > maxCharacters, !current.isEmpty {
                chunks.append(current)
                current = [line]
                currentCount = line.count
            } else {
                current.append(line)
                currentCount += added
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    private static func formatTimestamp(_ timestamp: TimeInterval) -> String {
        let totalSeconds = max(0, Int(timestamp))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private static func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let index = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<index]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
