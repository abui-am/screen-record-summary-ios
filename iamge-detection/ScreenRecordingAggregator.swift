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
    let matchedPrompt: String?
    let videoMatchedPrompt: String?
    let audioMatchedPrompt: String?
    let probability: Float
    let thumbnail: UIImage?
    let bottomCropThumbnail: UIImage?
    let audioTranscript: String?
    let audioTone: String?
    let audioLabel: String?
}

enum ScreenRecordingAggregator {
    static let videoWeight: Float = 0.35
    static let audioWeight: Float = 0.65

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
                probability: probabilities[index],
                matchedPrompt: nil
            )
        }
        .sorted { $0.probability > $1.probability }
    }

    static func mergeVideoAndAudio(
        videoMatches: [ClassificationMatch],
        audioMatches: [ClassificationMatch]?,
        labels: [String],
        temperature: Float,
        transcript: String? = nil,
        audioTone: String? = nil
    ) -> [ClassificationMatch] {
        guard let audioMatches, !audioMatches.isEmpty else {
            return videoMatches
        }

        let weights = fusionWeights(transcript: transcript, audioTone: audioTone)

        let videoScores = Dictionary(uniqueKeysWithValues: videoMatches.map { ($0.label, $0.score) })
        let audioScores = Dictionary(uniqueKeysWithValues: audioMatches.map { ($0.label, $0.score) })

        let blendedSimilarities = labels.map { label in
            let videoScore = videoScores[label] ?? 0
            let audioScore = audioScores[label] ?? 0
            return weights.video * videoScore + weights.audio * audioScore
        }

        let probabilities = CLIPScoring.softmaxProbabilities(
            similarities: blendedSimilarities,
            temperature: temperature
        )

        let videoTop = videoMatches.first?.label
        let audioTop = audioMatches.first?.label

        return labels.enumerated().map { index, label in
            let videoMatch = videoMatches.first { $0.label == label }
            let audioMatch = audioMatches.first { $0.label == label }
            let preferVideoPrompt = videoTop == "Entertainment content"
                && audioTop == "Educational content"
                && !MobileCLIPClassifier.isInstructionalTranscript(transcript ?? "")
            let matchedPrompt = preferVideoPrompt
                ? videoMatch?.matchedPrompt
                : (audioMatch?.matchedPrompt ?? videoMatch?.matchedPrompt)
            return ClassificationMatch(
                id: label,
                label: label,
                score: blendedSimilarities[index],
                probability: probabilities[index],
                matchedPrompt: matchedPrompt
            )
        }
        .sorted { $0.probability > $1.probability }
    }

    static func fusionWeights(transcript: String?, audioTone: String?) -> (video: Float, audio: Float) {
        let trimmed = transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if MobileCLIPClassifier.isInstructionalTranscript(trimmed) {
            return (0.25, 0.75)
        }
        if MobileCLIPClassifier.toneSuggestsMusic(audioTone ?? "") || trimmed.split(whereSeparator: \.isWhitespace).count < 8 {
            return (0.62, 0.38)
        }
        return (videoWeight, audioWeight)
    }

    static func timeline(
        frames: [(
            timestamp: TimeInterval,
            matches: [ClassificationMatch],
            thumbnail: UIImage?,
            bottomCropThumbnail: UIImage?,
            audioTranscript: String?,
            audioTone: String?,
            audioLabel: String?,
            videoMatchedPrompt: String?,
            audioMatchedPrompt: String?
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
                matchedPrompt: top.matchedPrompt,
                videoMatchedPrompt: frame.videoMatchedPrompt,
                audioMatchedPrompt: frame.audioMatchedPrompt,
                probability: top.probability,
                thumbnail: frame.thumbnail,
                bottomCropThumbnail: frame.bottomCropThumbnail,
                audioTranscript: frame.audioTranscript,
                audioTone: frame.audioTone,
                audioLabel: frame.audioLabel
            )
        }

        let interval = max(1, BroadcastConstants.classificationIntervalSeconds)
        if perFrameSummaries.count <= interval * 2 {
            return perFrameSummaries
        }

        let grouped = Dictionary(grouping: perFrameSummaries) { summary in
            Int(summary.timestamp) / interval * interval
        }

        return grouped.keys.sorted().compactMap { bucketStart in
            guard let bucket = grouped[bucketStart], !bucket.isEmpty else { return nil }
            let labelCounts = Dictionary(grouping: bucket, by: \.label).mapValues(\.count)
            guard let winningLabel = labelCounts.max(by: { $0.value < $1.value })?.key else { return nil }
            let matching = bucket.filter { $0.label == winningLabel }
            let averageProbability = matching.map(\.probability).reduce(0, +) / Float(matching.count)
            return FrameClassificationSummary(
                id: bucketStart,
                timestamp: TimeInterval(bucketStart),
                label: winningLabel,
                matchedPrompt: matching.first?.matchedPrompt,
                videoMatchedPrompt: matching.first?.videoMatchedPrompt ?? bucket.first?.videoMatchedPrompt,
                audioMatchedPrompt: matching.first?.audioMatchedPrompt ?? bucket.first?.audioMatchedPrompt,
                probability: averageProbability,
                thumbnail: matching.first?.thumbnail ?? bucket.first?.thumbnail,
                bottomCropThumbnail: matching.first?.bottomCropThumbnail ?? bucket.first?.bottomCropThumbnail,
                audioTranscript: matching.first?.audioTranscript ?? bucket.first?.audioTranscript,
                audioTone: matching.first?.audioTone ?? bucket.first?.audioTone,
                audioLabel: matching.first?.audioLabel ?? bucket.first?.audioLabel
            )
        }
    }
}
