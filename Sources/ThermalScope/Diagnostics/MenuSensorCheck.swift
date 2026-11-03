import AppKit
import ThermalCore

@MainActor enum MenuSensorCheck {
    static func run() {
        guard CommandLine.arguments.contains("--ui-check") else{print("Use --menu-sensor-check --ui-check.");exit(2)}
        _=NSApplication.shared
        do {
            func require(_ condition:Bool,_ message:String)throws {if !condition {throw ScopeError.message(message)}}
            func preferences()->NSDictionary {NSDictionary(dictionary:UserDefaults.standard.persistentDomain(forName:Bundle.main.bundleIdentifier ?? "local.jack.ThermalScope") ?? [:])}
            let before=preferences(),model=AppModel(),base=Date(timeIntervalSince1970:50_000)
            defer {model.shutdown()}
            func sample(_ seconds:Double,missing:Bool=false)->Snapshot {
                Snapshot(date:base.addingTimeInterval(seconds),cpuUsage:25,sensors:missing ? []:[
                    SensorReading(key:"TC0P",label:"CPU",celsius:50+seconds),SensorReading(key:"TC1P",label:"CPU",celsius:70),
                    SensorReading(key:"TG0P",label:"GPU",celsius:45),SensorReading(key:"TH0P",label:"SSD",celsius:38),
                    SensorReading(key:"TX9Z",label:"TX9Z",celsius:32)],
                    fans:missing ? []:[FanReading(id:0,rpm:0,minimum:0,maximum:6000,manual:false,controllable:true),FanReading(id:1,rpm:1800,minimum:1000,maximum:6000,manual:false,controllable:true)],
                    speedLimit:100,schedulerLimit:100,availableCPUs:4,totalCPUs:4,thermalState:0,thermalWarning:nil,turbo:.unsupported,acPower:true,lowPower:false,smcAvailable:true,
                    additionalSensors:missing ? []:[HardwareSensorReading(key:"PSTR",label:"PSTR",kind:.power,value:-2.125),HardwareSensorReading(key:"PG0R",label:"PG0R",kind:.power,value:26.6),HardwareSensorReading(key:"VD0R",label:"VD0R",kind:.voltage,value:12.125),HardwareSensorReading(key:"ID0R",label:"ID0R",kind:.current,value:-1.25),HardwareSensorReading(key:"IZ9X",label:"IZ9X",kind:.current,value:nil)])
            }
            model.menuStyle="custom";model.menuComposition=nil;model.menuItems=[.cpu];model.menuTileColors=[:]
            let initial=sample(0)
            model.readings.update(initial,publish:false)
            let options=model.menuHardwareSensorOptions,refs=options.map(\.reference)
            try require(Set(options.map(\.id))==Set(SensorInventory.readings(initial).map(\.id)),"Inventory selector omitted a sensor")
            try require(Set(refs.map(\.kind))==Set(HardwareSensorKind.allCases),"A sensor kind is unavailable")
            try require(options.first{$0.reference.key=="TX9Z"}?.title.contains("TX9Z")==false,"Unknown probe has no human-readable title")
            for option in options {
                try require(model.insertMenuComponent(source:.sensor(option.reference),style:.value),"Cannot add "+option.id)
                try require(MenuComponentDrag(MenuComponentDrag.sensorTemplate(option.reference,.value).token) == .sensorTemplate(option.reference,.value),"Sensor drag token changed identity")
            }
            for option in model.menuCommonSensorOptions where option.reference.isCommon {
                try require(model.insertMenuComponent(source:.sensor(option.reference),style:.value),"Cannot add common aggregate")
            }
            let saved=model.effectiveMenuComponents
            try require(MenuBarComponent.decode(try JSONEncoder().encode(saved))==saved,"Sensor configuration cannot round-trip")
            model.sensorHistory.record(initial,menuSensors:refs,publish:false)
            let next=sample(5)
            model.readings.update(next,publish:false);model.sensorHistory.record(next,menuSensors:refs,publish:false)
            let tiles=MenuBarAppearanceRenderer.tiles(model:model)
            try require(tiles.allSatisfy{$0.color==nil},"A new physical sensor did not default to black and white")
            let colorID=saved.first{$0.sensor?.key=="ID0R"}!.id
            model.updateMenuComponent(id:colorID){$0.colorHex="2468AC"}
            let custom=MenuBarAppearanceRenderer.tiles(model:model)
            try require(custom.first{$0.sensor?.key=="ID0R"}?.color != nil && custom.filter{$0.sensor?.key != "ID0R"}.allSatisfy{$0.color==nil},"A physical sensor color changed another component")
            model.updateMenuComponent(id:colorID){$0.colorHex=nil}
            try require(model.effectiveMenuComponents==saved,"Resetting a physical sensor color changed its saved configuration")
            for ref in refs {
                let tile=tiles.first{$0.sensor==ref}
                try require(tile != nil && tile?.value.hasSuffix(ref.kind.unit)==true || tile?.value=="—","Unit missing for "+ref.id)
                try require(tile?.number==model.menuHardwareSensorOptions.first{$0.reference==ref}?.value,"Value substituted for "+ref.id)
            }
            let cpu0=tiles.first{$0.sensor?.key=="TC0P"},cpu1=tiles.first{$0.sensor?.key=="TC1P"}
            try require(cpu0?.number==55 && cpu1?.number==70,"Individual probes were merged")
            try require(tiles.first{$0.sensor?.key=="ID0R"}?.value=="-1.250 A" && tiles.first{$0.sensor?.key=="PSTR"}?.value=="-2.12 W","Signed values or precision lost")
            try require(tiles.first{$0.sensor?.key=="F0Ac"}?.value=="0 RPM","Stopped fan shown as missing")
            for dark in [false,true] {
                let image=MenuBarAppearanceRenderer.image(tiles:tiles,ending:next.date,spacing:4,graphWidth:44,background:false,appearance:NSAppearance(named:dark ? .darkAqua:.aqua))
                try require(image.size.height==22 && image.tiffRepresentation != nil && image.accessibilityDescription?.contains("ID0R -1.250 A")==true,"Sensor menu render/tooltip failed")
            }
            let signed=refs.first{$0.key=="ID0R"}!
            try require(model.sensorHistory.menuPoints(for:signed).compactMap(\.value)==[-1.25,-1.25],"Signed trend lost")
            let absent=sample(10,missing:true)
            model.readings.update(absent,publish:false);model.sensorHistory.record(absent,menuSensors:refs,publish:false)
            try require(model.effectiveMenuComponents==saved && MenuBarAppearanceRenderer.tiles(model:model).filter{$0.sensor != nil}.allSatisfy{$0.value=="—"},"Missing probe replaced or removed")
            try require(model.sensorHistory.menuPoints(for:signed).last?.value==nil,"Missing sensor did not break its trend")
            let resumed=sample(15)
            model.readings.update(resumed,publish:false);model.sensorHistory.record(resumed,menuSensors:refs,publish:false)
            let points=model.sensorHistory.menuPoints(for:signed)
            try require(points.last?.value == -1.25 && points.first?.segment != points.last?.segment,"Resume reconnected across missing data")
            let unusual=MenuSensorReference(key:"T|0P",kind:.temperature)
            try require(MenuComponentDrag(MenuComponentDrag.sensorTemplate(unusual,.value).token) == .sensorTemplate(unusual,.value),"Delimiter inside a physical ID changed the token")
            let bad=MenuSensorReference(key:"NOPE",kind:.power)
            try require(!model.insertMenuComponent(source:.sensor(bad),style:.value),"Unavailable source accepted")
            model.sensorHistory.record(sample(20),menuSensors:[],publish:false)
            try require(model.sensorHistory.menuPoints(for:signed).isEmpty,"Unselected physical history not released")
            try require(before.isEqual(preferences()),"Sensor check changed saved preferences")
            print("PASS: every physical sensor kind, common aggregates, names/units/precision, exact probe identity, signed/zero/missing readings, JSON, drag tokens, menu pixels/tooltips, bounded selected histories and isolated preferences. No hardware writes.")
        } catch {print("FAIL: "+error.localizedDescription);exit(1)}
    }
}
