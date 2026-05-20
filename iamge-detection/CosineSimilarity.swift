//
//  CosineSimilarity.swift
//  iamge-detection
//

import Foundation

enum CosineSimilarity {
    /// Cosine similarity between two equal-length vectors (higher = more similar).
    static func score(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dot: Float = 0
        var magA: Float = 0
        var magB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            magA += a[i] * a[i]
            magB += b[i] * b[i]
        }

        let denom = (magA.squareRoot() * magB.squareRoot())
        guard denom > 0 else { return 0 }
        return dot / denom
    }

    static func l2Normalize(_ vector: [Float]) -> [Float] {
        var mag: Float = 0
        for v in vector { mag += v * v }
        let norm = mag.squareRoot()
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }

    static func average(_ vectors: [[Float]]) -> [Float] {
        guard let first = vectors.first else { return [] }
        var sum = [Float](repeating: 0, count: first.count)
        for vector in vectors {
            guard vector.count == first.count else { continue }
            for index in 0..<first.count {
                sum[index] += vector[index]
            }
        }
        let count = Float(vectors.count)
        guard count > 0 else { return sum }
        return sum.map { $0 / count }
    }

    /// Weighted mean of embeddings (e.g. favor bottom-caption crop on tall screenshots).
    static func weightedAverage(_ vectors: [[Float]], weights: [Float]) -> [Float] {
        guard let first = vectors.first, vectors.count == weights.count else {
            return average(vectors)
        }

        var sum = [Float](repeating: 0, count: first.count)
        var weightSum: Float = 0
        for (vector, weight) in zip(vectors, weights) {
            guard vector.count == first.count, weight > 0 else { continue }
            for index in 0..<first.count {
                sum[index] += vector[index] * weight
            }
            weightSum += weight
        }

        guard weightSum > 0 else { return sum }
        return sum.map { $0 / weightSum }
    }
}
