//
//  MobileCLIPClassifier.swift
//  iamge-detection
//

import CoreML
import CoreVideo
import UIKit

struct ClassificationMatch: Identifiable, Sendable {
    let id: String
    let label: String
    let score: Float
    let probability: Float
    /// Best matching prompt within this category (when label is a category name).
    let matchedPrompt: String?
}

enum ClassifierError: LocalizedError {
    case modelLoadFailed(String)
    case predictionFailed(String)
    case invalidImage
    case emptyLabels

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let message):
            return "Failed to load MobileCLIP model: \(message)"
        case .predictionFailed(let message):
            return "Inference failed: \(message)"
        case .invalidImage:
            return "Could not prepare the image for the model."
        case .emptyLabels:
            return "Enter at least one label."
        }
    }
}

struct ClassificationResult: Sendable {
    /// 3 category-level matches — use for timeline and primary UI.
    let categories: [ClassificationMatch]
    /// All 24 prompt-level scores — use for debug / detail.
    let prompts: [ClassificationMatch]
}

/// Zero-shot classifier using MobileCLIP2-S3 image + text Core ML models.
/// Loads off the main thread — do not mark MainActor-isolated.
final class MobileCLIPClassifier: Sendable {
    static let modelInputSize = 256
    static let embeddingDimension = 768

    static let categories: [ClassificationCategory] = ClassificationCategories.all
    static let audioCategories: [ClassificationCategory] = ClassificationCategories.audioAll
    static let labels: [String] = ClassificationCategories.categoryNames
    static let allPrompts: [String] = ClassificationCategories.allPrompts
    static let audioPrompts: [String] = ClassificationCategories.audioPrompts

    static let defaultLabels: [String] = labels

    private let imageModel: mobileclip2_s3_image
    private let textModel: mobileclip2_s3_text
    private let tokenizer: CLIPTokenizer

    private var cachedPrompts: [String] = []
    private var cachedTextEmbeddings: [[Float]] = []
    private var cachedAudioPrompts: [String] = []
    private var cachedAudioTextEmbeddings: [[Float]] = []

    init() throws {
        tokenizer = try CLIPTokenizer()

        let config = MLModelConfiguration()
        config.computeUnits = .all

        do {
            imageModel = try mobileclip2_s3_image(configuration: config)
            textModel = try mobileclip2_s3_text(configuration: config)
        } catch {
            throw ClassifierError.modelLoadFailed(error.localizedDescription)
        }
    }

    func classify(
        image: UIImage,
        temperature: Float = 100,
        topK: Int? = nil
    ) throws -> ClassificationResult {
        guard let buffers = ImagePreprocessor.modelInputBuffers(from: image, size: Self.modelInputSize),
              !buffers.isEmpty else {
            throw ClassifierError.invalidImage
        }
        return try classify(buffers: buffers, temperature: temperature, topK: topK)
    }

    func classify(
        pixelBuffer: CVPixelBuffer,
        temperature: Float = 100,
        topK: Int? = nil
    ) throws -> ClassificationResult {
        guard let buffers = ImagePreprocessor.modelInputBuffers(from: pixelBuffer, size: Self.modelInputSize),
              !buffers.isEmpty else {
            throw ClassifierError.invalidImage
        }
        return try classify(buffers: buffers, temperature: temperature, topK: topK)
    }

    func classify(
        transcript: String,
        tone: String = "",
        temperature: Float = 100,
        topK: Int? = nil
    ) throws -> ClassificationResult {
        try prepareAudioTextEmbeddings(for: Self.audioPrompts)

        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTone = tone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty || !trimmedTone.isEmpty else {
            return ClassificationResult(categories: [], prompts: [])
        }

        let promptSimilarities: [(prompt: String, similarity: Float)]
        if !trimmedTranscript.isEmpty, Self.isInstructionalTranscript(trimmedTranscript) {
            promptSimilarities = try computePromptSimilarities(
                for: "Spoken content: \(trimmedTranscript)"
            )
        } else if !trimmedTranscript.isEmpty, !trimmedTone.isEmpty {
            let transcriptSimilarities = try computePromptSimilarities(
                for: "Spoken content: \(trimmedTranscript)"
            )
            let toneSimilarities = try computePromptSimilarities(for: "Audio tone: \(trimmedTone)")
            let transcriptWeight: Float = Self.toneSuggestsMusic(trimmedTone) ? 0.25 : 0.4
            let toneWeight: Float = 1 - transcriptWeight
            promptSimilarities = zip(transcriptSimilarities, toneSimilarities).map { left, right in
                (left.prompt, transcriptWeight * left.similarity + toneWeight * right.similarity)
            }
        } else if !trimmedTranscript.isEmpty {
            promptSimilarities = try computePromptSimilarities(
                for: "Spoken content: \(trimmedTranscript)"
            )
        } else {
            promptSimilarities = try computePromptSimilarities(for: "Audio tone: \(trimmedTone)")
        }

        let promptProbabilities = CLIPScoring.softmaxProbabilities(
            similarities: promptSimilarities.map(\.similarity),
            temperature: temperature
        )

        let promptMatches = promptSimilarities.enumerated().map { index, item in
            ClassificationMatch(
                id: item.prompt,
                label: item.prompt,
                score: item.similarity,
                probability: promptProbabilities[index],
                matchedPrompt: nil
            )
        }
        .sorted { $0.probability > $1.probability }

        let categoryMatches = rollUpToCategories(
            promptSimilarities: promptSimilarities,
            categories: Self.audioCategories,
            temperature: temperature
        )

        if let topK {
            return ClassificationResult(
                categories: Array(categoryMatches.prefix(topK)),
                prompts: Array(promptMatches.prefix(topK))
            )
        }

        return ClassificationResult(categories: categoryMatches, prompts: promptMatches)
    }

    static func isInstructionalTranscript(_ transcript: String) -> Bool {
        let words = transcript
            .lowercased()
            .split { $0.isWhitespace || $0.isNewline }
            .map(String.init)
            .filter { !$0.isEmpty }
        guard words.count >= 8 else { return false }

        let uniqueCount = Set(words).count
        let repetitionRatio = Float(uniqueCount) / Float(words.count)
        if words.count >= 4, repetitionRatio < 0.55 {
            return false
        }

        let instructionalKeywords = [
            "explain", "because", "how", "why", "learn", "teach", "lesson", "strategy",
            "framework", "invest", "business", "skill", "mindset", "growth", "audience",
            "youtube", "formula", "step", "means", "should", "tip", "advice", "guide",
        ]
        let joined = words.joined(separator: " ")
        return instructionalKeywords.contains { joined.contains($0) }
    }

    static func toneSuggestsMusic(_ tone: String) -> Bool {
        let lowered = tone.lowercased()
        return lowered.contains("speech-over-music")
            || lowered.contains("music-heavy")
            || lowered.contains("sound-effect")
    }

    private func computePromptSimilarities(for text: String) throws -> [(prompt: String, similarity: Float)] {
        let audioEmbedding = try encodeSingleText(text)
        return zip(Self.audioPrompts, cachedAudioTextEmbeddings).map { prompt, textEmb in
            (prompt: prompt, similarity: CosineSimilarity.score(audioEmbedding, textEmb))
        }
    }

    static func combinedAudioDescription(transcript: String, tone: String) -> String {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTone = tone.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedTranscript.isEmpty {
            return "Spoken content: \(trimmedTranscript)"
        }
        if !trimmedTone.isEmpty {
            return "Audio tone: \(trimmedTone)"
        }
        return ""
    }

    private func classify(
        buffers: [CVPixelBuffer],
        temperature: Float,
        topK: Int?
    ) throws -> ClassificationResult {
        try prepareTextEmbeddings(for: Self.allPrompts)

        let imageEmbeddings = try buffers.map { try encodeImage(from: $0) }

        let promptSimilarities = zip(Self.allPrompts, cachedTextEmbeddings).map { prompt, textEmb in
            let similarity = dualCropSimilarity(imageEmbeddings: imageEmbeddings, textEmbedding: textEmb)
            return (prompt: prompt, similarity: similarity)
        }

        let promptProbabilities = CLIPScoring.softmaxProbabilities(
            similarities: promptSimilarities.map(\.similarity),
            temperature: temperature
        )

        let promptMatches = promptSimilarities.enumerated().map { index, item in
            ClassificationMatch(
                id: item.prompt,
                label: item.prompt,
                score: item.similarity,
                probability: promptProbabilities[index],
                matchedPrompt: nil
            )
        }
        .sorted { $0.probability > $1.probability }

        let categoryMatches = rollUpToCategories(
            promptSimilarities: promptSimilarities,
            categories: Self.categories,
            temperature: temperature
        )

        if let topK {
            return ClassificationResult(
                categories: Array(categoryMatches.prefix(topK)),
                prompts: Array(promptMatches.prefix(topK))
            )
        }

        return ClassificationResult(categories: categoryMatches, prompts: promptMatches)
    }

    /// Tall screenshots: full frame sees talking head + clean bg; caption crop sees on-screen text.
    private func dualCropSimilarity(imageEmbeddings: [[Float]], textEmbedding: [Float]) -> Float {
        guard imageEmbeddings.count == 2 else {
            guard let imageEmbedding = imageEmbeddings.first else { return 0 }
            return CosineSimilarity.score(imageEmbedding, textEmbedding)
        }

        let captionScore = CosineSimilarity.score(imageEmbeddings[0], textEmbedding)
        let fullFrameScore = CosineSimilarity.score(imageEmbeddings[1], textEmbedding)
        return 0.45 * captionScore + 0.55 * fullFrameScore
    }

    private func rollUpToCategories(
        promptSimilarities: [(prompt: String, similarity: Float)],
        categories: [ClassificationCategory],
        temperature: Float
    ) -> [ClassificationMatch] {
        let grouped: [(category: ClassificationCategory, score: Float, bestPrompt: String)] =
            categories.compactMap { category in
                let scores = promptSimilarities
                    .filter { category.prompts.contains($0.prompt) }
                    .sorted { $0.similarity > $1.similarity }
                guard let best = scores.first else { return nil }

                let topScores = scores.prefix(3).map(\.similarity)
                let aggregatedScore = topScores.reduce(0, +) / Float(topScores.count)

                return (category, aggregatedScore, best.prompt)
            }

        let categorySimilarities = grouped.map(\.score)
        let categoryProbabilities = CLIPScoring.softmaxProbabilities(
            similarities: categorySimilarities,
            temperature: temperature
        )

        return grouped.enumerated().map { index, item in
            ClassificationMatch(
                id: item.category.name,
                label: item.category.name,
                score: item.score,
                probability: categoryProbabilities[index],
                matchedPrompt: item.bestPrompt
            )
        }
        .sorted { $0.probability > $1.probability }
    }

    private func prepareTextEmbeddings(for prompts: [String]) throws {
        guard prompts != cachedPrompts else { return }
        cachedPrompts = prompts
        cachedTextEmbeddings = try prompts.map { try encodeSingleText($0) }
    }

    private func prepareAudioTextEmbeddings(for prompts: [String]) throws {
        guard prompts != cachedAudioPrompts else { return }
        cachedAudioPrompts = prompts
        cachedAudioTextEmbeddings = try prompts.map { try encodeSingleText($0) }
    }

    private func encodeImage(from pixelBuffer: CVPixelBuffer) throws -> [Float] {
        do {
            let output = try imageModel.prediction(image: pixelBuffer)
            return CosineSimilarity.l2Normalize(output.final_emb_1.floatArray())
        } catch {
            throw ClassifierError.predictionFailed(error.localizedDescription)
        }
    }

    private func encodeSingleText(_ text: String) throws -> [Float] {
        let tokenIDs = tokenizer.encode_full(text: text)
        let input = try MLMultiArray(shape: [1, 77], dataType: .int32)
        for (index, token) in tokenIDs.enumerated() {
            input[index] = NSNumber(value: token)
        }
        let output = try textModel.prediction(text: input)
        return CosineSimilarity.l2Normalize(output.final_emb_1.floatArray())
    }
}

enum CLIPScoring {
    static func softmaxProbabilities(similarities: [Float], temperature: Float) -> [Float] {
        guard !similarities.isEmpty else { return [] }
        let scale = max(temperature, 1)
        let logits = similarities.map { $0 * scale }
        let maxLogit = logits.max() ?? 0
        let exps = logits.map { exp($0 - maxLogit) }
        let sum = exps.reduce(0, +)
        guard sum > 0 else {
            return Array(repeating: 1 / Float(similarities.count), count: similarities.count)
        }
        return exps.map { $0 / sum }
    }
}
