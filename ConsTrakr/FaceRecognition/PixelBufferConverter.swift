//
//  PixelBufferConverter.swift
//  ConsTrakr
//

import CoreVideo
import UIKit

enum PixelBufferConverter {
    enum Error: Swift.Error {
        case invalidImage
        case bufferCreationFailed
        case renderFailed
    }

    static func pixelBuffer(fromJPEG data: Data) throws -> CVPixelBuffer {
        guard let image = UIImage(data: data),
              let cgImage = image.cgImage else {
            throw Error.invalidImage
        }

        let width = cgImage.width
        let height = cgImage.height
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true
            ] as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else {
            throw Error.bufferCreationFailed
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw Error.renderFailed
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
