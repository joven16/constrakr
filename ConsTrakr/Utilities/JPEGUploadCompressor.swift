//
//  JPEGUploadCompressor.swift
//  ConsTrakr
//

import UIKit

enum JPEGUploadCompressor {
    /// Shrinks enrollment / ID JPEGs before upload to reduce sync time on cellular.
    static func compressForUpload(
        _ data: Data,
        maxPixelSize: CGFloat = 1024,
        quality: CGFloat = 0.82
    ) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let scaled = scale(image, maxPixelSize: maxPixelSize)
        return scaled.jpegData(compressionQuality: quality) ?? data
    }

    private static func scale(_ image: UIImage, maxPixelSize: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxPixelSize, longest > 0 else { return image }

        let scale = maxPixelSize / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
