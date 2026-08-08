//
//  EmployeeCodeGenerator.swift
//  ConsTrakr
//
//  Auto employee IDs: YYYYMM + sequence (001–999 zero-padded, then 1000+ unpadded).
//

import Foundation

enum EmployeeCodeGenerator {
    static let monthPrefixLength = 6

    static func monthPrefix(for date: Date, calendar: Calendar = .current) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return String(format: "%04d%02d", year, month)
    }

    static func format(monthPrefix: String, sequence: Int) -> String {
        precondition(sequence >= 1, "Employee code sequence must be >= 1")
        let suffix = sequence <= 999 ? String(format: "%03d", sequence) : String(sequence)
        return monthPrefix + suffix
    }

    static func nextSequence(from existingCodes: [String], monthPrefix: String) -> Int {
        var maxSequence = 0
        for code in existingCodes {
            guard let sequence = parseSequence(from: code, expectedMonthPrefix: monthPrefix),
                  sequence > maxSequence else { continue }
            maxSequence = sequence
        }
        return maxSequence + 1
    }

    static func generate(existingCodes: [String], registeredAt: Date = Date(), calendar: Calendar = .current) -> String {
        let prefix = monthPrefix(for: registeredAt, calendar: calendar)
        let sequence = nextSequence(from: existingCodes, monthPrefix: prefix)
        return format(monthPrefix: prefix, sequence: sequence)
    }

    static func parseSequence(from code: String, expectedMonthPrefix: String) -> Int? {
        guard code.hasPrefix(expectedMonthPrefix), code.count > monthPrefixLength else { return nil }
        let suffix = String(code.dropFirst(monthPrefixLength))
        guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber) else { return nil }
        return Int(suffix)
    }
}
