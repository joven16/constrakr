//
//  Date+Formatting.swift
//  ConsTrakr
//

import Foundation

extension Date {
    var attendanceDisplay: String {
        formatted(date: .abbreviated, time: .shortened)
    }

    var timeOnly: String {
        formatted(date: .omitted, time: .shortened)
    }

    var dayOnly: String {
        formatted(date: .complete, time: .omitted)
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }
}
