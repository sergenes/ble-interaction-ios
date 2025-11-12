//
//  DetailsViewModel.swift
//  BLEInteraction
//
//  Created by Serge Nes on 10/30/25.
//

import Foundation
import Combine
import CommonLibrary
import UIKit

@MainActor
final class DetailsViewModel: ObservableObject {
    
    // MARK: - Pref Keys
    static let prefsLastDeviceId = "lastDeviceId"
    static let prefsLastServiceUUID = "lastServiceUUID"
    
    // MARK: - Inputs
    @Published var selectedDevice: BluetoothDevice? = nil
    @Published var selectedDeviceId: UUID? = nil


    // MARK: - Outputs
    @Published private(set) var state: BluetoothConnectionState = .idle
    @Published private(set) var detail: DeviceDetail?
    @Published private(set) var messages: [String] = []
    @Published var inputText: String = ""
    @Published var toggleOn: Bool = false
    @Published private(set) var receivedImage: UIImage? = nil
    @Published private(set) var receivedImageFilename: String? = nil
    @Published private(set) var receivedImageBytes: Int? = nil
    // Image download progress state
    @Published var isImageDownloading: Bool = false
    @Published var imageDownloadProgress: Double = 0

    // Text protocol parser
    private let parser = TextProtocolParser()

    private var cancellables = Set<AnyCancellable>()
    private var isBound = false
    
    private var repository: BluetoothRepository?
    
    func setup(repository: BluetoothRepository) {
        self.repository = repository
        // Prevent duplicate subscriptions if setup/bind is called multiple times
        guard !isBound else { return }
        self.bind()
    }
    
    private func bind() {
        isBound = true
        repository?.connectionStatePublisher
            .sink { [weak self] newState in
                self?.state = newState
                if case .disconnected = newState {
                    self?.resetImageState()
                }
            }
            .store(in: &cancellables)

        repository?.deviceDetailPublisher
            .sink { [weak self] detail in
                guard let self = self else { return }
                self.detail = detail
            }
            .store(in: &cancellables)

        // Wire parser delegate
        parser.delegate = self
        repository?.inboundTextPublisher
            .sink { [weak self] text in
                self?.parser.feed(line: text)
            }
            .store(in: &cancellables)
    }


    // MARK: - Image RX helpers
    func resetImageState() {
        receivedImage = nil
        receivedImageFilename = nil
        receivedImageBytes = nil
        isImageDownloading = false
        imageDownloadProgress = 0
    }

    // MARK: - Lifecycle
    func onAppear() {
        // If a specific device model was explicitly selected from Discovery, prefer it.
        if let device = selectedDevice {
            repository?.connect(to: device)
            return
        }
        // Otherwise, fall back to last selected identifier (e.g., from Splash auto-reconnect)
        if let id = selectedDeviceId {
            repository?.connect(to: id)
            return
        }
        // Waiting for selection
    }

    func onDisappear() {
        repository?.disconnect()
        messages = []
        inputText = ""
        toggleOn = false
        resetImageState()
        // Clear persisted auto-connect preferences when leaving details
        UserDefaults.standard.removeObject(forKey: Self.prefsLastDeviceId)
        UserDefaults.standard.removeObject(forKey: Self.prefsLastServiceUUID)
        // Reset bindings so a future appearance re-binds cleanly without duplicates
        cancellables.removeAll()
        isBound = false
        // Also clear any implicit selection to avoid stale reuse
        selectedDevice = nil
        selectedDeviceId = nil
    }

    // MARK: - Actions
    func send() {
        let text = inputText
        inputText = ""
        guard !text.isEmpty else { return }
        repository?.send(text: text)
    }

    func sendToggle() {
        repository?.sendToggle(on: toggleOn)
    }

    func disconnect() {
        repository?.disconnect()
    }
    
    func getImage() {
        repository?.send(text: TextProtocol.getImage)
    }
}



// MARK: - TextMessageHandler
extension DetailsViewModel: TextMessageHandler {
    func didReceiveRegularMessage(_ line: String) {
        let truncated = line.truncated(to: 500)
        self.messages.append(truncated)
        
        // Only notify when the app is not active (background / inactive)
        let appState = UIApplication.shared.applicationState
        if appState != .active {
            let title = detail?.device.name ?? "ScannerQ"
            NotificationManager.shared.scheduleNotification(
                title: title,
                body: truncated,
                delay: 1,
                userInfo: ["command": "inbound_text", "text": truncated]
            )
        }
    }

    func didStartImage(filename: String, expectedBytes: Int) {
        self.receivedImage = nil
        self.receivedImageFilename = filename
        self.receivedImageBytes = expectedBytes > 0 ? expectedBytes : nil
        self.isImageDownloading = true
        self.imageDownloadProgress = 0
    }

    func didReceiveImageProgress(bytesEstimated: Int, expectedBytes: Int) {
        guard expectedBytes > 0 else { return }
        let prog = min(0.99, max(0.0, Double(bytesEstimated) / Double(expectedBytes)))
        self.imageDownloadProgress = prog
    }

    func didFinishImage(data: Data, filename: String) {
        #if canImport(UIKit)
        if let image = UIImage(data: data) {
            self.receivedImage = image
        }
        #endif
        self.receivedImageFilename = filename
        self.receivedImageBytes = data.count
        self.imageDownloadProgress = 1.0
        self.isImageDownloading = false
        self.messages.append("Image received (\(filename), \(data.count) bytes)")
    }

    func didFailImage(reason: String) {
        self.messages.append("IMG_ERROR \(reason)")
        self.isImageDownloading = false
        self.imageDownloadProgress = 0
        // keep filename if any, but clear data
        self.receivedImage = nil
        self.receivedImageBytes = nil
    }
}
