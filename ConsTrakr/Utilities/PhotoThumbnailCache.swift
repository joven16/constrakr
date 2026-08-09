//
//  PhotoThumbnailCache.swift
//  ConsTrakr
//
//  In-memory downsampled thumbnails so lists scroll smoothly.
//

import ImageIO
import UIKit

enum PhotoThumbnailCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        return cache
    }()

    static func cachedImage(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    static func loadImage(
        forKey key: String,
        maxPixelSize: Int,
        loader: @escaping @Sendable () -> Data?
    ) async -> UIImage? {
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        let data = await Task.detached(priority: .utility, operation: loader).value
        guard let data else { return nil }

        let image = await Task.detached(priority: .utility) {
            downsample(data: data, maxPixelSize: maxPixelSize)
        }.value

        if let image {
            cache.setObject(image, forKey: key as NSString)
        }
        return image
    }

    static func removeAll() {
        cache.removeAllObjects()
    }

    private static func downsample(data: Data, maxPixelSize: Int) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }
}
