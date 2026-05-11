import Foundation

extension Notification.Name {
    static let jitouchPreferencesDidChange = Notification.Name("My Notification")
    static let jitouchRuntimeDidChange = Notification.Name("My Notification2")
}

enum NotificationObject {
    static let preferencePaneToApp = "com.jitouch.Jitouch.PrefpaneTarget"
    static let appToPreferencePane = "com.jitouch.Jitouch.PrefpaneTarget2"
}
