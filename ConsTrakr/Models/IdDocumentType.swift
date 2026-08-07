//
//  IdDocumentType.swift
//  ConsTrakr
//
//  Government ID types aligned with IMS rentals ID_TYPE_CHOICES.
//

import Foundation

enum IdDocumentType: String, CaseIterable, Identifiable, Codable {
    case philsysNationalId = "philsys_national_id"
    case driversLicense = "drivers_license"
    case passport = "passport"
    case sssUmid = "sss_umid"
    case votersId = "voters_id"
    case philhealthId = "philhealth_id"
    case pagIbigId = "pag_ibig_id"
    case postalId = "postal_id"
    case seniorCitizenId = "senior_citizen_id"
    case pwdId = "pwd_id"
    case nbiClearance = "nbi_clearance"
    case tinId = "tin_id"
    case policeId = "police_id"
    case prcId = "prc_id"
    case others = "others"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .philsysNationalId: return "PhilSys National ID"
        case .driversLicense: return "Driver's License"
        case .passport: return "Passport"
        case .sssUmid: return "SSS / UMID"
        case .votersId: return "Voter's ID"
        case .philhealthId: return "PhilHealth ID"
        case .pagIbigId: return "Pag-IBIG ID"
        case .postalId: return "Postal ID"
        case .seniorCitizenId: return "Senior Citizen ID"
        case .pwdId: return "PWD ID"
        case .nbiClearance: return "NBI Clearance"
        case .tinId: return "TIN ID"
        case .policeId: return "Police ID"
        case .prcId: return "PRC ID"
        case .others: return "Other ID"
        }
    }
}
