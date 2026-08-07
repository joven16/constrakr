//
//  UIImage+Rotation.swift
//  ConsTrakr
//

import UIKit

extension UIImage {
    /// Rotate 90° clockwise when `clockwise` is true, counter-clockwise when false.
    func rotatedQuarterTurn(clockwise: Bool) -> UIImage {
        let source = normalizedUpOrientation()
        let newSize = CGSize(width: source.size.height, height: source.size.width)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { context in
            let cg = context.cgContext
            cg.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            cg.rotate(by: clockwise ? .pi / 2 : -.pi / 2)
            source.draw(
                in: CGRect(
                    x: -source.size.width / 2,
                    y: -source.size.height / 2,
                    width: source.size.width,
                    height: source.size.height
                )
            )
        }
    }

    func normalizedUpOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
