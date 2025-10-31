//
//  BluetoothMappers.swift
//  CommonLibrary
//
//  Created by Serge Nes on 10/30/25.
//

import Foundation
import CoreBluetooth

public enum BluetoothMappers {
    @inlinable
    public static func powerState(from cbState: CBManagerState) -> BluetoothPowerState {
        switch cbState {
        case .unknown: return .unknown
        case .resetting: return .resetting
        case .unsupported: return .unsupported
        case .unauthorized: return .unauthorized
        case .poweredOff: return .poweredOff
        case .poweredOn: return .poweredOn
        @unknown default: return .unknown
        }
    }
}
