//
//  AppDependencies.swift
//  BLEInteraction
//
//  Created by Serge Nes on 10/30/25.
//

import Foundation
import Combine

// Simple dependency container to share a single repository across the app
final class AppDependencies: ObservableObject {
    // Shared services
    let repository: BluetoothRepository = BluetoothRepository()
    
    // Shared view models
    let discoveryViewModel = DiscoveryViewModel()
    let detailsViewModel = DetailsViewModel()
    
    private var cancellables: [AnyCancellable] = []
    
    init() {
        // Forward child ViewModels' changes so views observing `deps` refresh
        cancellables = [
            discoveryViewModel.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() },
            detailsViewModel.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        ]
    }
}
