//
//  EmployeeListViewModel.swift
//  ConsTrac
//

import Foundation
import SwiftData

@MainActor
@Observable
final class EmployeeListViewModel {
    var searchText = ""

    private(set) var employees: [Employee] = []
    private(set) var errorMessage: String?

    private var employeeService: EmployeeService?

    func configure(context: ModelContext) {
        employeeService = EmployeeService(context: context)
        refresh()
    }

    func refresh() {
        guard let employeeService else { return }
        do {
            employees = try employeeService.allEmployees(search: searchText)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ employee: Employee) {
        guard let employeeService else { return }
        do {
            try employeeService.delete(employee)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
