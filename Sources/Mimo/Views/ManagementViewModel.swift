//
//  ManagementViewModel.swift
//  
//
//  Created by Srinivas Pendela on 27/04/2026.
//

import Foundation
import Combine

enum TransitionDirection {
    case leading
    case trailing
}

@MainActor
final class ManagementViewModel: ObservableObject {
    @Published var transitionDirection: TransitionDirection = .trailing

    @Published var showProfileForm: Bool = false
    @Published var isCreatingNewProfile: Bool = false
    @Published var showNewSSHKeyForm: Bool = false

    func isMinusIcon(tab: Constants.ManagementTab) -> Bool {
        switch tab {
        case .profile: return showProfileForm && isCreatingNewProfile
        case .ssh: return showNewSSHKeyForm
        case .directories, .signing: return false
        }
    }

    func selectTab(appModel: AppModel, tab: Constants.ManagementTab) {
        let tabs = Constants.ManagementTab.allCases
        let currentIndex = tabs.firstIndex(of: appModel.selectedManagementTab) ?? 0
        let targetIndex = tabs.firstIndex(of: tab) ?? 0

        transitionDirection = targetIndex > currentIndex ? .trailing : .leading

        appModel.selectedManagementTab = tab
    }
}
