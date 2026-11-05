import Foundation

public enum FanStrategy:String,Codable,CaseIterable,Identifiable {
    case system,quiet,balanced,cooling,custom
    public var id:String {rawValue}
    public static let presets:[Self]=[.system,.quiet,.balanced,.cooling]
    public var title:String {
        switch self {
        case .system:return "系统自动"
        case .quiet:return "安静优先"
        case .balanced:return "均衡"
        case .cooling:return "散热优先"
        case .custom:return "自定义曲线"
        }
    }
    public var shortTitle:String {
        switch self {case .system:return "自动";case .quiet:return "安静";case .balanced:return "均衡";case .cooling:return "强劲";case .custom:return "自定义"}
    }
    public var curve:FanCurve? {
        switch self {case .quiet:return .quiet;case .balanced:return .balanced;case .cooling:return .performance;default:return nil}
    }
    public var explanation:String {
        switch self {
        case .system:return "由 macOS 决定转速，不使用应用曲线"
        case .quiet:return "优先降低风扇噪声"
        case .balanced:return "兼顾温度与噪声"
        case .cooling:return "提前提高风扇转速"
        case .custom:return "使用已保存的温度曲线"
        }
    }
}

public enum FanControlDuration:String,Codable,CaseIterable,Identifiable {
    case continuous,minutes30,hour1,hours2
    public var id:String {rawValue}
    public var seconds:Double? {
        switch self {case .continuous:return nil;case .minutes30:return 1800;case .hour1:return 3600;case .hours2:return 7200}
    }
    public var title:String {
        switch self {case .continuous:return "持续运行";case .minutes30:return "30 分钟";case .hour1:return "1 小时";case .hours2:return "2 小时"}
    }
}

public enum FanModeSelection:Codable,Hashable {
    case strategy(FanStrategy)
    case scene(String)
    public var isAutomatic:Bool {self == .strategy(.system)}
}

public struct FanScene:Codable,Equatable,Identifiable {
    public var id:String
    public var name:String
    public var curve:FanCurve
    public init(id:String=UUID().uuidString,name:String,curve:FanCurve) {self.id=id;self.name=name;self.curve=curve}
    public func validate() throws {
        guard UUID(uuidString:id) != nil else {throw ScopeError.message("无效场景")}
        let trimmed=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !trimmed.isEmpty,trimmed==name,name.utf8.count<=80,!name.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}) else {throw ScopeError.message("场景名称不能为空，且不能超过 80 字节")}
        try curve.validate()
    }
    public static let defaults:[FanScene]=[
        .init(id:"88C98559-2688-4103-92B7-55AC87CAC001",name:"剪辑",curve:.performance),
        .init(id:"88C98559-2688-4103-92B7-55AC87CAC002",name:"游戏",curve:.performance),
        .init(id:"88C98559-2688-4103-92B7-55AC87CAC003",name:"办公",curve:.balanced),
        .init(id:"88C98559-2688-4103-92B7-55AC87CAC004",name:"影音",curve:.quiet),
        .init(id:"88C98559-2688-4103-92B7-55AC87CAC005",name:"编程",curve:FanCurve(points:FanCurve.balanced.points,sensor:.cpu))
    ]
}

/// Saves fan curves and intent, never system power/Turbo state or a live helper token.
public struct FanSceneConfiguration:Codable,Equatable {
    public static let limit=32
    public var scenes:[FanScene]
    public var selection:FanModeSelection
    public var duration:FanControlDuration
    public var restoreOnLaunch:Bool
    public var confirmedCustomCurve:FanCurve?
    public init(scenes:[FanScene]=FanScene.defaults,selection:FanModeSelection = .strategy(.system),duration:FanControlDuration = .continuous,restoreOnLaunch:Bool=true,confirmedCustomCurve:FanCurve?=nil) {
        self.scenes=scenes;self.selection=selection;self.duration=duration;self.restoreOnLaunch=restoreOnLaunch;self.confirmedCustomCurve=confirmedCustomCurve
    }
    public static func decode(_ data:Data?)->Self {
        guard let data,data.count<=131072,var value=try? JSONDecoder().decode(Self.self,from:data) else{return Self()}
        var ids=Set<String>(),names=Set<String>()
        value.scenes=value.scenes.filter {scene in
            guard (try? scene.validate()) != nil,!ids.contains(scene.id),!names.contains(scene.name.lowercased()) else{return false}
            ids.insert(scene.id);names.insert(scene.name.lowercased());return true
        }.prefix(limit).map{$0}
        if case .scene(let id)=value.selection,!value.scenes.contains(where:{$0.id==id}) {value.selection = .strategy(.system)}
        if let curve=value.confirmedCustomCurve,(try? curve.validate())==nil {value.confirmedCustomCurve=nil}
        return value
    }
    public func curve(custom:FanCurve)->FanCurve? {
        switch selection {
        case .strategy(let strategy):return strategy == .custom ? (confirmedCustomCurve ?? custom):strategy.curve
        case .scene(let id):return scenes.first{$0.id==id}?.curve
        }
    }
    public var resumeSelection:FanModeSelection? {
        guard restoreOnLaunch,!selection.isAutomatic else{return nil}
        if selection == .strategy(.custom),confirmedCustomCurve==nil {return nil}
        if case .scene(let id)=selection,!scenes.contains(where:{$0.id==id}) {return nil}
        return selection
    }
    public mutating func save(name:String,curve:FanCurve,id:String?=nil)throws->FanScene {
        let trimmed=name.trimmingCharacters(in:.whitespacesAndNewlines)
        let scene=FanScene(id:id ?? UUID().uuidString,name:trimmed,curve:curve)
        try scene.validate()
        guard !scenes.contains(where:{$0.id != scene.id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame}) else {throw ScopeError.message("已有同名场景")}
        if let index=scenes.firstIndex(where:{$0.id==scene.id}) {scenes[index]=scene}
        else {
            guard scenes.count<Self.limit else {throw ScopeError.message("最多保存 32 个场景")}
            scenes.append(scene)
        }
        return scene
    }
    public mutating func remove(_ id:String) {
        scenes.removeAll{$0.id==id}
        if selection == .scene(id) {selection = .strategy(.system)}
    }
}
