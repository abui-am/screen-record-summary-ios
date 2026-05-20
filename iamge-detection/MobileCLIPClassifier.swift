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

/// Zero-shot classifier using MobileCLIP2-S3 image + text Core ML models.
/// Loads off the main thread — do not mark MainActor-isolated.
final class MobileCLIPClassifier: Sendable {
    static let modelInputSize = 256
    static let embeddingDimension = 768
    static let labels: [String] = [
        "educational content",
        "commercial content",
        "entertainment content",
    ]

    /// Backward-compatible alias for call sites using the old name.
    static let defaultLabels: [String] = labels

    private let imageModel: mobileclip2_s3_image
    private let textModel: mobileclip2_s3_text
    private let tokenizer: CLIPTokenizer

    private var cachedLabels: [String] = []
    private var cachedPromptVersion: Int = -1
    private var cachedTextEmbeddings: [[Float]] = []

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
        labels: [String] = MobileCLIPClassifier.labels,
        temperature: Float = 100,
        topK: Int? = nil
    ) throws -> [ClassificationMatch] {
        guard let buffers = ImagePreprocessor.modelInputBuffers(from: image, size: Self.modelInputSize),
              !buffers.isEmpty else {
            throw ClassifierError.invalidImage
        }
        return try classify(buffers: buffers, labels: labels, temperature: temperature, topK: topK)
    }

    func classify(
        pixelBuffer: CVPixelBuffer,
        labels: [String] = MobileCLIPClassifier.labels,
        temperature: Float = 100,
        topK: Int? = nil
    ) throws -> [ClassificationMatch] {
        guard let buffers = ImagePreprocessor.modelInputBuffers(from: pixelBuffer, size: Self.modelInputSize),
              !buffers.isEmpty else {
            throw ClassifierError.invalidImage
        }
        return try classify(buffers: buffers, labels: labels, temperature: temperature, topK: topK)
    }

    private func classify(
        buffers: [CVPixelBuffer],
        labels: [String],
        temperature: Float,
        topK: Int?
    ) throws -> [ClassificationMatch] {
        let trimmed = labels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !trimmed.isEmpty else { throw ClassifierError.emptyLabels }

        try prepareTextEmbeddings(for: trimmed)

        let embeddings = try buffers.map { try encodeImage(from: $0) }
        let fusedEmbedding: [Float]
        if embeddings.count == 2 {
            // Tall screenshot: [bottom crop, full letterbox] — caption/metadata lives in bottom crop.
            fusedEmbedding = CosineSimilarity.weightedAverage(embeddings, weights: [0.65, 0.35])
        } else {
            fusedEmbedding = CosineSimilarity.average(embeddings)
        }
        let imageEmbedding = CosineSimilarity.l2Normalize(fusedEmbedding)

        let similarities = zip(trimmed, cachedTextEmbeddings).map { label, textEmb in
            (label: label, similarity: CosineSimilarity.score(imageEmbedding, textEmb))
        }

        let probabilities = CLIPScoring.softmaxProbabilities(
            similarities: similarities.map(\.similarity),
            temperature: temperature
        )

        let matches = similarities.enumerated().map { index, item in
            ClassificationMatch(
                id: item.label,
                label: item.label,
                score: item.similarity,
                probability: probabilities[index]
            )
        }

        let sorted = matches.sorted { $0.probability > $1.probability }
        if let topK {
            return Array(sorted.prefix(topK))
        }
        return sorted
    }

    private func prepareTextEmbeddings(for labels: [String]) throws {
        let promptVersion = CLIPLabelPrompts.version
        guard labels != cachedLabels || promptVersion != cachedPromptVersion else { return }
        cachedLabels = labels
        cachedPromptVersion = promptVersion
        cachedTextEmbeddings = try encodeTexts(labels)
    }

    private func encodeImage(from pixelBuffer: CVPixelBuffer) throws -> [Float] {
        do {
            let output = try imageModel.prediction(image: pixelBuffer)
            return CosineSimilarity.l2Normalize(output.final_emb_1.floatArray())
        } catch {
            throw ClassifierError.predictionFailed(error.localizedDescription)
        }
    }

    private func encodeTexts(_ labels: [String]) throws -> [[Float]] {
        try labels.map { label in
            let prompts = CLIPLabelPrompts.prompts(for: label)
            guard !prompts.isEmpty else {
                throw ClassifierError.emptyLabels
            }
            let embeddings = try prompts.map { try encodeSingleText($0) }
            return CosineSimilarity.l2Normalize(CosineSimilarity.average(embeddings))
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
    /// Softmax over cosine similarities scaled by temperature (CLIP logit scale, default 100).
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
