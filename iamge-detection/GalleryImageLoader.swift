//
//  GalleryImageLoader.swift
//  iamge-detection
//

import Photos
import PhotosUI
import SwiftUI
import UIKit

enum GalleryImageLoader {
    enum LoadError: LocalizedError {
        case assetNotFound
        case imageUnavailable

        var errorDescription: String? {
            switch self {
            case .assetNotFound:
                return "Photo asset could not be found."
            case .imageUnavailable:
                return "Could not load the selected photo."
            }
        }
    }

    /// Loads the original photo from the library without downscaling or re-encoding.
    static func loadFullResolution(from item: PhotosPickerItem) async throws -> UIImage {
        if let itemID = item.itemIdentifier {
            return try await loadFromPhotoLibrary(itemID: itemID)
        }

        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw LoadError.imageUnavailable
        }
        return try imageFromData(data)
    }

    private static func loadFromPhotoLibrary(itemID: String) async throws -> UIImage {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [itemID], options: nil)
        guard let asset = assets.firstObject else {
            throw LoadError.assetNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .none
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .default,
                options: options
            ) { image, info in
                if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                    continuation.resume(throwing: LoadError.imageUnavailable)
                    return
                }
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let image else {
                    continuation.resume(throwing: LoadError.imageUnavailable)
                    return
                }
                continuation.resume(returning: normalize(image))
            }
        }
    }

    private static func imageFromData(_ data: Data) throws -> UIImage {
        guard let image = UIImage(data: data) else {
            throw LoadError.imageUnavailable
        }
        return normalize(image)
    }

    /// Keeps pixel dimensions and applies orientation so preview matches the original.
    private static func normalize(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        guard image.imageOrientation != .up else {
            return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
