//
//  DiscoveryViewModel.swift
//  ScannerQ
//
//  Created by Serge Nes on 10/30/25.
//

import Foundation
import Combine
import CommonLibrary
import OSLog

@MainActor
final class DiscoveryViewModel: ObservableObject {
    
    // MARK: - Outputs
    @Published private(set) var devices: [BluetoothDevice] = []
    @Published private(set) var powerState: BluetoothPowerState = .unknown
    @Published var isScanning: Bool = false
    
    @Published var refreshInterval: TimeInterval = 10
    
    let refreshValues: [TimeInterval] = [0.0, 1.0, 5.0, 10.0]
    
    func updateRefreshInterval(_ refreshInterval: TimeInterval) {
        self.refreshInterval = refreshInterval
        devicesCancellable?.cancel()
        devicesCancellable = repository?.devicesPublisher
            .throttle(for: .seconds(self.refreshInterval), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] in self?.devices = $0 }
    }
    
    
    private var cancellables = Set<AnyCancellable>()
    private var devicesCancellable: AnyCancellable?
    
    private var repository: BluetoothRepository?
    
    func setup(repository: BluetoothRepository) {
        self.repository = repository
        self.bind()
    }
    
    private func bind() {
        // Live updates: subscribe directly to devices stream
        devicesCancellable = repository?.devicesPublisher
            .throttle(for: .seconds(self.refreshInterval), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] in self?.devices = $0 }

        // Power state: reflect only, scanning decisions are owned by Repository
        repository?.powerStatePublisher
            .sink { [weak self] state in
                self?.powerState = state
            }
            .store(in: &cancellables)
        
        // Mirror scanning state from repository
        repository?.isScanningPublisher
            .sink { [weak self] scanning in
                self?.isScanning = scanning
            }
            .store(in: &cancellables)
    }

    // MARK: - User Intents
    func onPreviewAppear() {
        devicesCancellable?.cancel()
        repository?.setScanningEnabled(false)
        isScanning = false
        devices = BluetoothDevice.previewStubs
    }
    
    func onAppear() {
        // Clear any pending auto-connect target so a new tap connects to the tapped device
        repository?.clearConnectionIntent()
        // Start scanning by default
        startStopScanning(shouldScan: true)
    }

    func onDisappear() {
        startStopScanning(shouldScan: false)
    }

    func toggleScanning() {
        startStopScanning(shouldScan: !isScanning)
    }

    // For navigation to detail screens
    func pauseScanning() {
        startStopScanning(shouldScan: false)
    }

    func resumeScanning() {
        startStopScanning(shouldScan: true)
    }

    private func startStopScanning(shouldScan: Bool) {
        repository?.setScanningEnabled(shouldScan)
    }
    
}
