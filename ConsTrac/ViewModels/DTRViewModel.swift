//
//  DTRViewModel.swift
//  ConsTrac
//

import Foundation
import SwiftData

@MainActor
@Observable
final class DTRViewModel {
    var selectedDate: Date = Date()

    private(set) var rows: [DTRRow] = []
    private(set) var errorMessage: String?

    private var attendanceService: AttendanceService?

    struct DTRRow: Identifiable {
        let id: UUID
        let employeeName: String
        let employeeCode: String
        let timeIn: Date?
        let timeOut: Date?
    }

    var dayTitle: String {
        selectedDate.formatted(date: .complete, time: .omitted)
    }

    func configure(context: ModelContext) {
        attendanceService = AttendanceService(context: context)
        refresh()
    }

    func refresh() {
        guard let attendanceService else { return }
        do {
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: selectedDate)
            let end = calendar.date(byAdding: .day, value: 1, to: start)?
                .addingTimeInterval(-0.001) ?? start

            let fetched = try attendanceService.history(from: start, to: end)

            struct Acc {
                var name: String
                var code: String
                var timeIn: Date?
                var timeOut: Date?
            }

            var byEmployee: [UUID: Acc] = [:]
            for record in fetched {
                var acc = byEmployee[record.employeeId] ?? Acc(
                    name: attendanceService.employeeName(for: record),
                    code: attendanceService.employeeCode(for: record),
                    timeIn: nil,
                    timeOut: nil
                )
                switch record.checkType {
                case .checkIn:
                    if acc.timeIn == nil || record.timestamp < acc.timeIn! {
                        acc.timeIn = record.timestamp
                    }
                case .checkOut:
                    if acc.timeOut == nil || record.timestamp > acc.timeOut! {
                        acc.timeOut = record.timestamp
                    }
                }
                byEmployee[record.employeeId] = acc
            }

            rows = byEmployee.map { id, acc in
                DTRRow(
                    id: id,
                    employeeName: acc.name,
                    employeeCode: acc.code,
                    timeIn: acc.timeIn,
                    timeOut: acc.timeOut
                )
            }
            .sorted { $0.employeeName.localizedCaseInsensitiveCompare($1.employeeName) == .orderedAscending }

            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
