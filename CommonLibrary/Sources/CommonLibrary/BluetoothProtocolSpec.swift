//
//  BluetoothProtocolSpec.swift
//  CommonLibrary
//
//  Created by Serge Nes on 10/30/25.
//

import Foundation
import Combine

import CoreBluetooth

extension CBUUID {
   public func toUUID() -> UUID {
        UUID(uuidString: uuidString)!
   }
}

public enum Gatt {
    
    public enum Service {
        // Use computed properties to avoid storing non-Sendable CoreBluetooth types across actors.
        // Returning a fresh CBUUID each access is cheap and concurrency-safe.
        public static var nusServiceUUID: CBUUID { CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E") }
    }
    
    public enum Characteristic {
        // Nordic UART Service (NUS) standard mapping:
        // RX (Peripheral receives from Central) -> Central writes to this characteristic
        public static var nusRXUUID: CBUUID { CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E") } // write
        // TX (Peripheral transmits to Central) -> Central subscribes (notify) to this characteristic
        public static var nusTXUUID: CBUUID { CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E") } // notify
        // Backwards-compat alias for older references
        public static var notify: CBUUID { nusTXUUID }
    }
}

public enum BluetoothAuthorizationStatus {
    case notDetermined
    case restricted
    case denied
    case allowed
}

public enum BluetoothPowerState {
    case unknown
    case resetting
    case unsupported
    case unauthorized
    case poweredOff
    case poweredOn
}

public enum BluetoothConnectionState: Equatable {
    case idle
    case connecting
    case connected
    case failed(Error)
    case disconnected(Error?)
}

public struct DeviceDetail: Equatable {
    public let device: BluetoothDevice
    public let services: [UUID]
    public let notifyCharacteristic: UUID?
    public let writeCharacteristic: UUID?

    // Primary initializer using composition
    public init(device: BluetoothDevice, services: [UUID], notifyCharacteristic: UUID?, writeCharacteristic: UUID?) {
        self.device = device
        self.services = services
        self.notifyCharacteristic = notifyCharacteristic
        self.writeCharacteristic = writeCharacteristic
    }

    // Temporary shim initializer to ease migration from the old layout
    // Allows constructing DeviceDetail with discrete fields; internally builds a BluetoothDevice.
    public init(id: UUID, name: String, rssi: Int?, isConnectable: Bool?, services: [UUID], notifyCharacteristic: UUID?, writeCharacteristic: UUID?, preferredServiceUUID: UUID? = nil) {
        self.device = BluetoothDevice(id: id, name: name, rssi: rssi, isConnectable: isConnectable, preferredServiceUUID: preferredServiceUUID)
        self.services = services
        self.notifyCharacteristic = notifyCharacteristic
        self.writeCharacteristic = writeCharacteristic
    }
}

public extension BluetoothConnectionState {
    static func == (lhs: BluetoothConnectionState, rhs: BluetoothConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.connecting, .connecting),
             (.connected, .connected):
            return true
        case (.failed, .failed):
            return true
        case (.disconnected, .disconnected):
            return true
        default:
            return false
        }
    }
}
