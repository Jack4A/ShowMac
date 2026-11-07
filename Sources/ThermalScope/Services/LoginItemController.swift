import AppKit
import CoreServices
import ServiceManagement
import ThermalCore

enum LoginItemState:Equatable {case off,enabled,requiresApproval}

enum LoginLaunch {
    static func isAutomatic(arguments:[String],event:NSAppleEventDescriptor?)->Bool {
        arguments.contains("--login-item") || event?.paramDescriptor(forKeyword:AEKeyword(keyAEPropData))?
            .paramDescriptor(forKeyword:AEKeyword(keyAELaunchedAsLogInItem))?.booleanValue == true
    }
}

@MainActor protocol LoginItemAccess:AnyObject {
    func read() throws -> LoginItemState
    func setEnabled(_ enabled:Bool) throws
    func openSettings()
}

/// Display the OS registration state, rather than a preference that can drift from it.
@MainActor final class LoginItemController:ObservableObject {
    @Published private(set) var state:LoginItemState = .off
    @Published private(set) var error:String?
    private let access:LoginItemAccess
    var enabled:Bool {state != .off}
    init(access:LoginItemAccess?=nil,preview:Bool=false) {
        self.access=access ?? (preview ? PreviewLoginItemAccess():NativeLoginItemAccess())
        refresh()
    }
    func refresh() {
        do {state=try access.read();error=nil}
        catch {self.error=error.localizedDescription}
    }
    func setEnabled(_ value:Bool) {
        guard value != enabled || error != nil else{return}
        do {try access.setEnabled(value);state=try access.read();error=nil}
        catch {self.error=error.localizedDescription;state=(try? access.read()) ?? state}
    }
    func openSettings(){access.openSettings()}
}

@MainActor final class PreviewLoginItemAccess:LoginItemAccess {
    var state:LoginItemState = .off
    func read() throws -> LoginItemState {state}
    func setEnabled(_ enabled:Bool) throws {state=enabled ? .enabled:.off}
    func openSettings(){}
}

@MainActor private final class NativeLoginItemAccess:LoginItemAccess {
    private let legacy=LegacyLoginItem()
    func read() throws -> LoginItemState {
        if #available(macOS 13,*) {
            switch SMAppService.mainApp.status {
            case .enabled:return .enabled
            case .requiresApproval:return .requiresApproval
            default:break
            }
        }
        return try legacy.isEnabled() ? .enabled:.off
    }
    func setEnabled(_ enabled:Bool) throws {
        if #available(macOS 13,*) {
            if enabled {
                if SMAppService.mainApp.status != .enabled {try SMAppService.mainApp.register()}
                // Remove our old-system registration only after the new one succeeds.
                try legacy.setEnabled(false)
            } else {
                if [.enabled,.requiresApproval].contains(SMAppService.mainApp.status) {try SMAppService.mainApp.unregister()}
                try legacy.setEnabled(false)
            }
        } else {try legacy.setEnabled(enabled)}
    }
    func openSettings() {
        if #available(macOS 13,*) {SMAppService.openSystemSettingsLoginItems()}
        else if let url=URL(string:"x-apple.systempreferences:com.apple.preferences.users?LoginItems") {NSWorkspace.shared.open(url)}
    }
}

/// macOS 11–12 compatibility: a per-user, one-shot GUI login task; no root helper.
struct LegacyLoginItem {
    static let label="cc.showmac.login"
    let directory:URL
    let app:URL
    init(directory:URL=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents",isDirectory:true),app:URL=Bundle.main.bundleURL) {
        self.directory=directory;self.app=app
    }
    var file:URL {directory.appendingPathComponent(Self.label+".plist")}
    private var arguments:[String] {["/usr/bin/open","-g","-a",app.path,"--args","--login-item"]}
    private func existing() throws -> [String:Any]? {
        guard FileManager.default.fileExists(atPath:file.path) else{return nil}
        let attributes=try FileManager.default.attributesOfItem(atPath:file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let data=try PropertyListSerialization.propertyList(from:Data(contentsOf:file),format:nil) as? [String:Any],
              data["Label"] as? String == Self.label,
              let args=data["ProgramArguments"] as? [String],args.count==6,
              Array(args.prefix(3))==["/usr/bin/open","-g","-a"],Array(args.suffix(2))==["--args","--login-item"] else {
            throw ScopeError.message(L("登录启动配置无法读取，请在系统设置中检查。"))
        }
        return data
    }
    func isEnabled() throws -> Bool {
        guard let data=try existing() else{return false}
        return data["ProgramArguments"] as? [String] == arguments && data["RunAtLoad"] as? Bool == true
    }
    func setEnabled(_ enabled:Bool) throws {
        _=try existing() // Never overwrite an unrelated file or follow a file symlink.
        if enabled {
            guard app.pathExtension=="app",FileManager.default.isExecutableFile(atPath:app.appendingPathComponent("Contents/MacOS/ThermalScope").path) else {
                throw ScopeError.message(L("请先将 ShowMac 放入应用程序文件夹。"))
            }
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let plist:[String:Any] = ["Label":Self.label,"ProgramArguments":arguments,"RunAtLoad":true,"LimitLoadToSessionType":"Aqua","ProcessType":"Background"]
            try PropertyListSerialization.data(fromPropertyList:plist,format:.xml,options:0).write(to:file,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
        } else if FileManager.default.fileExists(atPath:file.path) {try FileManager.default.removeItem(at:file)}
    }
}
