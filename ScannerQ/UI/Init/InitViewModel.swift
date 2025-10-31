//
//  InitViewModel.swift
//  ScannerQ
//
//  Created by Serge Nes on 10/31/25.
//

import Foundation
import Combine
import SwiftUI
import CommonLibrary

@MainActor
final class InitViewModel: ObservableObject {
    private var autoConnectCancellable: AnyCancellable?

    func attemptAutoReconnect(
        lastDeviceId: String?,
        lastServiceUUID: String?,
        deps: AppDependencies,
        discoveryViewModel: DiscoveryViewModel,
        detailsViewModel: DetailsViewModel,
        navigationViewModel: NavigationViewModel,
        hideSplash: @escaping () -> Void
    ) {
        var didStartAuto = false
        if let idStr = lastDeviceId, let id = UUID(uuidString: idStr) {
            // Attempt direct connect by identifier
            detailsViewModel.selectedDeviceId = id
            detailsViewModel.setup(repository: deps.repository)
            detailsViewModel.onAppear()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                hideSplash()
                // Ensure a proper root so Back goes to Discovery instead of an empty splash
                navigationViewModel.path = NavigationPath()
                navigationViewModel.navigateTo(.discover)
                navigationViewModel.navigateTo(.details)
            }
            didStartAuto = true
        } else if let svcStr = lastServiceUUID, let svc = UUID(uuidString: svcStr) {
            // Start scanning and watch for a device advertising this service
            discoveryViewModel.setup(repository: deps.repository)
            discoveryViewModel.onAppear()
            autoConnectCancellable = deps.repository.devicesPublisher
                .sink { [weak self] devices in
                    guard let self = self else { return }
                    if let match = devices.first(where: { $0.preferredServiceUUID == svc && ($0.isConnectable ?? false) }) {
                        discoveryViewModel.pauseScanning()
                        detailsViewModel.selectedDevice = match
                        detailsViewModel.setup(repository: deps.repository)
                        hideSplash()
                        // Establish Discovery as root, then push Details so Back returns to Discovery
                        navigationViewModel.path = NavigationPath()
                        navigationViewModel.navigateTo(.discover)
                        navigationViewModel.navigateTo(.details)
                        self.autoConnectCancellable?.cancel(); self.autoConnectCancellable = nil
                    }
                }
            // Fallback: go to discovery after a short delay if nothing found
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self else { return }
                guard self.autoConnectCancellable != nil else { return }
                hideSplash()
                navigationViewModel.navigateTo(.discover)
            }
            didStartAuto = true
        }
        if didStartAuto == false {
            // No prefs saved; show splash briefly then go to discovery
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                hideSplash()
                navigationViewModel.navigateTo(.discover)
            }
        }
    }
}
