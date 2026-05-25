//
//  ScreenRecordingAudioToneAnalyzer.swift
//  iamge-detection
//

import Accelerate
import Foundation

struct AudioToneAnalysis: Sendable {
    let description: String
    let energy: String
    let character: String
    let pace: String?
}

enum ScreenRecordingAudioToneAnalyzer {
    static func analyze(
        wavURL: URL,
        transcript: String = "",
        durationSeconds: TimeInterval = TimeInterval(BroadcastConstants.classificationIntervalSeconds)
    ) -> AudioToneAnalysis {
        guard let samples = loadPCMSamples(from: wavURL), !samples.isEmpty else {
            return AudioToneAnalysis(
                description: "silent or unreadable audio",
                energy: "silent",
                character: "silent",
                pace: nil
            )
        }

        let rms = rootMeanSquare(samples)
        let zcr = zeroCrossingRate(samples)
        let brightness = highFrequencyEnergy(samples)

        let energy = energyLabel(rms: rms)
        let character = characterLabel(rms: rms, zcr: zcr, brightness: brightness, hasTranscript: !transcript.isEmpty)
        let pace = paceLabel(transcript: transcript, durationSeconds: durationSeconds)

        var parts = ["\(energy) \(character) audio"]
        if let pace {
            parts.append(pace)
        }
        if !transcript.isEmpty {
            parts.append("with spoken words")
        } else if character.contains("music") {
            parts.append("without clear speech")
        }

        return AudioToneAnalysis(
            description: parts.joined(separator: ", "),
            energy: energy,
            character: character,
            pace: pace
        )
    }

    private static func loadPCMSamples(from wavURL: URL) -> [Float]? {
        guard let data = try? Data(contentsOf: wavURL), data.count > 44 else { return nil }

        let headerSize = 44
        let pcmData = data.subdata(in: headerSize ..< data.count)
        let sampleCount = pcmData.count / MemoryLayout<Int16>.size
        guard sampleCount > 0 else { return nil }

        return pcmData.withUnsafeBytes { rawBuffer in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            return (0 ..< sampleCount).map { index in
                Float(int16Buffer[index]) / Float(Int16.max)
            }
        }
    }

    private static func rootMeanSquare(_ samples: [Float]) -> Float {
        var rms: Float = 0
        samples.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            vDSP_rmsqv(base, 1, &rms, vDSP_Length(buffer.count))
        }
        return rms
    }

    private static func zeroCrossingRate(_ samples: [Float]) -> Float {
        guard samples.count > 1 else { return 0 }
        var crossings = 0
        for index in 1 ..< samples.count {
            let previous = samples[index - 1]
            let current = samples[index]
            if (previous >= 0 && current < 0) || (previous < 0 && current >= 0) {
                crossings += 1
            }
        }
        return Float(crossings) / Float(samples.count - 1)
    }

    private static func highFrequencyEnergy(_ samples: [Float]) -> Float {
        guard samples.count > 1 else { return 0 }
        var total: Float = 0
        for index in 1 ..< samples.count {
            total += abs(samples[index] - samples[index - 1])
        }
        return total / Float(samples.count - 1)
    }

    private static func energyLabel(rms: Float) -> String {
        switch rms {
        case ..<0.015:
            return "quiet"
        case ..<0.05:
            return "calm"
        case ..<0.12:
            return "moderate-energy"
        default:
            return "energetic loud"
        }
    }

    private static func characterLabel(
        rms: Float,
        zcr: Float,
        brightness: Float,
        hasTranscript: Bool
    ) -> String {
        if rms < 0.015 {
            return "silent"
        }

        let speechLike = zcr > 0.08
        let musicLike = brightness > 0.03 && zcr < 0.12

        if hasTranscript || speechLike {
            if musicLike {
                return "speech-over-music"
            }
            return "spoken"
        }

        if musicLike {
            return "music-heavy"
        }

        if brightness > 0.02 {
            return "sound-effect or mixed"
        }

        return "ambient"
    }

    private static func paceLabel(transcript: String, durationSeconds: TimeInterval) -> String? {
        let words = transcript
            .split { $0.isWhitespace || $0.isNewline }
            .filter { !$0.isEmpty }
        guard !words.isEmpty, durationSeconds > 0 else { return nil }

        let wordsPerSecond = Float(words.count) / Float(durationSeconds)
        switch wordsPerSecond {
        case ..<1.2:
            return "slow deliberate delivery"
        case ..<2.4:
            return "normal conversational delivery"
        default:
            return "fast urgent delivery"
        }
    }
}
