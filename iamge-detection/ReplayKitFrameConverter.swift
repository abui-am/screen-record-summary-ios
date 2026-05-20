//
//  ReplayKitFrameConverter.swift
//  iamge-detection
//

import CoreImage
import CoreMedia
import CoreVideo
import ReplayKit
import UIKit

enum ReplayKitFrameConverter {
    private static let renderContext = CIContext(options: [.useSoftwareRenderer: false])

    /// ReplayKit on device often delivers YUV buffers and reuses them quickly.
    /// Copy + convert to BGRA before preview or Core ML inference.
    static func makeBGRACopy(from sampleBuffer: CMSampleBuffer) -> CVPixelBuffer? {
        guard let source = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }

        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        guard width > 0, height > 0 else { return nil }

        var destination: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true,
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &destination
        )

        guard status == kCVReturnSuccess, let destination else { return nil }

        var ciImage = CIImage(cvPixelBuffer: source)
        ciImage = ciImage.oriented(forExifOrientation: exifOrientation(from: sampleBuffer))

        renderContext.render(ciImage, to: destination)
        return destination
    }

    static func uiImage(from sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let buffer = makeBGRACopy(from: sampleBuffer) else { return nil }
        return ImagePreprocessor.uiImage(from: buffer)
    }

    private static func exifOrientation(from sampleBuffer: CMSampleBuffer) -> Int32 {
        guard
            let orientation = CMGetAttachment(
                sampleBuffer,
                key: RPVideoSampleOrientationKey as CFString,
                attachmentModeOut: nil
            ) as? NSNumber
        else {
            return 1
        }

        switch orientation.int32Value {
        case 1: return 1  // portrait
        case 2: return 4  // portrait upside down
        case 3: return 3  // landscape left
        case 4: return 2  // landscape right
        default: return 1
        }
    }
}
