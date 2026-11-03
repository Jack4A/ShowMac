import Foundation

public enum AppDistribution {
    public static var isAppStore:Bool {
        #if APP_STORE
        return true
        #else
        return false
        #endif
    }
    public static var hardwareControlAvailable:Bool {!isAppStore}
    public static let monitoringOnlyMessage="App Store 版仅监测硬件状态，风扇转速由系统或其他控制器管理。"
}
