import Foundation
import ThermalCore

final class FakePower:PowerSettingsAccess {
    var config=PowerConfiguration([.ac:[.lowpowermode:0,.displaysleep:10,.sleep:0],.battery:[.lowpowermode:1,.displaysleep:2,.sleep:5]])
    var source:PowerSource? = .ac
    var blocked=false
    var turbo:Int?=0
    var writes:[String]=[]
    var failKey:PowerSetting?
    var failTurbo=false
    func configuration() throws ->PowerConfiguration {config}
    func currentSource()->PowerSource? {source}
    func hasSleepBlockers() throws ->Bool {blocked}
    func turboState()->Int? {turbo}
    func set(_ key:PowerSetting,on source:PowerSource,to value:Int) throws {
        writes.append(source.rawValue+":"+key.rawValue+"=\(value)");config.profiles[source]?[key]=value
        if failKey==key {failKey=nil;throw ScopeError.message("Simulated write/readback failure")}
    }
    func setTurbo(disabled:Bool) throws {
        writes.append("turbo=\(disabled)");turbo=disabled ? 1:0
        if failTurbo {failTurbo=false;throw ScopeError.message("Simulated Turbo verification failure")}
    }
}
struct PowerTests {
    func testSettingsParsing() {
        let config=PowerConfiguration.parse("Battery Power:\n lowpowermode 1\n sleep 5\nAC Power:\n lowpowermode 0\n displaysleep 10\n sleep 0\n arbitrary 1")
        expectEqual(config.value(.lowpowermode,on:.battery),1);expectEqual(config.value(.lowpowermode,on:.ac),0)
        expectEqual(config.value(.displaysleep,on:.ac),10);expectEqual(config.value(.sleep,on:.ac),0)
        let bad=PowerConfiguration.parse("AC Power:\n sleep -1\n lowpowermode 0\n lowpowermode 1\n lowpowermode 0")
        expectNil(bad.value(.sleep,on:.ac));expectNil(bad.value(.lowpowermode,on:.ac))
        expectTrue(PowerConfiguration.parse("unavailable").profiles.isEmpty)
    }
    func testPowerScopesAndNoops() throws {
        let hardware=FakePower()
        let plan=PowerOptimizationPlan(source:.ac)
        expectEqual(plan.edits(in:hardware.config),[PowerEdit(source:.ac,key:.lowpowermode,before:0,after:1)])
        let automatic=PowerOptimizationPlan(source:.ac,scope:.batteryAutomatic)
        expectTrue(automatic.edits(in:hardware.config).isEmpty)
        let result=try PowerTransaction.apply(automatic,using:hardware)
        expectFalse(result.changed);expectNil(result.backup);expectTrue(hardware.writes.isEmpty)
        let applied=try PowerTransaction.apply(plan,using:hardware)
        expectTrue(applied.changed);expectEqual(hardware.writes,["ac:lowpowermode=1"]);expectEqual(hardware.turbo,0)
        expectEqual(hardware.config.value(.lowpowermode,on:.battery),1)
        let other=FakePower()
        other.config.profiles[.ac]?[.lowpowermode]=1;other.config.profiles[.battery]?[.lowpowermode]=0
        let original=other.config
        let switched=try PowerTransaction.apply(automatic,using:other)
        expectEqual(other.config.value(.lowpowermode,on:.ac),0);expectEqual(other.config.value(.lowpowermode,on:.battery),1)
        _=try PowerTransaction.restore(switched.backup!,using:other)
        expectEqual(other.config,original)
    }
    func testPowerPreflight() {
        let hardware=FakePower();hardware.source = .battery
        expectThrows(try PowerTransaction.apply(PowerOptimizationPlan(source:.ac),using:hardware))
        expectTrue(hardware.writes.isEmpty)
        hardware.source = .ac;hardware.blocked=true
        expectThrows(try PowerTransaction.apply(PowerOptimizationPlan(source:.ac,idleMinutes:15),using:hardware))
        expectTrue(hardware.writes.isEmpty)
        hardware.blocked=false
        let expected=hardware.config
        hardware.config.profiles[.ac]?[.displaysleep]=2
        expectThrows(try PowerTransaction.apply(PowerOptimizationPlan(source:.ac,displayMinutes:5,expected:expected),using:hardware))
        expectTrue(hardware.writes.isEmpty)
        hardware.blocked=false;hardware.config.profiles[.ac]?.removeValue(forKey:.lowpowermode)
        expectThrows(try PowerTransaction.apply(PowerOptimizationPlan(source:.ac),using:hardware))
        expectTrue(hardware.writes.isEmpty)
    }
    func testPartialPowerRollback() {
        let hardware=FakePower(),original=hardware.config
        hardware.failKey = .displaysleep
        expectThrows(try PowerTransaction.apply(PowerOptimizationPlan(source:.ac,displayMinutes:5),using:hardware))
        expectEqual(hardware.config,original)
        expectEqual(Array(hardware.writes.suffix(2)),["ac:displaysleep=10","ac:lowpowermode=0"])
    }
    func testTurboTransactionRollback() {
        let hardware=FakePower(),original=hardware.config
        hardware.failTurbo=true
        expectThrows(try PowerTransaction.apply(PowerOptimizationPlan(source:.ac,disableTurbo:true),using:hardware))
        expectEqual(hardware.config,original);expectEqual(hardware.turbo,0)
    }
    func testRestorePreservesExternalChanges() throws {
        let hardware=FakePower()
        let result=try PowerTransaction.apply(PowerOptimizationPlan(source:.ac,displayMinutes:5,disableTurbo:true),using:hardware)
        hardware.config.profiles[.ac]?[.displaysleep]=2
        let restored=try PowerTransaction.restore(result.backup!,using:hardware)
        expectEqual(restored.skipped,1);expectEqual(hardware.config.value(.displaysleep,on:.ac),2)
        expectEqual(hardware.config.value(.lowpowermode,on:.ac),0);expectEqual(hardware.turbo,0)
        let twice=try PowerTransaction.restore(result.backup!,using:hardware)
        expectEqual(twice.skipped,1);expectFalse(twice.changed)
    }
    func testPowerProtocolValidation() throws {
        expectThrows(try ControlRequest("power-optimize").validate())
        expectThrows(try ControlRequest("power-restore").validate())
        expectThrows(try ControlRequest("status",powerPlan:PowerOptimizationPlan(source:.ac)).validate())
        expectThrows(try ControlRequest("power-optimize",powerPlan:PowerOptimizationPlan(source:.ac,idleMinutes:0)).validate())
        expectThrows(try PowerBackup(edits:[PowerEdit(source:.ac,key:.sleep,before:300,after:15)],turboBefore:nil).validate())
        let edit=PowerEdit(source:.ac,key:.lowpowermode,before:0,after:1)
        expectThrows(try PowerBackup(edits:[edit,edit],turboBefore:nil).validate())
        expectThrows(try NativePowerSettings.write(.sleep,on:.ac,value:9999))
        try ControlRequest("power-optimize",powerPlan:PowerOptimizationPlan(source:.ac)).validate()
        let value=PowerBackup(edits:[edit],turboBefore:0)
        let data=try JSONEncoder().encode(value)
        let decoded=try JSONDecoder().decode(PowerBackup.self,from:data)
        expectEqual(decoded.edits,[edit]);try decoded.validate()
        var reply=ControlReply(ok:true,message:"verified")
        reply.power=PowerOutcome(backup:value,changed:true)
        let received=try JSONDecoder().decode(ControlReply.self,from:JSONEncoder().encode(reply))
        expectEqual(received.power?.backup?.edits,[edit]);expectEqual(received.power?.changed,true)
        let request=ControlRequest("power-optimize",powerPlan:PowerOptimizationPlan(source:.ac,expected:FakePower().config))
        let accepted=try JSONDecoder().decode(ControlRequest.self,from:JSONEncoder().encode(request))
        try accepted.validate();expectEqual(accepted.powerPlan?.expected,FakePower().config)
    }
    func testComparisonCoverage() {
        let date=Date(timeIntervalSince1970:1000)
        func samples(_ source:PowerSource,watts:Double?)->[OptimizationMetric] {(0..<6).map {i in OptimizationMetric(date:date.addingTimeInterval(Double(i*5)),cpu:20,temperature:60,dischargeWatts:watts,source:source)}}
        let before=OptimizationSummary(samples(.battery,watts:12)),after=OptimizationSummary(samples(.battery,watts:10))
        expectTrue(before.sufficient);expectTrue(before.comparableWatts(to:after));expectEqual(before.watts,12)
        expectNil(OptimizationSummary(samples(.ac,watts:12)).watts)
        expectNil(OptimizationSummary(Array(samples(.battery,watts:12).prefix(1))).watts)
        expectFalse(OptimizationSummary([]).sufficient)
        var mixed=samples(.battery,watts:12);mixed.append(OptimizationMetric(date:date.addingTimeInterval(30),cpu:20,temperature:60,dischargeWatts:nil,source:.ac))
        expectNil(OptimizationSummary(mixed).watts)
    }
}
