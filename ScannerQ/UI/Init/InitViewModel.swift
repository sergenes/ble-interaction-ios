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
        hideSplash: @escaping ([AppScreen]) -> Void
    ) {
        var didStartAuto = false
        if let idStr = lastDeviceId, let id = UUID(uuidString: idStr) {
            // Path 1: Direct reconnect using saved device ID
            deps.detailsViewModel.selectedDeviceId = id
            deps.detailsViewModel.setup(repository: deps.repository)
            deps.detailsViewModel.onAppear()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                hideSplash([.discover, .details])
            }
            didStartAuto = true
        } else if let svcStr = lastServiceUUID, let svc = UUID(uuidString: svcStr) {
            // Path 2: Scan for device with matching service UUID
            deps.discoveryViewModel.setup(repository: deps.repository)
            deps.discoveryViewModel.onAppear()
            autoConnectCancellable = deps.repository.devicesPublisher
                .sink { [weak self] devices in
                    guard let self = self else { return }
                    if let match = devices.first(where: { $0.preferredServiceUUID == svc && ($0.isConnectable ?? false) }) {
                        deps.discoveryViewModel.pauseScanning()
                        deps.detailsViewModel.selectedDevice = match
                        deps.detailsViewModel.setup(repository: deps.repository)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            hideSplash([.discover, .details])
                        }
                        self.autoConnectCancellable?.cancel(); self.autoConnectCancellable = nil
                    }
                }
            // Fallback: go to discovery after a short delay if nothing found
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self else { return }
                guard self.autoConnectCancellable != nil else { return }
                hideSplash([.discover])
            }
            didStartAuto = true
        }
        // No preferences saved; show splash briefly then go to discovery
        if !didStartAuto {
            // No prefs saved; show splash briefly then go to discovery
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                hideSplash([.discover])
            }
        }
    }
}
