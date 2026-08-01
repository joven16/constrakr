//
//  AttendancePhotoStore.swift
//  ConsTrakr
//
//  Face crop captured at Time In / Time Out for supervisor audit.
//  Files are keyed by attendance id (no SwiftData schema change required).
//

import CoreVideo
import Foundation

enum AttendancePhotoStore {
    private static let folderName = "AttendancePhotos"

    static func encodeFaceJPEG(
        from pixelBuffer: CVPixelBuffer,
        boundingBox: CGRect
    ) -> Data? {
        EnrollmentPhotoStore.encodeFaceJPEG(from: pixelBuffer, boundingBox: boundingBox)
    }

    static func save(attendanceId: UUID, jpeg: Data) throws {
        let dir = rootDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try jpeg.write(to: fileURL(attendanceId: attendanceId), options: .completeFileProtection)
    }

    static func load(attendanceId: UUID) -> Data? {
        try? Data(contentsOf: fileURL(attendanceId: attendanceId))
    }

    static func delete(attendanceId: UUID) {
        try? FileManager.default.removeItem(at: fileURL(attendanceId: attendanceId))
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: rootDirectory())
    }

    private static func rootDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folderName, isDirectory: true)
    }

    private static func fileURL(attendanceId: UUID) -> URL {
        rootDirectory().appendingPathComponent("\(attendanceId.uuidString).jpg")
    }
}
