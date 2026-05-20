//
//  ScreenRecordingWriter.swift
//  Shared between main app and Broadcast Upload Extension
//

import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

enum ScreenRecordingWriterError: LocalizedError {
    case cannotCreateWriter
    case cannotStartWriting
    case appendFailed
    case finishFailed
    case missingFormat
    case missingPixelBuffer

    var errorDescription: String? {
        switch self {
        case .cannotCreateWriter:
            return "Could not create the screen recording file."
        case .cannotStartWriting:
            return "Could not start writing the screen recording."
        case .appendFailed:
            return "Could not append a frame to the screen recording."
        case .finishFailed:
            return "Could not finalize the screen recording."
        case .missingFormat:
            return "The screen recording did not include a valid video format."
        case .missingPixelBuffer:
            return "The screen recording frame did not contain image data."
        }
    }
}

final class ScreenRecordingWriter {
    let outputURL: URL
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var sessionStarted = false
    private var frameCount = 0
    private var lastAcceptedPresentationTime: CMTime?
    private let minFrameInterval = CMTime(value: 1, timescale: 1)

    init(outputURL: URL) throws {
        self.outputURL = outputURL
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            throw ScreenRecordingWriterError.cannotCreateWriter
        }
        assetWriter = writer
    }

    func append(sampleBuffer: CMSampleBuffer) throws {
        guard CMSampleBufferIsValid(sampleBuffer) else { return }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if let lastAcceptedPresentationTime {
            let delta = CMTimeSubtract(presentationTime, lastAcceptedPresentationTime)
            if CMTimeCompare(delta, minFrameInterval) < 0 {
                return
            }
        }

        guard let pixelBuffer = BroadcastPixelBufferConverter.makeBGRACopy(from: sampleBuffer) else {
            throw ScreenRecordingWriterError.missingPixelBuffer
        }

        try configureWriterIfNeeded(from: pixelBuffer)

        guard let assetWriter, let videoInput, let pixelBufferAdaptor else { return }
        if assetWriter.status == .failed {
            throw assetWriter.error ?? ScreenRecordingWriterError.appendFailed
        }

        if !sessionStarted {
            guard assetWriter.startWriting() else {
                throw assetWriter.error ?? ScreenRecordingWriterError.cannotStartWriting
            }
            assetWriter.startSession(atSourceTime: presentationTime)
            sessionStarted = true
        }

        var retries = 0
        while !videoInput.isReadyForMoreMediaData, retries < 200 {
            Thread.sleep(forTimeInterval: 0.005)
            retries += 1
        }

        guard videoInput.isReadyForMoreMediaData else {
            throw ScreenRecordingWriterError.appendFailed
        }

        guard pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
            throw assetWriter.error ?? ScreenRecordingWriterError.appendFailed
        }

        lastAcceptedPresentationTime = presentationTime
        frameCount += 1
    }

    func finish() throws {
        guard frameCount > 0 else { return }
        guard let assetWriter, let videoInput else { return }

        videoInput.markAsFinished()

        let group = DispatchGroup()
        group.enter()
        assetWriter.finishWriting {
            group.leave()
        }
        group.wait()

        guard assetWriter.status == .completed else {
            throw assetWriter.error ?? ScreenRecordingWriterError.finishFailed
        }
    }

    private func configureWriterIfNeeded(from pixelBuffer: CVPixelBuffer) throws {
        guard videoInput == nil else { return }
        guard let assetWriter else { throw ScreenRecordingWriterError.cannotCreateWriter }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else {
            throw ScreenRecordingWriterError.missingFormat
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * 4,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )

        guard assetWriter.canAdd(input) else {
            throw ScreenRecordingWriterError.cannotCreateWriter
        }

        assetWriter.add(input)
        videoInput = input
        pixelBufferAdaptor = adaptor
    }
}
