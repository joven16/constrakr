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
}
