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
    /// Opens DTR for the default job site configured under More → Job Sites.
    func openDTR() {
        selectedTab = .dtr
    }
}
