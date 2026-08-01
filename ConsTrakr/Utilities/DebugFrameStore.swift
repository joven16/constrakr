//
//  DebugFrameStore.swift
//  ConsTrakr
//
//  CHANGE: Captured camera frames are discarded by default.
//  Enable `AppConstants.UserDefaultsKeys.uploadRawFramesEnabled` only for re-enrollment/debug.
//

import CoreVideo
import Foundation
import UIKit

enum DebugFrameStore {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.uploadRawFramesEnabled)
    }

    /// Optionally keeps a JPEG thumbnail on disk for debugging — never uploads unless explicitly enabled later.
    static func maybePersistDebugFrame(_ pixelBuffer: CVPixelBuffer, label: String) {
        guard isEnabled else { return }
        // DEBUG ONLY — not part of the production attendance path.
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let image = UIImage(cgImage: cgImage)
        guard let data = image.jpegData(compressionQuality: 0.6) else { return }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ConsTrakrDebugFrames", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(label)-\(UUID().uuidString).jpg")
        try? data.write(to: url, options: .completeFileProtection)
    }
}
