//
//  NotificationManager.swift
//  ScannerQ
//
//  Created by Serge Nes on 11/12/25.
//

import UserNotifications
import UIKit

class NotificationManager {
    static let shared = NotificationManager()
    
    func scheduleNotification(title: String,
                            body: String,
                            delay: TimeInterval = 5,
                            userInfo: [AnyHashable: Any] = [:]) {
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = NSNumber(value: UIApplication.shared.applicationIconBadgeNumber + 1)
        content.userInfo = userInfo
        
        // Add custom data
        content.userInfo["customKey"] = "test"
        
        // Optional: Add image attachment
        // if let imageURL = Bundle.main.url(forResource: "image", withExtension: "png"),
        //    let attachment = try? UNNotificationAttachment(identifier: "image", url: imageURL) {
        //    content.attachments = [attachment]
        // }
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error.localizedDescription)")
            } else {
                print("Notification scheduled successfully")
            }
        }
    }
    
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    
    func getPendingNotifications(completion: @escaping ([UNNotificationRequest]) -> Void) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            completion(requests)
        }
    }
    
    func clearDeliveredAndResetBadge() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }
}
