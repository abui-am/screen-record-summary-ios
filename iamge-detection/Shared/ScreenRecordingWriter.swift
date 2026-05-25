//
//  ScreenRecordingWriter.swift
//  Shared between main app and Broadcast Upload Extension
//

import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

enum ScreenRecordingWriterError: LocalizedError {
    case cannotCreateWriter(String)
    case cannotStartWriting
    case appendFailed
    case finishFailed
    case missingFormat
    case missingPixelBuffer

    var errorDescription: String? {
        switch self {
        case .cannotCreateWriter(let detail):
            if detail.isEmpty {
                return "Could not create the screen recording file."
            }
            return "Could not create the screen recording file. \(detail)"
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
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var sessionStarted = false
    private var sessionStartTime: CMTime?
    private var frameCount = 0
    private var audioSampleCount = 0
    private var lastAcceptedPresentationTime: CMTime?
    private var pendingAudioBuffers: [CMSampleBuffer] = []
    private var preSessionVideoFrames = 0
    private let minFrameInterval = CMTime(value: 1, timescale: 1)
    /// Wait briefly for app audio before starting the writer session video-only.
    private let videoOnlySessionFrameThreshold = 2

    init(outputURL: URL) throws {
        self.outputURL = outputURL
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        do {
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw ScreenRecordingWriterError.cannotCreateWriter(error.localizedDescription)
        }
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

        try configureVideoInputIfNeeded(from: pixelBuffer)

        guard let assetWriter, let videoInput, let pixelBufferAdaptor else { return }
        if assetWriter.status == .failed {
            throw assetWriter.error ?? ScreenRecordingWriterError.appendFailed
        }

        if !sessionStarted {
            preSessionVideoFrames += 1
            if audioInput == nil, preSessionVideoFrames < videoOnlySessionFrameThreshold {
                return
            }
        }

        try startSessionIfNeeded(at: presentationTime)
        try flushPendingAudioBuffers()

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

    func appendAudio(sampleBuffer: CMSampleBuffer) throws {
        guard CMSampleBufferIsValid(sampleBuffer) else { return }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        try configureAudioInputIfNeeded(from: sampleBuffer)

        guard assetWriter != nil else { return }

        guard sessionStarted else {
            if let copy = copySampleBuffer(sampleBuffer) {
                pendingAudioBuffers.append(copy)
            }
            return
        }

        try appendAudioSampleBuffer(sampleBuffer, presentationTime: presentationTime)
    }

    func finish() throws {
        guard frameCount > 0 else { return }
        guard let assetWriter, let videoInput else { return }

        try flushPendingAudioBuffers()

        videoInput.markAsFinished()
        audioInput?.markAsFinished()

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

    private func startSessionIfNeeded(at presentationTime: CMTime) throws {
        guard !sessionStarted else { return }
        guard videoInput != nil else { return }
        guard let assetWriter else { throw ScreenRecordingWriterError.cannotCreateWriter("") }

        let startTime: CMTime
        if let sessionStartTime {
            startTime = CMTimeCompare(presentationTime, sessionStartTime) < 0 ? presentationTime : sessionStartTime
        } else {
            startTime = presentationTime
        }
        sessionStartTime = startTime

        guard assetWriter.startWriting() else {
            throw assetWriter.error ?? ScreenRecordingWriterError.cannotStartWriting
        }
        assetWriter.startSession(atSourceTime: startTime)
        sessionStarted = true
    }

    private func flushPendingAudioBuffers() throws {
        guard sessionStarted, !pendingAudioBuffers.isEmpty else { return }

        let buffers = pendingAudioBuffers
        pendingAudioBuffers.removeAll(keepingCapacity: true)

        for sampleBuffer in buffers {
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            try appendAudioSampleBuffer(sampleBuffer, presentationTime: presentationTime)
        }
    }

    private func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer, presentationTime: CMTime) throws {
        guard let assetWriter, let audioInput else { return }
        if assetWriter.status == .failed {
            throw assetWriter.error ?? ScreenRecordingWriterError.appendFailed
        }

        var retries = 0
        while !audioInput.isReadyForMoreMediaData, retries < 200 {
            Thread.sleep(forTimeInterval: 0.005)
            retries += 1
        }

        guard audioInput.isReadyForMoreMediaData else {
            throw ScreenRecordingWriterError.appendFailed
        }

        guard audioInput.append(sampleBuffer) else {
            throw assetWriter.error ?? ScreenRecordingWriterError.appendFailed
        }

        audioSampleCount += 1
    }

    private func configureVideoInputIfNeeded(from pixelBuffer: CVPixelBuffer) throws {
        guard videoInput == nil else { return }
        guard let assetWriter else { throw ScreenRecordingWriterError.cannotCreateWriter("") }

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
            let detail = assetWriter.error?.localizedDescription ?? "Could not add the video track."
            throw ScreenRecordingWriterError.cannotCreateWriter(detail)
        }

        assetWriter.add(input)
        videoInput = input
        pixelBufferAdaptor = adaptor
    }

    private func configureAudioInputIfNeeded(from sampleBuffer: CMSampleBuffer) throws {
        guard audioInput == nil else { return }
        guard !sessionStarted else { return }
        guard let assetWriter else { throw ScreenRecordingWriterError.cannotCreateWriter("") }
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            throw ScreenRecordingWriterError.missingFormat
        }

        let input: AVAssetWriterInput
        if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
           asbd.pointee.mFormatID == kAudioFormatMPEG4AAC {
            // Already AAC — pass through to the MP4 container.
            input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: nil,
                sourceFormatHint: formatDescription
            )
        } else if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) {
            // ReplayKit usually delivers PCM; re-encode to AAC for MP4.
            let sampleRate = asbd.pointee.mSampleRate
            let channels = Int(asbd.pointee.mChannelsPerFrame)
            guard sampleRate > 0, channels > 0 else {
                throw ScreenRecordingWriterError.missingFormat
            }

            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: 128_000,
            ]
            input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: audioSettings,
                sourceFormatHint: formatDescription
            )
        } else {
            throw ScreenRecordingWriterError.missingFormat
        }

        input.expectsMediaDataInRealTime = true

        guard assetWriter.canAdd(input) else {
            let detail = assetWriter.error?.localizedDescription ?? "Could not add the audio track."
            throw ScreenRecordingWriterError.cannotCreateWriter(detail)
        }

        assetWriter.add(input)
        audioInput = input

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if let sessionStartTime {
            if CMTimeCompare(presentationTime, sessionStartTime) < 0 {
                self.sessionStartTime = presentationTime
            }
        } else {
            sessionStartTime = presentationTime
        }
    }

    private func copySampleBuffer(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopy(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleBufferOut: &copy
        )
        guard status == noErr else { return nil }
        return copy
    }
}
