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
    let repository: BluetoothRepository = BluetoothRepository()
}
