//
//  ScannerQApp.swift
//  ScannerQ
//
//  Created by Serge Nes on 10/30/25.
//

import SwiftUI
import UserNotifications
import BackgroundTasks

class BackgroundCommandHandler {
    static let shared = BackgroundCommandHandler()
    
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.answers.assesment.command", using: nil) { task in
            self.handleBackgroundCommand(task: task as! BGProcessingTask)
        }
    }
    
    func scheduleBackgroundTask() {
        let request = BGProcessingTaskRequest(identifier: "com.answers.assesment.command")
        request.requiresNetworkConnectivity = true
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule background task: \(error)")
        }
    }
    
    func handleBackgroundCommand(task: BGProcessingTask) {
        // Fetch your command from server or local storage
        let command = "Update data"
        
        // Show notification
        NotificationManager.shared.scheduleNotification(
            title: "Background Command",
            body: command,
            delay: 1,
            userInfo: ["command": command]
        )
        
        // Complete the background task
        task.setTaskCompleted(success: true)
    }
}

class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    
    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        
        // Process the notification
        if let command = userInfo["command"] as? String {
            print("Received command in foreground: \(command)")
        }
        
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        if let command = userInfo["command"] as? String {
            print("User tapped notification with command: \(command)")
            // Handle the command action
        }
        
        // Clear delivered notifications and reset badge when user taps
        NotificationManager.shared.clearDeliveredAndResetBadge()
        
        completionHandler()
    }
}

@main
struct ScannerQApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var deps = AppDependencies()
    
    var body: some Scene {
        WindowGroup {
            SplashScreenView()
                .onAppear {
                   requestNotificationPermission()
                }
                .environmentObject(deps)
        }
    }
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

}
