//
//  BluetoothRepository.swift
//  BLEInteraction
//
//  Created by Serge Nes on 10/30/25.
//

import Foundation
import Combine
import CommonLibrary
import CoreBluetooth
import OSLog

@MainActor
final class BluetoothRepository: NSObject {
    // MARK: - Public Publishers
    private let devicesSubject = CurrentValueSubject<[BluetoothDevice], Never>([])
    private let powerStateSubject = CurrentValueSubject<BluetoothPowerState, Never>(.unknown)
    private let connectionStateSubject = CurrentValueSubject<BluetoothConnectionState, Never>(.idle)
    private let deviceDetailSubject = CurrentValueSubject<DeviceDetail?, Never>(nil)
    private let inboundTextSubject = PassthroughSubject<String, Never>()
    private let isScanningSubject = CurrentValueSubject<Bool, Never>(false)
    
    var devicesPublisher: AnyPublisher<[BluetoothDevice], Never> {
        devicesSubject
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    var powerStatePublisher: AnyPublisher<BluetoothPowerState, Never> {
        powerStateSubject
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    var connectionStatePublisher: AnyPublisher<BluetoothConnectionState, Never> {
        connectionStateSubject
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    var deviceDetailPublisher: AnyPublisher<DeviceDetail?, Never> {
        deviceDetailSubject
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    var inboundTextPublisher: AnyPublisher<String, Never> {
        inboundTextSubject
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    var isScanningPublisher: AnyPublisher<Bool, Never> {
        isScanningSubject
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    // MARK: - Private state
    private var central: CBCentralManager!
    private struct PeripheralEntry {
            let peripheral: CBPeripheral
            var lastRSSI: Int?
            var isConnectable: Bool?
            var lastLocalName: String?
            var preferredServiceUUID: UUID?
            var lastSeen: Date
        }
    // Parsed discovery container to keep didDiscover readable
    private struct DiscoveryInfo {
        let rssi: Int
        let isConnectable: Bool?
        let advName: String?
        let manufacturerData: Data
        let advertisedServiceUUIDs: [CBUUID]
    }
    private var peripherals: [UUID: PeripheralEntry] = [:]
    private var isScanning: Bool = false
    private var shouldScan: Bool = false
    
    // Stale discovery pruning
    private let staleTTL: TimeInterval = 6.0
    
    // Connection
    private var connectedPeripheral: CBPeripheral?
    private var notifyCharacteristic: CBCharacteristic?
    private var writeCharacteristic: CBCharacteristic?
    private var handshakeSent: Bool = false
    private var didRetryConnect: Bool = false
    private var autoConnectTargetId: UUID? = nil
    
    
    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        // Publish initial known state (may be .unknown until delegate updates)
        publishState(for: central.state)
    }
    
    // MARK: - BluetoothRepository (Connection & I/O)
    func connect(to device: BluetoothDevice) {
        // Stop scanning to improve stability, as requested
        stopScanning()
        Self.log.info("connect1: \(device.name)")
        Self.log.info("connect2: \(device.id)")
        guard let entry = peripherals[device.id] else {
            // Not in cache: try direct by identifier
            connect(to: device.id)
            return
        }
        
        let peripheral = entry.peripheral
        peripheral.services?.forEach { service in
            Self.log.info("service: \(service.uuid)")
        }
        
        prepareAndConnect(peripheral: peripheral,
                          name: device.name,
                          rssi: entry.lastRSSI,
                          isConnectable: entry.isConnectable,
                          preferredServiceUUID: entry.preferredServiceUUID)
    }
    
    // Connect by CoreBluetooth identifier (UUID)
    func connect(to identifier: UUID) {
        // If we're already connected to this device, skip
        if let p = connectedPeripheral, p.identifier == identifier, p.state == .connected {
            connectionStateSubject.send(.connected)
            return
        }
        // If we have it in cache, connect immediately
        if let entry = peripherals[identifier] {
            stopScanning()
            let peripheral = entry.peripheral
            let name = entry.lastLocalName ?? peripheral.name ?? "Unknown"
            prepareAndConnect(peripheral: peripheral,
                              name: name,
                              rssi: entry.lastRSSI,
                              isConnectable: entry.isConnectable,
                              preferredServiceUUID: entry.preferredServiceUUID)
            return
        }
        // Try to retrieve from system cache
        let found = central.retrievePeripherals(withIdentifiers: [identifier])
        if let peripheral = found.first {
            peripherals[identifier] = PeripheralEntry(
                peripheral: peripheral,
                lastRSSI: nil,
                isConnectable: nil,
                lastLocalName: nil,
                preferredServiceUUID: nil,
                lastSeen: Date()
            )
            stopScanning()
            let name = peripheral.name ?? "Unknown"
            prepareAndConnect(peripheral: peripheral,
                              name: name,
                              rssi: nil,
                              isConnectable: nil,
                              preferredServiceUUID: nil)
            return
        }
        // Could not retrieve: set target and start scanning until we see it
        autoConnectTargetId = identifier
        if central.state == .poweredOn {
            if !isScanning { startScanning() }
        } else {
            shouldScan = true
        }
        connectionStateSubject.send(.connecting)
    }

    func disconnect() {
        guard let p = connectedPeripheral else { return }
        // Proactively stop notifications to cleanly unsubscribe before canceling
        if let ch = notifyCharacteristic, p.state == .connected {
            p.setNotifyValue(false, for: ch)
        }
        central.cancelPeripheralConnection(p)
    }

    /// Clears any pending auto-connect target and retries flags. Call when returning to Discovery.
    func clearConnectionIntent() {
        autoConnectTargetId = nil
        didRetryConnect = false
        handshakeSent = false
    }

    // Unified preparation and connection logic
    private func prepareAndConnect(peripheral: CBPeripheral,
                                   name: String,
                                   rssi: Int?,
                                   isConnectable: Bool?,
                                   preferredServiceUUID: UUID?) {
        connectedPeripheral = peripheral
        notifyCharacteristic = nil
        writeCharacteristic = nil
        didRetryConnect = false

        let base = BluetoothDevice(id: peripheral.identifier,
                                   name: name,
                                   rssi: rssi,
                                   isConnectable: isConnectable,
                                   preferredServiceUUID: preferredServiceUUID)
        let detail = DeviceDetail(device: base,
                                  services: [],
                                  notifyCharacteristic: nil,
                                  writeCharacteristic: nil)
        deviceDetailSubject.send(detail)
        connectionStateSubject.send(.connecting)
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func send(text: String) {
        guard let ch = writeCharacteristic, let p = connectedPeripheral else { return }
        guard let data = text.data(using: .utf8) else { return }
        // Prefer writeWithoutResponse when supported to avoid peripherals that require
        // security/encryption for write-with-response. Fall back to withResponse only if needed.
        let props = ch.properties
        let type: CBCharacteristicWriteType = props.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        p.writeValue(data, for: ch, type: type)
    }

    func sendToggle(on: Bool) {
        // Simple textual protocol; adjust as needed for your device
        send(text: on ? TextProtocol.on : TextProtocol.off)
    }
    
    // MARK: - BluetoothRepository (Scanning)
    func setScanningEnabled(_ enabled: Bool) {
        shouldScan = enabled
        if enabled {
            startScanning()
        } else {
            stopScanning()
        }
    }

    private func startScanning() {
        shouldScan = true
        guard central.state == .poweredOn else { return }
        guard !isScanning else { return }
        isScanning = true
        isScanningSubject.send(true)
        // nil services -> discover all BLE devices
        let options: [String: Any] = [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        central.scanForPeripherals(withServices: nil, options: options)
    }

    private func stopScanning() {
        shouldScan = false
        guard isScanning else { return }
        isScanning = false
        isScanningSubject.send(false)
        central.stopScan()
    }
    
    // MARK: - Helpers
    /// Resets local connection-related state without emitting a connection state event.
    private func cleanState() {
        connectedPeripheral = nil
        notifyCharacteristic = nil
        writeCharacteristic = nil
        handshakeSent = false
        deviceDetailSubject.send(nil)
    }
    
    private func publishState(for cbState: CBManagerState) {
        let state = BluetoothMappers.powerState(from: cbState)
        powerStateSubject.send(state)
        if cbState == .poweredOn, shouldScan, !isScanning {
            startScanning()
        }
        if cbState == .poweredOff {
            // Stop scanning and clear cache as radios are off
            if isScanning { stopScanning() }
            peripherals.removeAll()
            emitDevices()
        }
    }

    private func emitDevices() {
        let now = Date()
        let cutoff = now.addingTimeInterval(-staleTTL)
        let connectedId = connectedPeripheral?.identifier
        let filteredEntries = peripherals.values.filter { entry in
            if let connectedId, entry.peripheral.identifier == connectedId { return true }
            return entry.lastSeen >= cutoff
        }
        let models: [BluetoothDevice] = filteredEntries.map { entry in
            let advName = entry.lastLocalName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (advName?.isEmpty == false ? advName! : nil)
                ?? entry.peripheral.name
                ?? "Unknown"
            return BluetoothDevice(
                id: entry.peripheral.identifier,
                name: name,
                rssi: entry.lastRSSI,
                isConnectable: entry.isConnectable,
                preferredServiceUUID: entry.preferredServiceUUID
            )
        }
        // Sort by RSSI desc (strongest first), Unknowns last; then by name for stable order
        let sorted = models.filter { device in
            if let rssi = device.rssi {
                return rssi < 0
            }
            return false
        }
        .sorted { a, b in
            if let ra = a.rssi, let rb = b.rssi {
                return ra > rb          // stronger signal first
            } else {
                return a.name < b.name  // fallback (theoretically never reached)
            }
        }
        devicesSubject.send(sorted)
    }

    // MARK: - Discovery helpers (split from didDiscover)
    private func parseDiscoveryInfo(from advertisementData: [String: Any], rssi: NSNumber) -> DiscoveryInfo {
        let isConnectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue
        // Prefer CoreBluetooth-provided advertised local name when available
        let advName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let manufacturerData = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data) ?? Data()
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        return DiscoveryInfo(
            rssi: rssi.intValue,
            isConnectable: isConnectable,
            advName: (advName?.isEmpty == false ? advName! : nil),
            manufacturerData: manufacturerData,
            advertisedServiceUUIDs: serviceUUIDs
        )
    }

    private func upsertPeripheralEntry(for peripheral: CBPeripheral, with info: DiscoveryInfo) {
        var entry = peripherals[peripheral.identifier] ?? PeripheralEntry(
            peripheral: peripheral,
            lastRSSI: nil,
            isConnectable: nil,
            lastLocalName: nil,
            preferredServiceUUID: nil,
            lastSeen: Date()
        )
        entry.lastRSSI = info.rssi
        entry.isConnectable = info.isConnectable
        if let name = info.advName, !name.isEmpty {
            entry.lastLocalName = name
        }
        entry.lastSeen = Date()
        // Capture advertised service UUIDs; prefer NUS when present, else first
        let cbuuids = info.advertisedServiceUUIDs
        if !cbuuids.isEmpty {
            if cbuuids.contains(Gatt.Service.nusServiceUUID) {
                entry.preferredServiceUUID = UUID(uuidString: Gatt.Service.nusServiceUUID.uuidString)
            } else if let first = cbuuids.first {
                entry.preferredServiceUUID = UUID(uuidString: first.uuidString)
            }
        }
        peripherals[peripheral.identifier] = entry
        // Optional manufacturer data logging can be added here if needed
        if !info.manufacturerData.isEmpty {
            // Self.log.info("Manufacturer Data: \(info.manufacturerData.manufacturerSummary())")
        }
    }

    private func handleAutoConnectIfNeeded(for peripheral: CBPeripheral) {
        // Auto-connect if this is the target we're waiting for
        if let target = autoConnectTargetId, target == peripheral.identifier {
            autoConnectTargetId = nil
            connect(to: target)
        }
    }

    private func updateDeviceDetail(services: [CBService]?) {
        guard let p = connectedPeripheral else { return }
        let serviceUUIDs = services?.map { $0.uuid.uuidString }.compactMap { UUID(uuidString: $0) } ?? []
        let cached = peripherals[p.identifier]
        let advName = cached?.lastLocalName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = (advName?.isEmpty == false ? advName! : nil) ?? p.name ?? "Unknown"
        let detail = DeviceDetail(
            id: p.identifier,
            name: resolvedName,
            rssi: cached?.lastRSSI,
            isConnectable: cached?.isConnectable,
            services: serviceUUIDs,
            notifyCharacteristic: notifyCharacteristic.flatMap { UUID(uuidString: $0.uuid.uuidString) },
            writeCharacteristic: writeCharacteristic.flatMap { UUID(uuidString: $0.uuid.uuidString) }
        )
        deviceDetailSubject.send(detail)
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothRepository: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        publishState(for: central.state)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Parse and normalize raw discovery inputs
        let info = parseDiscoveryInfo(from: advertisementData, rssi: RSSI)
        // Upsert/refresh our cached entry for this peripheral
        upsertPeripheralEntry(for: peripheral, with: info)
        // Notify UI about updated device list
        emitDevices()
        // Handle pending auto-connect intent if this is the target
        handleAutoConnectIfNeeded(for: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionStateSubject.send(.connected)
        handshakeSent = false
        // Prefer discovering the Nordic UART Service first; fallback handled in didDiscoverServices
        peripheral.discoverServices([Gatt.Service.nusServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        // One-shot retry to smooth over brief host advertising restarts after rename
        if didRetryConnect == false {
            didRetryConnect = true
            connectionStateSubject.send(.connecting)
            let p = peripheral
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self = self else { return }
                p.delegate = self
                central.connect(p, options: nil)
            }
        } else {
            // Final failure: clean local state to allow future reconnects
            connectedPeripheral?.delegate = nil
            cleanState()
            connectionStateSubject.send(.failed(error ?? NSError(domain: "BT", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to connect"])) )
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // Clean up all state so we can reconnect cleanly later without restarting the app
        peripheral.delegate = nil
        didRetryConnect = false
        cleanState()
        connectionStateSubject.send(.disconnected(error))
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothRepository: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        updateDeviceDetail(services: peripheral.services)
        guard let services = peripheral.services else {
            // If no services returned (e.g., we filtered by NUS and it's unavailable), fallback to discover all
            peripheral.discoverServices(nil)
            return
        }
        if let nus = services.first(where: { $0.uuid == Gatt.Service.nusServiceUUID }) {
            // Prefer discovering just the expected UART characteristics
            peripheral.discoverCharacteristics([Gatt.Characteristic.nusTXUUID, Gatt.Characteristic.nusRXUUID], for: nus)
        } else {
            // Fallback: discover all characteristics for all services
            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }

        // Prefer Nordic UART UUID mapping when available for this service
        if service.uuid == Gatt.Service.nusServiceUUID {
            if notifyCharacteristic == nil {
                if let tx = chars.first(where: { $0.uuid == Gatt.Characteristic.nusTXUUID }) {
                    notifyCharacteristic = tx
                    peripheral.setNotifyValue(true, for: tx)
                }
            }
            if writeCharacteristic == nil {
                if let rx = chars.first(where: { $0.uuid == Gatt.Characteristic.nusRXUUID }) {
                    writeCharacteristic = rx
                }
            }
        }

        // Fallback heuristics if still not selected
        if notifyCharacteristic == nil {
            if let notify = chars.first(where: { $0.properties.contains(.notify) || $0.properties.contains(.indicate) }) {
                notifyCharacteristic = notify
                peripheral.setNotifyValue(true, for: notify)
            }
        }
        if writeCharacteristic == nil {
            if let w = chars.first(where: { $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse) }) {
                writeCharacteristic = w
            }
        }

        // If we have a write characteristic and haven't sent handshake yet, send a HELLO
        if let _ = writeCharacteristic, handshakeSent == false {
            let now = ISO8601DateFormatter().string(from: Date())
            let hello = "HELLO from Central @ \(now)"
            send(text: hello)
            handshakeSent = true
        }

        updateDeviceDetail(services: peripheral.services)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else { return }
        guard let data = characteristic.value else { return }
        let string: String
        if let s = String(data: data, encoding: .utf8), !s.isEmpty {
            string = s
        } else {
            let hex = data.map { String(format: "%02X", $0) }.joined()
            string = "0x" + (hex.count > 512 ? String(hex.prefix(512)) + "…" : hex)
        }
        inboundTextSubject.send(string)
    }
}

extension BluetoothRepository {
    static let log = Logger(subsystem: "com.answers.assesment", category: "\(DiscoveryViewModel.self)")
}
