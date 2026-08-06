//
//  DataController.swift
//  ConsTrakr
//
//  FIX: Do not seed mock face embeddings — they are random placeholders and can
//  pollute matching. Demo employees (if seeded) have no enrollment until real capture.
//

import Foundation
import SwiftData

enum DataController {
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema([
            Employee.self,
            Attendance.self,
            FaceEmbeddingEntity.self,
            FaceEnrollmentPhotoEntity.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [fallback])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }

    @MainActor
    static func seedMockDataIfNeeded(context: ModelContext) {
        let key = AppConstants.UserDefaultsKeys.hasSeededMockData
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let descriptor = FetchDescriptor<Employee>()
        let existing = (try? context.fetch(descriptor)) ?? []
        guard existing.isEmpty else {
            UserDefaults.standard.set(true, forKey: key)
            return
        }

        // Seed directory entries WITHOUT face embeddings (scanner ignores non-enrolled).
        let samples: [(String, String, String, String)] = [
            ("EMP001", "Jordan", "Reyes", "Engineering"),
            ("EMP002", "Aisha", "Patel", "Operations"),
            ("EMP003", "Marco", "Santos", "Security")
        ]

        for sample in samples {
            let employee = Employee(
                employeeCode: sample.0,
                firstName: sample.1,
                lastName: sample.2,
                department: sample.3,
                faceEmbeddings: [],
                syncStatus: .pending
            )
            context.insert(employee)
        }

        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }
}
