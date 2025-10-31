//
//  PeripheralQApp.swift
//  PeripheralQ
//
//  Created by Serge Nes on 10/30/25.
//

import SwiftUI

@main
struct PeripheralQApp: App {
    @StateObject private var vm = MacHostViewModel()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
        }
        .commands {
            CommandMenu("File") {
                Button("Select Image…") { vm.selectImage() }
                    .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
}
