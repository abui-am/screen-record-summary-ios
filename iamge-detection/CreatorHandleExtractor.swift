//
//  CreatorHandleExtractor.swift
//  iamge-detection
//

import CoreVideo
import Foundation
import Vision

struct CreatorHandleResult: Sendable {
    let handle: String?
    let confidence: Float
    let rawCandidates: [String]
}

enum CreatorHandleExtractor {
    private static let handlePattern = /@([A-Za-z0-9._]{2,30})/
    private static let bareHandlePattern = /^[A-Za-z0-9._]{2,30}$/
    private static let penalizedTerms = [
        "follow", "live", "promoted", "sponsored", "views", "likes", "share", "comment",
    ]

    static func extract(from pixelBuffer: CVPixelBuffer) -> CreatorHandleResult {
        if let overlay = ImagePreprocessor.overlayCrop(from: pixelBuffer) {
            let overlayResult = extract(from: overlay, preferOverlayPosition: true)
            if overlayResult.handle != nil {
                return overlayResult
            }
        }

        return extract(from: pixelBuffer, preferOverlayPosition: false)
    }

    private static func extract(from pixelBuffer: CVPixelBuffer, preferOverlayPosition: Bool) -> CreatorHandleResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return CreatorHandleResult(handle: nil, confidence: 0, rawCandidates: [])
        }

        let observations = request.results ?? []
        var candidates: [(handle: String, score: Float)] = []

        for observation in observations {
            guard let text = observation.topCandidates(1).first?.string else { continue }
            let confidence = observation.confidence
            let box = observation.boundingBox

            for match in text.matches(of: handlePattern) {
                let handle = normalizeHandle(String(match.1))
                guard isPlausibleHandle(handle) else { continue }
                let score = candidateScore(
                    handle: handle,
                    confidence: confidence,
                    boundingBox: box,
                    preferOverlayPosition: preferOverlayPosition
                )
                candidates.append((handle, score))
            }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("#") { continue }
            if trimmed.count <= 30,
               trimmed.wholeMatch(of: bareHandlePattern) != nil,
               !trimmed.contains(" ") {
                let handle = normalizeHandle(trimmed)
                guard isPlausibleHandle(handle) else { continue }
                let score = candidateScore(
                    handle: handle,
                    confidence: confidence,
                    boundingBox: box,
                    preferOverlayPosition: preferOverlayPosition
                ) * 0.85
                candidates.append((handle, score))
            }
        }

        let rawCandidates = orderedUnique(candidates.map(\.handle))
        guard let best = candidates.max(by: { $0.score < $1.score }) else {
            return CreatorHandleResult(handle: nil, confidence: 0, rawCandidates: rawCandidates)
        }

        return CreatorHandleResult(
            handle: best.handle,
            confidence: best.score,
            rawCandidates: rawCandidates
        )
    }

    private static func normalizeHandle(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("@") {
            return trimmed
        }
        return "@\(trimmed)"
    }

    private static func isPlausibleHandle(_ handle: String) -> Bool {
        let username = handle.dropFirst()
        guard username.count >= 2, username.count <= 30 else { return false }

        let lowered = handle.lowercased()
        if penalizedTerms.contains(where: { lowered.contains($0) }) {
            return false
        }
        if username.allSatisfy(\.isNumber) {
            return false
        }
        if handle.contains("#") {
            return false
        }
        return true
    }

    private static func candidateScore(
        handle: String,
        confidence: Float,
        boundingBox: CGRect,
        preferOverlayPosition: Bool
    ) -> Float {
        var score = confidence

        if preferOverlayPosition {
            let leftBias = Float(1 - boundingBox.minX)
            let bottomBias = Float(1 - boundingBox.minY)
            score *= (0.5 + 0.25 * leftBias + 0.25 * bottomBias)
        }

        let lowered = handle.lowercased()
        if lowered.hasSuffix(".com") || lowered.contains("http") {
            score *= 0.2
        }

        return score
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
