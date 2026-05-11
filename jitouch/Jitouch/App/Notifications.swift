import Foundation

extension Notification.Name {
    static let jitouchPreferencesDidChange = Notification.Name("com.zhuanz.JitouchModern.preferencesDidChange")
    static let jitouchRuntimeDidChange = Notification.Name("com.zhuanz.JitouchModern.runtimeDidChange")
}

enum NotificationObject {
    static let preferencePaneToApp = "com.zhuanz.JitouchModern.preferences"
    static let appToPreferencePane = "com.zhuanz.JitouchModern.runtime"
}
