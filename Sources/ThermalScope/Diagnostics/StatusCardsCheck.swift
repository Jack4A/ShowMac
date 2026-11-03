import AppKit
import ThermalCore

@MainActor enum StatusCardsCheck {
    static func run() {
        guard CommandLine.arguments.contains("--ui-check") else{print("Use --status-cards-check --ui-check.");exit(2)}
        _=NSApplication.shared
        do {
            func require(_ condition:Bool,_ message:String)throws {if !condition {throw ScopeError.message(message)}}
            func preferences()->NSDictionary {NSDictionary(dictionary:UserDefaults.standard.persistentDomain(forName:Bundle.main.bundleIdentifier ?? "local.jack.ThermalScope") ?? [:])}
            let before=preferences(),model=AppModel(),base=Date(timeIntervalSince1970:50_000)
            defer {model.shutdown()}
            let menu=model.effectiveMenuComponents,spacing=model.menuSpacing
            func sample(_ seconds:Double,missing:Bool=false)->Snapshot {
                Snapshot(date:base.addingTimeInterval(seconds),cpuUsage:0,sensors:[SensorReading(key:"TC0P",label:"CPU",celsius:81)],
                    fans:[FanReading(id:0,rpm:0,minimum:0,maximum:6000,manual:false,controllable:true)],speedLimit:100,schedulerLimit:100,availableCPUs:4,totalCPUs:4,thermalState:0,thermalWarning:nil,turbo:.unsupported,acPower:true,lowPower:false,smcAvailable:true,
                    additionalSensors:missing ? []:[HardwareSensorReading(key:"PSTR",label:"PSTR",kind:.power,value:-2.125),HardwareSensorReading(key:"ID0R",label:"ID0R",kind:.current,value:-1.25),HardwareSensorReading(key:"VD0R",label:"VD0R",kind:.voltage,value:12.125)])
            }
            let initial=sample(0)
            model.readings.update(initial,publish:false)
            for reading in SensorInventory.readings(initial) {
                let source=StatusCardSource.sensor(.hardware(reading))
                try require(source.value(model.readings)==reading.value && source.unit==reading.kind.unit,"A physical source lost value/unit: "+reading.id)
            }
            let json="{\"date\":\(base.timeIntervalSinceReferenceDate),\"batteryPercent\":65,\"memoryUsed\":8,\"memoryTotal\":16}"
            let telemetry=try JSONDecoder().decode(SystemTelemetry.self,from:Data(json.utf8))
            model.readings.update(telemetry,publish:false)
            model.statusPanel=StatusPanelConfiguration()
            try require(model.statusPanel.cards.count==4 && Set(model.statusPanel.cards.map(\.id)).count==4,"Default cards missing/duplicated")
            try require(StatusCardSource.metric(.memory).value(model.readings)==50 && StatusCardSource.metric(.battery).value(model.readings)==65,"Telemetry cards reused CPU usage")
            try require(StatusCardSource.metric(.cpuUsage).value(model.readings)==0 && StatusCardSource.metric(.fan).value(model.readings)==0,"Zero reading became unavailable")
            let power=StatusCardSource.sensor(MenuSensorReference(key:"PSTR",kind:.power)),current=StatusCardSource.sensor(MenuSensorReference(key:"ID0R",kind:.current))
            try require(model.addStatusCard(power) && model.addStatusCard(current),"Actual sensor could not be added")
            try require(!model.addStatusCard(power) && !model.addStatusCard(.sensor(MenuSensorReference(key:"NOPE",kind:.power))),"Duplicate/unavailable sensor accepted")
            try require(power.valueText(power.value(model.readings))=="-2.12" && current.valueText(current.value(model.readings))=="-1.250","Signed values or precision lost")
            try require(power.unit=="W" && current.unit=="A" && power.warningKind==nil,"Power/current units or temperature classification wrong")
            let index=model.statusPanel.cards.firstIndex(of:power)!
            model.moveStatusCard(power,by:-1)
            try require(model.statusPanel.cards[index-1]==power,"Card order not updated")
            model.moveStatusCard(model.statusPanel.cards[0],by:-1)
            let saved=model.statusPanel
            try require(StatusPanelConfiguration.decode(try JSONEncoder().encode(saved))==saved,"Configuration lost source identity/order on reload")
            try require(StatusPanelConfiguration.decode(Data("broken".utf8))==StatusPanelConfiguration(),"Malformed storage has no fallback")
            var invalid=saved;invalid.cards=[power,power,.sensor(MenuSensorReference(key:"",kind:.power))]
            try require(StatusPanelConfiguration.decode(try JSONEncoder().encode(invalid)).cards==[power],"Stored invalid/duplicate sources accepted")
            invalid.cards=[]
            try require(!StatusPanelConfiguration.decode(try JSONEncoder().encode(invalid)).cards.isEmpty,"Empty storage made an unusable panel")
            for kind in MetricKind.allCases {_ = model.addStatusCard(.metric(kind))}
            try require(model.statusPanel.cards.count==StatusPanelConfiguration.limit && !model.addStatusCard(.metric(.battery)),"Card bound ignored")
            invalid.cards=MetricKind.allCases.map{.metric($0)}+[power,current]
            try require(StatusPanelConfiguration.decode(try JSONEncoder().encode(invalid)).cards.count==StatusPanelConfiguration.limit,"Stored oversized panel not bounded")
            model.statusPanel=saved
            let refs=model.retainedSensorReferences
            try require(refs.contains(power.sensor!) && Set(refs).isSuperset(of:menu.compactMap(\.sensor)),"Popover sensors displaced menu histories")
            for seconds in [0.0,5.0,180.0] {model.sensorHistory.record(sample(seconds),menuSensors:refs,publish:false)}
            try require(model.sensorHistory.points(for:power.sensor!,minutes:5).compactMap(\.value).count==3 && model.sensorHistory.menuPoints(for:power.sensor!).count==1,"Popover range truncated to the two-minute menu window")
            model.sensorHistory.record(sample(185,missing:true),menuSensors:refs,publish:false)
            model.readings.update(sample(185,missing:true),publish:false)
            try require(power.value(model.readings)==nil && power.valueText(nil)=="—","Missing physical sensor substituted a value")
            model.sensorHistory.record(sample(190),menuSensors:refs,publish:false)
            let points=model.sensorHistory.points(for:power.sensor!,minutes:5)
            try require(points.first?.segment != points.last?.segment && points.contains{$0.value==nil},"Missing samples reconnected a trend")
            model.removeStatusCard(power)
            if !menu.compactMap(\.sensor).contains(power.sensor!) {
                model.sensorHistory.record(sample(195),menuSensors:model.retainedSensorReferences,publish:false)
                try require(model.sensorHistory.points(for:power.sensor!,minutes:5).isEmpty,"Unselected physical sensor history retained")
            }
            while model.statusPanel.cards.count>1 {model.removeStatusCard(model.statusPanel.cards[0])}
            model.removeStatusCard(model.statusPanel.cards[0])
            try require(model.statusPanel.cards.count==1,"Removed the last card")
            model.statusPanel.showProcesses=false;model.statusPanel.showFanControls=false
            try require(StatusPanelConfiguration.decode(try JSONEncoder().encode(model.statusPanel))==model.statusPanel,"Section visibility lost on reload")
            try require(model.effectiveMenuComponents==menu && model.menuSpacing==spacing && before.isEqual(preferences()),"Popover editing changed the menu configuration or saved preferences during checks")
            print("PASS: compact-card defaults, bounded configuration, stable sensor identity/order, all source kinds, telemetry vs CPU, zero/signed/missing values, units/precision, range/gap preservation, shared history retention/release, section visibility, reload and isolated preferences. No hardware writes.")
        } catch {print("FAIL: "+error.localizedDescription);exit(1)}
    }
}
