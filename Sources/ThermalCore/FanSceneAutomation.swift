import Foundation

public struct FanApplication:Codable,Hashable,Identifiable {
    public var bundleID:String
    public var name:String
    public var id:String {bundleID}
    public init(bundleID:String,name:String) {self.bundleID=bundleID;self.name=name}
    public var isValid:Bool {
        let allowed=CharacterSet(charactersIn:"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return !bundleID.isEmpty && bundleID.utf8.count<=255 && bundleID.unicodeScalars.allSatisfy{allowed.contains($0)} &&
            !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && name.utf8.count<=160 &&
            !name.unicodeScalars.contains{CharacterSet.controlCharacters.contains($0)}
    }
}

public struct FanApplicationRule:Codable,Equatable,Identifiable {
    public var application:FanApplication
    public var sceneID:String
    public var id:String {application.bundleID}
    public init(application:FanApplication,sceneID:String) {self.application=application;self.sceneID=sceneID}
}

public struct FanAutomationDecision:Equatable {
    public var selection:FanModeSelection
    public var application:FanApplication?
}

/// Only app identities and explicit user mappings are stored. No process contents or window access.
public struct FanSceneAutomation:Codable,Equatable {
    public static let limit=128
    public var enabled:Bool
    public var rules:[FanApplicationRule]
    public var manualSelection:FanModeSelection
    public init(enabled:Bool=false,rules:[FanApplicationRule]=[],manualSelection:FanModeSelection = .strategy(.system)) {
        self.enabled=enabled;self.rules=rules;self.manualSelection=manualSelection
    }
    public static func decode(_ data:Data?,scenes:[FanScene])->Self {
        guard let data,data.count<=131072,var value=try? JSONDecoder().decode(Self.self,from:data) else{return Self()}
        let ids=Set(scenes.map(\.id));var apps=Set<String>()
        value.rules=value.rules.filter {
            guard $0.application.isValid,ids.contains($0.sceneID),apps.insert($0.id).inserted else{return false}
            return true
        }.prefix(limit).map{$0}
        if case .scene(let id)=value.manualSelection,!ids.contains(id) {value.manualSelection = .strategy(.system)}
        return value
    }
    public mutating func associate(_ app:FanApplication,with sceneID:String)throws {
        guard app.isValid,UUID(uuidString:sceneID) != nil else {throw ScopeError.message("无法识别这个应用或场景")}
        if let index=rules.firstIndex(where:{$0.id==app.id}) {rules[index] = .init(application:app,sceneID:sceneID)}
        else {
            guard rules.count<Self.limit else {throw ScopeError.message("最多关联 128 个应用")}
            rules.append(.init(application:app,sceneID:sceneID))
        }
    }
    public mutating func removeApplication(_ bundleID:String) {rules.removeAll{$0.id==bundleID}}
    public mutating func removeScene(_ sceneID:String) {
        rules.removeAll{$0.sceneID==sceneID}
        if manualSelection == .scene(sceneID) {manualSelection = .strategy(.system)}
    }
    public func decision(running:[FanApplication],frontmost:String?,current:String?,scenes:[FanScene])->FanAutomationDecision? {
        guard enabled else{return nil}
        let runningIDs=Set(running.filter(\.isValid).map(\.id)),sceneIDs=Set(scenes.map(\.id))
        let matching=rules.filter{runningIDs.contains($0.id) && sceneIDs.contains($0.sceneID)}
        // Foreground wins. Unrelated apps do not interrupt a still-running matched workload.
        if let rule=matching.first(where:{$0.id==frontmost}) ?? matching.first(where:{$0.id==current}) ?? matching.first {
            return .init(selection:.scene(rule.sceneID),application:rule.application)
        }
        var fallback=manualSelection
        if case .scene(let id)=fallback,!sceneIDs.contains(id) {fallback = .strategy(.system)}
        return .init(selection:fallback,application:nil)
    }
}
