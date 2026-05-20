//
//  BroadcastPixelBufferConverter.swift
//  Shared between main app and Broadcast Upload Extension
//

import CoreImage
import CoreMedia
import CoreVideo
import Foundation

enum BroadcastPixelBufferConverter {
    private static let renderContext = CIContext(options: [.useSoftwareRenderer: false])

    static func makeBGRACopy(from sampleBuffer: CMSampleBuffer) -> CVPixelBuffer? {
        guard let source = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }

        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        guard width > 0, height > 0 else { return nil }

        var destination: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true,
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &destination
        )

        guard status == kCVReturnSuccess, let destination else { return nil }

        var image = CIImage(cvPixelBuffer: source)
        image = image.oriented(forExifOrientation: exifOrientation(from: sampleBuffer))
        renderContext.render(image, to: destination)
        return destination
    }

    private static func exifOrientation(from sampleBuffer: CMSampleBuffer) -> Int32 {
        guard
            let orientation = CMGetAttachment(
                sampleBuffer,
                key: "RPVideoSampleOrientationKey" as CFString,
                attachmentModeOut: nil
            ) as? NSNumber
        else {
            return 1
        }

        switch orientation.int32Value {
        case 1: return 1
        case 2: return 4
        case 3: return 3
        case 4: return 2
        default: return 1
        }
    }
}
