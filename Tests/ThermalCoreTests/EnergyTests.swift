import ThermalCore

struct EnergyTests {
    func source(_ id:String,_ cpu:Double)->ActivitySource {ActivitySource(id:id,name:id,cpu:cpu)}
    func testWeightedGrouping() {
        var window=CPUActivityWindow()
        window.record([source("app",0),source("other",0)],at:0)
        window.record([source("app",40),source("app",60),source("other",50)],at:5)
        window.record([source("app",0),source("other",50)],at:15)
        expectEqual(window.seconds,15)
        expectEqual(window.rows.map(\.id),["other","app"])
        expectEqual(window.rows[1].averageCPU,100.0/3,accuracy:0.001)
        expectEqual(window.rows[0].averageCPU,50,accuracy:0.001)
        expectEqual(window.rows[1].cpuShare,40,accuracy:0.001)
        expectEqual(window.rows[1].currentCPU,0)
    }
    func testPartialIntervalExpiry() {
        var window=CPUActivityWindow(seconds:15)
        window.record([source("app",0)],at:0)
        window.record([source("app",100)],at:10)
        window.record([source("app",0)],at:20)
        expectEqual(window.seconds,15)
        expectEqual(window.rows[0].averageCPU,100.0/3,accuracy:0.001)
        window.record([source("app",0)],at:30)
        expectEqual(window.rows[0].averageCPU,0)
        expectEqual(window.rows[0].cpuShare,0)
    }
    func testExitedAndReusedIdentities() {
        var window=CPUActivityWindow()
        window.record([source("pid:1:old",0)],at:0)
        window.record([source("pid:1:old",100)],at:5)
        window.record([source("pid:1:new",10)],at:10)
        expectEqual(window.rows.map(\.id),["pid:1:new"])
        expectEqual(window.rows[0].averageCPU,5)
        expectEqual(window.rows[0].currentCPU,10)
    }
    func testSamplingGapsAndUnavailableData() {
        var window=CPUActivityWindow()
        window.record([source("app",0)],at:0)
        window.record([source("app",100)],at:5)
        window.record([source("app",100)],at:40)
        expectTrue(window.rows.isEmpty);expectEqual(window.seconds,0)
        window.record([source("app",20)],at:45)
        expectEqual(window.rows[0].averageCPU,20)
        window.record([],at:50)
        expectTrue(window.rows.isEmpty);expectEqual(window.seconds,0)
        window.record([source("app",Double.nan)],at:55)
        expectTrue(window.rows.isEmpty)
        window.record([source("app",0)],at:60)
        window.record([source("app",0)],at:65)
        expectEqual(window.rows[0].averageCPU,0)
        window.record([source("app",10)],at:64)
        expectTrue(window.rows.isEmpty)
    }
}
