//
//  ScreenRecordingAudioExtractor.swift
//  iamge-detection
//

import AVFoundation
import Foundation

struct ScreenRecordingAudioSegment: Sendable {
    let timestamp: TimeInterval
    let wavURL: URL
}

enum ScreenRecordingAudioExtractor {
    enum ExtractionError: LocalizedError {
        case unreadableAudio
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .unreadableAudio:
                return "Could not read audio from the saved screen recording."
            case .exportFailed:
                return "Could not export an audio segment for transcription."
            }
        }
    }

    private static let whisperSampleRate = 16_000
    private static let windowDuration = TimeInterval(BroadcastConstants.classificationIntervalSeconds)

    static func hasAudioTrack(in videoURL: URL) async -> Bool {
        let asset = AVURLAsset(url: videoURL)
        let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        return !tracks.isEmpty
    }

    static func exportClassificationWindows(from videoURL: URL) async throws -> [ScreenRecordingAudioSegment] {
        let asset = AVURLAsset(url: videoURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            return []
        }

        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw ExtractionError.unreadableAudio
        }

        let timestamps = classificationTimestamps(until: durationSeconds)
        guard !timestamps.isEmpty else { return [] }

        var segments: [ScreenRecordingAudioSegment] = []
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("screen-recording-audio", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        for timestamp in timestamps {
            let remaining = max(0, durationSeconds - timestamp)
            let segmentDuration = min(windowDuration, remaining)
            guard segmentDuration > 0.1 else { continue }

            let outputURL = tempDirectory
                .appendingPathComponent("audio-\(Int(timestamp * 1000)).wav")

            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }

            let exported = try exportWAVSegment(
                asset: asset,
                track: track,
                start: timestamp,
                duration: segmentDuration,
                outputURL: outputURL
            )
            if exported {
                segments.append(ScreenRecordingAudioSegment(timestamp: timestamp, wavURL: outputURL))
            }
        }

        return segments
    }

    static func classificationTimestamps(until durationSeconds: TimeInterval) -> [TimeInterval] {
        let interval = max(1, BroadcastConstants.classificationIntervalSeconds)
        var timestamps: [TimeInterval] = []
        var second = 0
        while TimeInterval(second) <= durationSeconds {
            if ScreenRecordingFrameExtractor.shouldClassify(at: TimeInterval(second)) {
                timestamps.append(TimeInterval(second))
            }
            second += interval
        }
        return timestamps
    }

    @discardableResult
    private static func exportWAVSegment(
        asset: AVURLAsset,
        track: AVAssetTrack,
        start: TimeInterval,
        duration: TimeInterval,
        outputURL: URL
    ) throws -> Bool {
        let readerAsset = asset
        let reader = try AVAssetReader(asset: readerAsset)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: whisperSampleRate,
            AVNumberOfChannelsKey: 1,
        ]

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        guard reader.startReading() else {
            throw reader.error ?? ExtractionError.exportFailed
        }

        var audioData = Data()
        while reader.status == .reading {
            guard let sampleBuffer = output.copyNextSampleBuffer(),
                  let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                continue
            }

            let length = CMBlockBufferGetDataLength(blockBuffer)
            var buffer = Data(count: length)
            buffer.withUnsafeMutableBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return }
                CMBlockBufferCopyDataBytes(
                    blockBuffer,
                    atOffset: 0,
                    dataLength: length,
                    destination: baseAddress
                )
            }
            audioData.append(buffer)
        }

        if reader.status == .failed {
            throw reader.error ?? ExtractionError.exportFailed
        }

        guard !audioData.isEmpty else { return false }

        try writeWAVFile(pcmData: audioData, sampleRate: whisperSampleRate, to: outputURL)
        return FileManager.default.fileExists(atPath: outputURL.path)
    }

    private static func writeWAVFile(pcmData: Data, sampleRate: Int, to url: URL) throws {
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = UInt32(pcmData.count)
        let riffSize = 36 + dataSize

        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        header.append(littleEndian: riffSize)
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.append(littleEndian: UInt32(16))
        header.append(littleEndian: UInt16(1))
        header.append(littleEndian: channels)
        header.append(littleEndian: UInt32(sampleRate))
        header.append(littleEndian: byteRate)
        header.append(littleEndian: blockAlign)
        header.append(littleEndian: bitsPerSample)
        header.append(contentsOf: "data".utf8)
        header.append(littleEndian: dataSize)

        var fileData = header
        fileData.append(pcmData)
        try fileData.write(to: url, options: .atomic)
    }
}

private extension Data {
    mutating func append(littleEndian value: UInt16) {
        var little = value.littleEndian
        append(UnsafeBufferPointer(start: &little, count: 1))
    }

    mutating func append(littleEndian value: UInt32) {
        var little = value.littleEndian
        append(UnsafeBufferPointer(start: &little, count: 1))
    }
}
