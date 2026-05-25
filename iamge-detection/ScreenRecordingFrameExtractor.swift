//
//  ScreenRecordingFrameExtractor.swift
//  iamge-detection
//

import AVFoundation
import CoreMedia
import CoreVideo

struct ScreenRecordingMetadata: Sendable {
    let fps: Float
    let duration: TimeInterval
    let estimatedFrameCount: Int
}

struct ScreenRecordingFrame {
    let index: Int
    let timestamp: TimeInterval
    let pixelBuffer: CVPixelBuffer
}

enum ScreenRecordingFrameExtractor {
    enum ExtractionError: LocalizedError {
        case unreadableVideo
        case noFrames

        var errorDescription: String? {
            switch self {
            case .unreadableVideo:
                return "Could not read the saved screen recording."
            case .noFrames:
                return "The screen recording did not contain any frames to analyze."
            }
        }
    }

    static func loadMetadata(from videoURL: URL) async throws -> ScreenRecordingMetadata {
        let asset = AVURLAsset(url: videoURL)
        guard !(try await asset.loadTracks(withMediaType: .video)).isEmpty else {
            throw ExtractionError.unreadableVideo
        }

        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw ExtractionError.unreadableVideo
        }

        let fps = Float(BroadcastConstants.targetRecordingFPS)
        let estimatedFrameCount = Self.estimatedClassificationFrameCount(durationSeconds: durationSeconds)
        return ScreenRecordingMetadata(
            fps: fps,
            duration: durationSeconds,
            estimatedFrameCount: estimatedFrameCount
        )
    }

    static func estimatedClassificationFrameCount(durationSeconds: TimeInterval) -> Int {
        let interval = max(1, BroadcastConstants.classificationIntervalSeconds)
        return max(1, Int(floor(durationSeconds / Double(interval))) + 1)
    }

    static func shouldClassify(at timestamp: TimeInterval) -> Bool {
        let interval = max(1, BroadcastConstants.classificationIntervalSeconds)
        let second = Int(timestamp.rounded(.down))
        return second % interval == 0
    }

    static func forEachFrame(
        from videoURL: URL,
        body: @Sendable (ScreenRecordingFrame) async throws -> Void
    ) async throws -> Int {
        let asset = AVURLAsset(url: videoURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExtractionError.unreadableVideo
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ]
        )
        output.alwaysCopiesSampleData = false
        reader.add(output)

        guard reader.startReading() else {
            throw reader.error ?? ExtractionError.unreadableVideo
        }

        var index = 0
        while reader.status == .reading {
            guard let sampleBuffer = output.copyNextSampleBuffer(),
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                continue
            }

            let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            try await body(
                ScreenRecordingFrame(
                    index: index,
                    timestamp: timestamp,
                    pixelBuffer: pixelBuffer
                )
            )
            index += 1
        }

        if reader.status == .failed {
            throw reader.error ?? ExtractionError.unreadableVideo
        }

        guard index > 0 else { throw ExtractionError.noFrames }
        return index
    }
}
