//
//  ScreenRecordingAggregator.swift
//  iamge-detection
//

import Foundation
import UIKit

struct FrameClassificationSummary: Identifiable {
    let id: Int
    let timestamp: TimeInterval
    let label: String
    let probability: Float
    let thumbnail: UIImage?
    let bottomCropThumbnail: UIImage?
}

enum ScreenRecordingAggregator {
    static func aggregate(
        frameResults: [[ClassificationMatch]],
        labels: [String],
        temperature: Float
    ) -> [ClassificationMatch] {
        guard !frameResults.isEmpty else { return [] }

        var summedScores = Dictionary(uniqueKeysWithValues: labels.map { ($0, Float.zero) })
        for results in frameResults {
            for match in results {
                summedScores[match.label, default: 0] += match.score
            }
        }

        let frameCount = Float(frameResults.count)
        let averagedSimilarities = labels.map { label in
            (summedScores[label] ?? 0) / frameCount
        }

        let probabilities = CLIPScoring.softmaxProbabilities(
            similarities: averagedSimilarities,
            temperature: temperature
        )

        return labels.enumerated().map { index, label in
            ClassificationMatch(
                id: label,
                label: label,
                score: averagedSimilarities[index],
                probability: probabilities[index]
            )
        }
        .sorted { $0.probability > $1.probability }
    }

    static func timeline(
        frames: [(
            timestamp: TimeInterval,
            matches: [ClassificationMatch],
            thumbnail: UIImage?,
            bottomCropThumbnail: UIImage?
        )],
        fps: Float
    ) -> [FrameClassificationSummary] {
        guard !frames.isEmpty else { return [] }

        let perFrameSummaries = frames.enumerated().compactMap { index, frame -> FrameClassificationSummary? in
            guard let top = frame.matches.first else { return nil }
            return FrameClassificationSummary(
                id: index,
                timestamp: frame.timestamp,
                label: top.label,
                probability: top.probability,
                thumbnail: frame.thumbnail,
                bottomCropThumbnail: frame.bottomCropThumbnail
            )
        }

        // Keep the UI readable for long recordings by bucketing to one entry per second.
        if perFrameSummaries.count <= Int(max(fps, 1) * 2) {
            return perFrameSummaries
        }

        let grouped = Dictionary(grouping: perFrameSummaries) { summary in
            Int(summary.timestamp)
        }

        return grouped.keys.sorted().compactMap { second in
            guard let bucket = grouped[second], !bucket.isEmpty else { return nil }
            let labelCounts = Dictionary(grouping: bucket, by: \.label).mapValues(\.count)
            guard let winningLabel = labelCounts.max(by: { $0.value < $1.value })?.key else { return nil }
            let matching = bucket.filter { $0.label == winningLabel }
            let averageProbability = matching.map(\.probability).reduce(0, +) / Float(matching.count)
            return FrameClassificationSummary(
                id: second,
                timestamp: TimeInterval(second),
                label: winningLabel,
                probability: averageProbability,
                thumbnail: matching.first?.thumbnail ?? bucket.first?.thumbnail,
                bottomCropThumbnail: matching.first?.bottomCropThumbnail ?? bucket.first?.bottomCropThumbnail
            )
        }
    }
}
