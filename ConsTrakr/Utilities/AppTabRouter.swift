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

    func orderedTabs(showsScanner: Bool) -> [Tab] {
        var tabs: [Tab] = [.dashboard, .employees]
        if showsScanner {
            tabs.append(.scanner)
        }
        tabs.append(.dtr)
        tabs.append(.more)
        return tabs
    }

    func selectNextTab(showsScanner: Bool) {
        let tabs = orderedTabs(showsScanner: showsScanner)
        guard let index = tabs.firstIndex(of: selectedTab), index < tabs.count - 1 else { return }
        selectedTab = tabs[index + 1]
    }

    func selectPreviousTab(showsScanner: Bool) {
        let tabs = orderedTabs(showsScanner: showsScanner)
        guard let index = tabs.firstIndex(of: selectedTab), index > 0 else { return }
        selectedTab = tabs[index - 1]
    }

    /// Opens DTR for the default job site configured under More → Job Sites.
    func openDTR() {
        selectedTab = .dtr
    }
}
