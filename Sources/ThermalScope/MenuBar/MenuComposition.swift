import Foundation
import ThermalCore

/// Instance identity lets a metric contribute an icon, a value and a graph independently.
struct MenuBarComponent:Codable,Equatable,Identifiable {
    static let limit=24
    var id:String=UUID().uuidString
    var metric:MenuMetric
    var style:MenuTileStyle
    var sensor:MenuSensorReference?
    var token:TokenMenuConfiguration?
    var label:String?
    var colorHex:String?
    var icon:String?

    var source:MenuComponentSource {sensor.map(MenuComponentSource.sensor) ?? .metric(metric)}
    @MainActor func title(in model:AppModel)->String {metric.isToken && sensor==nil ? model.tokenMenuReading(metric:metric,configuration:token ?? TokenMenuConfiguration()).title:source.title(in:model)}

    static func template(source:MenuComponentSource,style:MenuTileStyle)->Self {
        var value=template(metric:source.metric,style:style)
        if case .sensor(let sensor)=source {value.sensor=sensor}
        return value
    }

    static func template(metric:MenuMetric,style:MenuTileStyle)->Self {
        Self(metric:metric,style:style,icon:style == .history || style == .bars ? "none":nil).normalized()
    }

    func normalized()->Self {
        var result=self
        if style == .stacked {result.style = .iconValue}
        result.token=token?.normalized()
        if metric == .tokens,result.style == .ring {result.style = .historyValue}
        if metric == .tokenQuota,![.icon,.value,.iconValue,.ring].contains(result.style) {result.style = .ring}
        result.label=label.map{String($0.prefix(8))}
        if icon=="none",result.style == .icon {result.style = .value}
        if let colorHex,colorHex.count != 6 || UInt32(colorHex,radix:16)==nil {result.colorHex=nil}
        return result
    }
    static func decode(_ data:Data?)->[Self]? {
        guard let data,let values=try? JSONDecoder().decode([Self].self,from:data),!values.isEmpty,values.count<=limit else{return nil}
        var ids=Set<String>()
        guard values.allSatisfy({!$0.id.isEmpty && $0.id.count<=80 && ids.insert($0.id).inserted && ($0.sensor?.isValid ?? true)}) else{return nil}
        return values.map{$0.normalized()}
    }
}

enum MenuComponentDrag:Equatable {
    case existing(String)
    case template(MenuMetric,MenuTileStyle)
    case sensorTemplate(MenuSensorReference,MenuTileStyle)
    private static let prefix="local.jack.ThermalScope.menu.v1|"
    var token:String {
        switch self {
        case .existing(let id):return Self.prefix+"item|"+id
        case .template(let metric,let style):return Self.prefix+"template|"+metric.rawValue+"|"+style.rawValue
        case .sensorTemplate(let sensor,let style):return Self.prefix+"sensor|"+(sensor.isCommon ? "common":"hardware")+"|"+sensor.kind.rawValue+"|"+Data(sensor.key.utf8).base64EncodedString()+"|"+style.rawValue
        }
    }
    init?(_ token:String) {
        guard token.count<240,token.hasPrefix(Self.prefix) else{return nil}
        let parts=String(token.dropFirst(Self.prefix.count)).split(separator:"|",omittingEmptySubsequences:false).map(String.init)
        if parts.count==2,parts[0]=="item",!parts[1].isEmpty {self = .existing(parts[1])}
        else if parts.count==3,parts[0]=="template",let metric=MenuMetric(rawValue:parts[1]),let style=MenuTileStyle(rawValue:parts[2]) {self = .template(metric,style)}
        else if parts.count==5,parts[0]=="sensor",["common","hardware"].contains(parts[1]),let kind=HardwareSensorKind(rawValue:parts[2]),let data=Data(base64Encoded:parts[3]),let key=String(data:data,encoding:.utf8),let style=MenuTileStyle(rawValue:parts[4]) {
            let sensor=MenuSensorReference(key:key,kind:kind,isCommon:parts[1]=="common")
            guard sensor.isValid else{return nil};self = .sensorTemplate(sensor,style)
        }
        else {return nil}
    }
}

extension AppModel {
    var effectiveMenuComponents:[MenuBarComponent] {
        if let menuComposition,!menuComposition.isEmpty {return menuComposition}
        return menuItems.map {metric in
            MenuBarComponent(id:"legacy."+metric.rawValue,metric:metric,style:MenuTileStyle(rawValue:menuTileStyles[metric.rawValue] ?? "") ?? metric.defaultTileStyle,label:menuTileLabels[metric.rawValue],colorHex:menuTileColors[metric.rawValue],icon:menuTileIcons[metric.rawValue]).normalized()
        }
    }
    @discardableResult func insertMenuComponent(metric:MenuMetric,style:MenuTileStyle,before target:String?=nil)->Bool {
        insertMenuComponent(source:.metric(metric),style:style,before:target)
    }
    @discardableResult func insertMenuComponent(source:MenuComponentSource,style:MenuTileStyle,before target:String?=nil)->Bool {
        if case .sensor(let sensor)=source {guard sensor.isValid,menuSensorOptions.contains(where:{$0.reference==sensor}) else{return false}}
        var values=effectiveMenuComponents
        guard values.count<MenuBarComponent.limit,target==nil || values.contains(where:{$0.id==target}) else{return false}
        let index=target.flatMap{id in values.firstIndex{$0.id==id}} ?? values.count
        values.insert(.template(source:source,style:style),at:index)
        menuStyle="custom";menuComposition=values
        return true
    }
    @discardableResult func moveMenuComponent(id:String,before target:String?)->Bool {
        var values=effectiveMenuComponents
        guard id != target,let source=values.firstIndex(where:{$0.id==id}),target==nil || values.contains(where:{$0.id==target}) else{return false}
        let item=values.remove(at:source)
        let destination=target.flatMap{id in values.firstIndex{$0.id==id}} ?? values.count
        values.insert(item,at:destination)
        guard values != effectiveMenuComponents else{return false}
        menuStyle="custom";menuComposition=values
        return true
    }
    @discardableResult func removeMenuComponent(id:String)->Bool {
        let values=effectiveMenuComponents
        guard values.count>1,values.contains(where:{$0.id==id}) else{return false}
        menuComposition=values.filter{$0.id != id}
        return true
    }
    func updateMenuComponent(id:String,_ change:(inout MenuBarComponent)->Void) {
        var values=effectiveMenuComponents
        guard let index=values.firstIndex(where:{$0.id==id}) else{return}
        change(&values[index]);values[index]=values[index].normalized();menuComposition=values
    }
    func setMenuComponentIcon(_ token:String,id:String) {
        updateMenuComponent(id:id) {value in
            value.icon=token
            if token=="none",value.style == .icon {value.style = .value}
            else if token != "auto",token != "none",value.style == .value {value.style = .iconValue}
        }
    }
    @discardableResult func applyMenuDrop(_ tokens:[String],before target:String?)->Bool {
        guard tokens.count==1,let drag=MenuComponentDrag(tokens[0]) else{return false}
        switch drag {
        case .existing(let id):return moveMenuComponent(id:id,before:target)
        case .template(let metric,let style):return insertMenuComponent(metric:metric,style:style,before:target)
        case .sensorTemplate(let sensor,let style):return insertMenuComponent(source:.sensor(sensor),style:style,before:target)
        }
    }
}
