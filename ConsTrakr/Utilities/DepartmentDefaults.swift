//
//  DepartmentDefaults.swift
//  ConsTrakr
//

import Foundation

enum DepartmentDefaults {
    static let builtInCatalog: [DepartmentCatalogCategory] = [
        category("General", ["General Laborer", "Helper", "Utility Worker"]),
        category("Civil Works", ["Civil Engineer", "Site Engineer", "Mason", "Concrete Worker", "Excavation Worker", "Roadworks Worker"]),
        category("Structural", ["Structural Engineer", "Steelman / Rebar Worker", "Formwork Carpenter", "Structural Welder", "Concrete Crew"]),
        category("Architectural", ["Architect", "Architectural Coordinator", "Tile Setter", "Ceiling Installer", "Drywall Installer", "Glass / Aluminum Installer", "Finishing Carpenter"]),
        category("MEP", ["MEP Engineer", "MEP Coordinator", "MEP Supervisor", "MEPF Engineer"]),
        category("HVAC", ["Mechanical Engineer", "HVAC Technician", "Duct Installer", "Aircon Technician"]),
        category("Electrical", ["Electrical Engineer", "Electrician", "Electrical Foreman", "Electrical Technician"]),
        category("Plumbing", ["Plumbing / Sanitary Engineer", "Plumber", "Pipefitter", "Plumbing Foreman"]),
        category("Painting", ["Painter", "Painting Foreman", "Surface Preparation Worker"]),
        category("Roofing", ["Roofer", "Roofing Installer", "Roofing Foreman", "Waterproofing Worker"]),
        category("Safety", ["Safety Manager", "Safety Officer", "Safety Inspector", "First Aider"]),
        category("QA/QC", ["QA/QC Manager", "QA/QC Engineer", "QA/QC Inspector", "Materials Inspector"]),
        category("Survey", ["Survey Engineer", "Surveyor", "Instrument Man", "Rodman / Survey Assistant"]),
        category("Equipment / Plant", ["Equipment Supervisor", "Heavy Equipment Operator", "Crane Operator", "Mechanic", "Auto Electrician", "Equipment Helper"]),
        category("Logistics", ["Logistics Officer", "Warehouseman", "Storekeeper", "Materials Controller", "Driver"]),
        category("Admin / Office", ["Project Administrator", "HR / Admin Officer", "Accountant", "Timekeeper", "Payroll Staff", "Document Controller", "Site Secretary"]),
        category("Supervision", ["Project Manager", "Construction Manager", "Project Engineer", "General Foreman", "Foreman", "Site Supervisor"]),
        category("Subcontractor", ["Subcontractor Supervisor", "Subcontractor Foreman", "Subcontractor Worker"]),
    ]

    static var builtIn: [String] {
        builtInCatalog.map(\.name)
    }

    static let otherLabel = "Other"

    private static func category(_ name: String, _ positions: [String]) -> DepartmentCatalogCategory {
        DepartmentCatalogCategory(
            id: "builtin-\(name)",
            name: name,
            sortOrder: 0,
            positions: positions.enumerated().map { index, title in
                DepartmentCatalogPosition(id: "builtin-\(name)-\(index)", name: title, sortOrder: index)
            }
        )
    }
}

struct DepartmentCatalogCategory: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let sortOrder: Int
    let positions: [DepartmentCatalogPosition]

    enum CodingKeys: String, CodingKey {
        case id, name, positions
        case sortOrder = "sort_order"
    }
}

struct DepartmentCatalogPosition: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case sortOrder = "sort_order"
    }
}
