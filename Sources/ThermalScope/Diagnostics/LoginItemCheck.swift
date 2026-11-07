import AppKit
import CoreServices
import ThermalCore

@MainActor enum LoginItemCheck {
    private final class Access:LoginItemAccess {
        var state:LoginItemState = .off
        var reject=false
        var requests:[Bool]=[]
        func read() throws -> LoginItemState {state}
        func setEnabled(_ value:Bool) throws {
            requests.append(value)
            if reject {throw ScopeError.message("fixture rejection")}
            state=value ? .enabled:.off
        }
        func openSettings(){}
    }
    static func run() {
        guard CommandLine.arguments.contains("--ui-check") else {exit(2)}
        do {try check();print("PASS: login registration uses OS state, rejects failed registration, refreshes external changes, preserves approval state, detects silent launches; macOS 11–12 plist round trip and symlink rejection. Isolated fixtures only; no real login items changed.");exit(0)}
        catch {print("FAIL: \(error.localizedDescription)");exit(1)}
    }
    private static func require(_ value:Bool,_ message:String)throws {if !value {throw ScopeError.message(message)}}
    private static func check() throws {
        let access=Access(),model=LoginItemController(access:access)
        try require(!model.enabled && access.requests.isEmpty,"Login startup enabled without a click")
        model.setEnabled(true);model.setEnabled(true)
        try require(model.enabled && access.requests==[true],"Duplicate registration or stale state")
        access.state = .off;model.refresh()
        try require(!model.enabled,"External disable was ignored")
        access.reject=true;model.setEnabled(true)
        try require(!model.enabled && model.error != nil,"Rejected registration appears enabled")
        access.state = .requiresApproval;model.refresh()
        try require(model.enabled && model.state == .requiresApproval && model.error==nil,"Approval request not preserved")
        access.reject=false;model.setEnabled(false)
        try require(!model.enabled,"Pending registration could not be disabled")
        try require(!LoginLaunch.isAutomatic(arguments:["showmac"],event:nil),"Manual launch treated as a login item")
        try require(LoginLaunch.isAutomatic(arguments:["showmac","--login-item"],event:nil),"Legacy login flag ignored")
        let properties=NSAppleEventDescriptor.record()
        properties.setDescriptor(NSAppleEventDescriptor(boolean:true),forKeyword:AEKeyword(keyAELaunchedAsLogInItem))
        let event=NSAppleEventDescriptor.record()
        event.setParam(properties,forKeyword:AEKeyword(keyAEPropData))
        try require(LoginLaunch.isAutomatic(arguments:["showmac"],event:event),"System login launch event ignored")

        let root=FileManager.default.temporaryDirectory.appendingPathComponent("showmac-login-"+UUID().uuidString,isDirectory:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let app=root.appendingPathComponent("Show Mac 演示.app",isDirectory:true)
        let executable=app.appendingPathComponent("Contents/MacOS/ThermalScope")
        try FileManager.default.createDirectory(at:executable.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data("fixture".utf8).write(to:executable)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:executable.path)
        let legacy=LegacyLoginItem(directory:root.appendingPathComponent("LaunchAgents"),app:app)
        try require(try !legacy.isEnabled(),"Fresh compatibility registration is enabled")
        try legacy.setEnabled(true)
        try require(try legacy.isEnabled(),"Legacy registration did not survive readback")
        let plist=try PropertyListSerialization.propertyList(from:Data(contentsOf:legacy.file),format:nil) as! [String:Any]
        try require(plist["KeepAlive"]==nil && plist["LimitLoadToSessionType"] as? String == "Aqua","Login item respawns or runs outside GUI login")
        try require((plist["ProgramArguments"] as? [String])?[3]==app.path,"Spaces/Unicode app path not preserved")
        try legacy.setEnabled(false);try legacy.setEnabled(false)
        try require(try !legacy.isEnabled(),"Legacy disable failed")
        let foreign=root.appendingPathComponent("untouched.txt")
        try Data("unchanged".utf8).write(to:foreign)
        try FileManager.default.createSymbolicLink(at:legacy.file,withDestinationURL:foreign)
        var rejected=false
        do {try legacy.setEnabled(true)} catch {rejected=true}
        try require(rejected,"Symlink registration was accepted")
        try require(try String(contentsOf:foreign)=="unchanged","Foreign file was changed")
    }
}
