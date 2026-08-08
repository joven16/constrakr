//
//  AppTabRouter.swift
//  ConsTrakr
//

import SwiftUI

@MainActor
@Observable
final class AppTabRouter {
    enum Tab: Hashable {
        case dashboard
        case employees
        case scanner
        case dtr
        case more
    }

    var selectedTab: Tab = .dashboard
    /// When set, DTR tab shows roster and punches for this job site only.
    var dtrSiteFilterId: UUID?

    func openDTR(forSiteId siteId: UUID) {
        dtrSiteFilterId = siteId
        selectedTab = .dtr
    }
}
