import AppKit
import Combine
import ThermalCore

/// Persistence and hidden sampling use an explicit temporary file and isolated preferences.
@MainActor enum ElectricityHistoryCheck {
    static func run() {
        let name="local.showmac.electricity-check."+UUID().uuidString
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(name,isDirectory:true)
        let file=directory.appendingPathComponent("history.json")
        let domain=Bundle.main.bundleIdentifier ?? "local.jack.ThermalScope"
        let before=NSDictionary(dictionary:UserDefaults.standard.persistentDomain(forName:domain) ?? [:])
        let defaults=UserDefaults(suiteName:name)!
        defer {defaults.removePersistentDomain(forName:name);try? FileManager.default.removeItem(at:directory)}
        do {
            let start=Date(timeIntervalSince1970:1_800_000_000)
            let store=ElectricityHistoryStore(fileURL:file,defaults:defaults)
            store.rate=0.6;store.currency="USD";store.selectSource(.dcInput)
            var notifications=0
            let subscription=store.objectWillChange.sink{notifications+=1}
            for index in 0...120 {
                store.recordPower(60,source:.system,at:start.addingTimeInterval(Double(index)*5),publish:false)
                store.recordPower(80,source:.dcInput,at:start.addingTimeInterval(Double(index)*5),publish:false)
            }
            guard notifications==0 else{throw ScopeError.message("Hidden energy sampling invalidated views")}
            store.resumeVisualUpdates()
            guard notifications==1 else{throw ScopeError.message("Energy view did not catch up once")}
            store.suspend();store.recordPower(60,source:.system,at:start.addingTimeInterval(605),publish:false)
            store.resume();store.recordPower(60,source:.system,at:start.addingTimeInterval(610),publish:false)
            store.shutdown()
            let range=DateInterval(start:start,duration:7200)
            let reloaded=ElectricityHistoryStore(fileURL:file,defaults:defaults)
            let total=reloaded.history.totals(source:.system,in:range)
            guard abs(total.wattHours-10)<0.000001,total.observedSeconds==600,
                  reloaded.source == .dcInput,reloaded.rate==0.6,reloaded.currency=="USD" else{throw ScopeError.message("Electricity persistence lost usage or preferences")}
            reloaded.recordPower(60,source:.system,at:start.addingTimeInterval(3600),publish:false)
            guard reloaded.history.totals(source:.system,in:range)==total else{throw ScopeError.message("Restart fabricated electricity for a missing interval")}
            let original=Data("unreadable history fixture".utf8)
            try original.write(to:file,options:.atomic)
            let damaged=ElectricityHistoryStore(fileURL:file,defaults:defaults)
            damaged.recordPower(100,source:.system,at:start,publish:false)
            damaged.recordPower(100,source:.system,at:start.addingTimeInterval(10),publish:false)
            damaged.shutdown()
            guard damaged.storageIssue != nil,try Data(contentsOf:file)==original else{throw ScopeError.message("Unreadable energy history was overwritten")}
            guard before.isEqual(NSDictionary(dictionary:UserDefaults.standard.persistentDomain(forName:domain) ?? [:])) else{throw ScopeError.message("Electricity check modified application preferences")}
            withExtendedLifetime(subscription){}
            print("PASS: electricity history persists exact usage, source and tariff; hidden sampling, sleep/restart gaps, corrupt-file preservation and preference isolation. No hardware writes.")
        } catch {print("FAIL: "+error.localizedDescription);exit(1)}
    }
}
