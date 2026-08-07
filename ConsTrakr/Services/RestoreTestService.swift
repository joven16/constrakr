//
//  RestoreTestService.swift
//  ConsTrakr
//
//  Wipes local SwiftData + on-disk photos to simulate a fresh device, then cloud restore can be verified.
//

import Foundation
import SwiftData

struct LocalDataSnapshot {
    let employees: Int
    let embeddings: Int
    let enrollmentPhotoEntities: Int
    let attendance: Int

    var summaryLine: String {
        "\(employees) employees, \(embeddings) face templates, \(enrollmentPhotoEntities) enrollment photo rows, \(attendance) attendance records"
    }
}

struct RestoreTestResult {
    let wiped: LocalDataSnapshot
    let restored: SyncService.RestoreSummary

    var report: String {
        var lines: [String] = [
            "Local data cleared:",
            "  \(wiped.summaryLine)",
            "",
            "Downloaded from IMS:",
            "  \(restored.detailedLines.joined(separator: "\n  "))",
            "",
            restored.verificationNote
        ]
        return lines.joined(separator: "\n")
    }
}

enum RestoreTestService {
    static func snapshot(context: ModelContext) throws -> LocalDataSnapshot {
        LocalDataSnapshot(
            employees: try EmployeeRepository(context: context).count(),
            embeddings: try context.fetchCount(FetchDescriptor<FaceEmbeddingEntity>()),
            enrollmentPhotoEntities: try context.fetchCount(FetchDescriptor<FaceEnrollmentPhotoEntity>()),
            attendance: try context.fetchCount(FetchDescriptor<Attendance>())
        )
    }

    /// Removes all local employees, attendance, embeddings, and JPEG files. Does not call IMS.
    static func wipeLocalData(context: ModelContext) throws {
        let employees = try context.fetch(FetchDescriptor<Employee>())
        for employee in employees {
            EnrollmentPhotoStore.delete(employeeId: employee.id)
            IdDocumentPhotoStore.delete(employeeId: employee.id)
        }

        for record in try context.fetch(FetchDescriptor<Attendance>()) {
            context.delete(record)
        }
        for entity in try context.fetch(FetchDescriptor<FaceEmbeddingEntity>()) {
            context.delete(entity)
        }
        for entity in try context.fetch(FetchDescriptor<FaceEnrollmentPhotoEntity>()) {
            context.delete(entity)
        }
        for entity in try context.fetch(FetchDescriptor<EmployeeIdDocumentEntity>()) {
            context.delete(entity)
        }
        for employee in employees {
            context.delete(employee)
        }

        AttendancePhotoStore.deleteAll()
        EnrollmentPhotoStore.deleteAll()
        IdDocumentPhotoStore.deleteAll()
        try context.save()

        NotificationCenter.default.post(name: AppConstants.Notifications.attendanceHistoryDidClear, object: nil)
        NotificationCenter.default.post(name: AppConstants.Notifications.employeesDidChange, object: nil)
    }
}

extension SyncService.RestoreSummary {
    var detailedLines: [String] {
        var lines = [
            "Employees: \(employees)",
            "Face templates: \(embeddings)",
            "Enrollment photo rows: \(enrollmentPhotos)",
            "Enrollment JPEGs on disk: \(enrollmentPhotosWithJPEG)",
            "Attendance records: \(attendance)",
            "Punch photos on disk: \(punchPhotos)"
        ]
        if employees > 0 && embeddings == 0 {
            lines.append("⚠️ No face templates — face scan may not work offline.")
        }
        if enrollmentPhotos > 0 && enrollmentPhotosWithJPEG < enrollmentPhotos {
            lines.append("⚠️ Some enrollment photos missing JPEG bytes from IMS.")
        }
        if attendance > 0 && punchPhotos == 0 {
            lines.append("⚠️ No punch photo JPEGs restored (check IMS include_media).")
        }
        return lines
    }

    fileprivate var verificationNote: String {
        "Verify in app: Employees tab (roster + photos), DTR (history + punch thumbnails). Device works offline after restore."
    }
}
