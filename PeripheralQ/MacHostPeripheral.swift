//
//  MacHostPeripheral.swift
//  PeripheralQ
//  PeripheralQ: macOS Host Mode implementation using CBPeripheralManager
//
//  Created by Serge Nes on 10/30/25.


import Foundation
import CoreBluetooth
import Combine
import CommonLibrary
import OSLog

@MainActor
final class MacHostPeripheral: NSObject {
    enum State: Equatable {
        case idle
        case ready
        case advertising
        case connected(centralID: UUID?)
        case failed(String)
        case disconnected
    }

    // Public observable state
    @Published private(set) var state: State = .idle
    @Published private(set) var inboundMessages: [String] = []
    @Published private(set) var remoteToggleOn: Bool = false
    
    // Selected image to serve on GET_IMAGE
    private var selectedImageURL: URL? = nil

    // Config
    struct Config: Equatable {
        var localName: String
        var serviceUUID: CBUUID
    }
    @Published private(set) var config: Config

    // BLE
    private var pm: CBPeripheralManager!
    private var service: CBMutableService?
    private var rxCharacteristic: CBMutableCharacteristic?
    private var txCharacteristic: CBMutableCharacteristic?

    private var subscribedCentrals: [CBCentral] = []

    // Notify backpressure queue 
    private var notifyQueue: [Data] = []

    // Lifecycle flags
    private var desiredAdvertise: Bool = false
    private var isServiceAdded: Bool = false

    override init() {
        // Default config
        self.config = Config(localName: "QDevice1", serviceUUID: Gatt.Service.nusServiceUUID)
        super.init()
        self.pm = CBPeripheralManager(delegate: self, queue: .main)
    }

    // MARK: - Public API
    func update(config: Config) {
        self.config = config
        // If advertising, restart to apply changes
        if case .advertising = state {
            restartAdvertising()
        }
    }

    func startHosting() {
        switch pm.state {
        case .poweredOn:
            setupGattIfNeeded()
            startAdvertising()
        default:
            desiredAdvertise = true
        }
    }

    func stopHosting() {
        desiredAdvertise = false
        notifyQueue.removeAll()
        if pm.isAdvertising { pm.stopAdvertising() }
        pm.removeAllServices()
        service = nil
        rxCharacteristic = nil
        txCharacteristic = nil
        isServiceAdded = false
        state = .ready
    }

    func send(text: String) {
        guard let ch = txCharacteristic, let data = text.data(using: .utf8) else { return }
        _ = pm.updateValue(data, for: ch, onSubscribedCentrals: nil)
    }

    // MARK: - Internals
    private func setupGattIfNeeded() {
        guard service == nil else { return }
        let s = CBMutableService(type: config.serviceUUID, primary: true)
        let rx = CBMutableCharacteristic(type: Gatt.Characteristic.nusRXUUID, properties: [.write, .writeWithoutResponse], value: nil, permissions: [.writeable])
        let tx = CBMutableCharacteristic(type: Gatt.Characteristic.nusTXUUID, properties: [.notify], value: nil, permissions: [.readable])
        s.characteristics = [rx, tx]
        isServiceAdded = false
        pm.add(s)
        self.service = s
        self.rxCharacteristic = rx
        self.txCharacteristic = tx
    }

    private func startAdvertising() {
        desiredAdvertise = true
        guard pm.state == .poweredOn else { return }
        guard isServiceAdded, service != nil else { return }
        let adv: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [config.serviceUUID],
            CBAdvertisementDataLocalNameKey: config.localName
        ]
        Self.log.info("startAdvertising: \(self.config.serviceUUID.uuidString)\n Name: \(self.config.localName)\n \(self.service)")
        pm.startAdvertising(adv)
        state = .advertising
    }

    private func restartAdvertising() {
        if pm.isAdvertising { pm.stopAdvertising() }
        startAdvertising()
    }

    func setSelectedImageURL(_ url: URL?) {
        selectedImageURL = url
    }

    private func sendText(_ s: String) {
        if let d = s.data(using: .utf8) { enqueueNotify(d) }
    }

    private func sendSelectedImageOrError() {
        guard let url = selectedImageURL else {
            sendText(TextProtocol.imgError + " no_file_selected")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            // Basic sanity check: ensure it's a PNG by signature
            if data.count >= 8 {
                let sig = [UInt8](data.prefix(8))
                let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
                guard sig.elementsEqual(pngMagic) else {
                    sendText(TextProtocol.imgError + " not_png")
                    return
                }
            }
            let filename = url.lastPathComponent
            let total = data.count
            sendText("\(TextProtocol.imgBegin) \(filename) \(total)")
            let b64 = data.base64EncodedString()
            let chunkSize = 180
            var idx = b64.startIndex
            while idx < b64.endIndex {
                let next = b64.index(idx, offsetBy: chunkSize, limitedBy: b64.endIndex) ?? b64.endIndex
                let slice = String(b64[idx..<next])
                sendText(slice)
                idx = next
            }
            sendText(TextProtocol.imgEnd)
        } catch {
            sendText(TextProtocol.imgError + " read_failed")
        }
    }

    private func handleWrites(_ requests: [CBATTRequest]) {
        for req in requests {
            if req.characteristic.uuid == rxCharacteristic?.uuid, let data = req.value {
                pm.respond(to: req, withResult: .success)
                if let text = String(data: data, encoding: .utf8) {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let upper = trimmed.uppercased()
                    if upper == TextProtocol.on {
                        remoteToggleOn = true
                    } else if upper == TextProtocol.off {
                        remoteToggleOn = false
                    } else if upper == TextProtocol.get || upper == TextProtocol.getImage {
                        sendSelectedImageOrError()
                    } else {
                        inboundMessages.append(truncate(trimmed, max: 500))
                    }
                } else {
                    let hex = data.map { String(format: "%02X", $0) }.joined()
                    inboundMessages.append("0x" + (hex.count > 512 ? String(hex.prefix(512)) + "…" : hex))
                }
            } else {
                pm.respond(to: req, withResult: .requestNotSupported)
            }
        }
    }

    private func enqueueNotify(_ data: Data) {
        guard let ch = txCharacteristic else { return }
        if pm.updateValue(data, for: ch, onSubscribedCentrals: nil) == false {
            notifyQueue.append(data)
        }
    }

    private func flushQueue() {
        guard let ch = txCharacteristic else { return }
        while !notifyQueue.isEmpty {
            let data = notifyQueue.first!
            if pm.updateValue(data, for: ch, onSubscribedCentrals: nil) {
                notifyQueue.removeFirst()
            } else { break }
        }
        if notifyQueue.count > 100 { notifyQueue.removeFirst(notifyQueue.count - 100) }
    }

    private func startTicker() {
        let now = ISO8601DateFormatter().string(from: Date())
        let hello = "HELLO from macOS Host @ \(now)"
        if let d = hello.data(using: .utf8) { enqueueNotify(d) }
    }

    private func resetAfterDisconnectIfNoSubscribers() {
        if subscribedCentrals.isEmpty {
            notifyQueue.removeAll()
            // Reset transient remote state so a fresh connection starts cleanly
            remoteToggleOn = false
            state = .advertising
        }
    }

    private func truncate(_ s: String, max: Int) -> String {
        if s.count <= max { return s }
        let idx = s.index(s.startIndex, offsetBy: max)
        return String(s[..<idx]) + "…"
    }
}

extension MacHostPeripheral: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            state = .ready
            setupGattIfNeeded()
            if desiredAdvertise { startAdvertising() }
        case .poweredOff: state = .idle
        case .resetting: state = .idle
        case .unsupported: state = .failed("Unsupported on macOS")
        case .unauthorized: state = .failed("Unauthorized")
        case .unknown: state = .idle
        @unknown default: state = .idle
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let e = error { isServiceAdded = false; state = .failed("Add service failed: \(e.localizedDescription)") }
        else {
            isServiceAdded = true
            if desiredAdvertise && !peripheral.isAdvertising { startAdvertising() }
        }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let e = error { state = .failed("Advertising failed: \(e.localizedDescription)") }
        else { state = .advertising }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        let mtu = central.maximumUpdateValueLength  // <— This is available!
        print("Central MTU: \(mtu) bytes")
        if !subscribedCentrals.contains(where: { $0.identifier == central.identifier }) {
            subscribedCentrals.append(central)
        }
        state = .connected(centralID: central.identifier)
        startTicker(); flushQueue()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscribedCentrals.removeAll { $0.identifier == central.identifier }
        let anyLeft = !subscribedCentrals.isEmpty
        if anyLeft {
            state = .connected(centralID: subscribedCentrals.first?.identifier)
        } else {
            resetAfterDisconnectIfNoSubscribers()
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        handleWrites(requests)
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        flushQueue()
    }
}


extension MacHostPeripheral {
    static let log = Logger(subsystem: "com.answers.assesment", category: "\(MacHostPeripheral.self)")
}
