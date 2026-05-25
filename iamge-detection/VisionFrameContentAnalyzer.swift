//
//  VisionFrameContentAnalyzer.swift
//  iamge-detection
//

import CoreVideo
import Foundation
import Vision

struct VisionFrameAnalysis: Sendable {
    let onScreenText: String
    let sceneHints: [String]
}

enum VisionFrameContentAnalyzer {
    static func analyze(pixelBuffer: CVPixelBuffer) -> VisionFrameAnalysis {
        VisionFrameAnalysis(
            onScreenText: recognizeText(in: pixelBuffer),
            sceneHints: classifyScenes(in: pixelBuffer)
        )
    }

    private static func recognizeText(in pixelBuffer: CVPixelBuffer) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }

        let lines = (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first?.string
        }

        return normalizeText(lines.joined(separator: " "))
    }

    private static func classifyScenes(in pixelBuffer: CVPixelBuffer) -> [String] {
        let request = VNClassifyImageRequest()

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        return (request.results ?? [])
            .filter { $0.confidence >= 0.15 }
            .sorted { $0.confidence > $1.confidence }
            .prefix(3)
            .map(\.identifier)
            .map(humanizeSceneLabel)
    }

    private static func normalizeText(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func humanizeSceneLabel(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }
}

enum ScreenContentSummaryBuilder {
    static func segmentSummary(
        label: String,
        onScreenText: String,
        sceneHints: [String],
        transcript: String?,
        audioTone: String?
    ) -> String? {
        var parts: [String] = []

        let category = label
            .replacingOccurrences(of: " content", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !category.isEmpty {
            parts.append(category)
        }

        let screen = onScreenText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !screen.isEmpty {
            parts.append("On screen: \(truncate(screen, limit: 160))")
        }

        let spoken = transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !spoken.isEmpty {
            parts.append("Spoken: \(truncate(spoken, limit: 160))")
        } else if let audioTone {
            let trimmedTone = audioTone.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTone.isEmpty, trimmedTone != "silent or unreadable audio" {
                parts.append("Audio: \(truncate(trimmedTone, limit: 80))")
            }
        }

        if screen.isEmpty, spoken.isEmpty, !sceneHints.isEmpty {
            parts.append("Visual: \(sceneHints.prefix(2).joined(separator: ", "))")
        }

        guard parts.count > 1 || !screen.isEmpty || !spoken.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    static func recordingSummary(from segments: [String]) -> String? {
        let unique = orderedUnique(segments.filter { !$0.isEmpty })
        guard !unique.isEmpty else { return nil }

        if unique.count == 1 {
            return unique[0]
        }

        let preview = unique.prefix(4).joined(separator: "\n")
        if unique.count <= 4 {
            return preview
        }
        return preview + "\n… and \(unique.count - 4) more segments"
    }

    static func mergeSegmentSummaries(_ summaries: [String]) -> String? {
        let cleaned = summaries.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }
        return cleaned.max(by: { $0.count < $1.count })
    }

    private static func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let index = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<index]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for value in values where seen.insert(value).inserted {
            ordered.append(value)
        }
        return ordered
    }
}
