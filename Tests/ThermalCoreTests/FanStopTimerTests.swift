import Foundation
import ThermalCore

final class FanStopTimerTests {
    func testOneShotClockAndSleepBoundaries()throws {
        let date=Date(timeIntervalSince1970:1_000_000)
        let timer=try FanStopTimer(minutes:30,now:date,uptime:100)
        expectEqual(timer.remaining(now:date,uptime:100),1800)
        expectEqual(timer.remaining(now:date.addingTimeInterval(90),uptime:190),1710)
        // Sleep counts even if the uptime clock did not advance during sleep.
        expectEqual(timer.remaining(now:date.addingTimeInterval(1900),uptime:110),0)
        // Moving the wall clock backwards must not extend the original timer.
        expectEqual(timer.remaining(now:date.addingTimeInterval(-3600),uptime:1900),0)
        expectEqual(timer.remaining(now:date,uptime:.infinity),0)
        expectEqual(try FanStopTimer(minutes:1440,now:date,uptime:100).remaining(now:date,uptime:100),86400)
        for minutes in [-1,0,1441,Int.max] {expectThrows(try FanStopTimer(minutes:minutes,now:date,uptime:100))}
        expectThrows(try FanStopTimer(minutes:1,now:date,uptime:-1))
        expectThrows(try FanStopTimer(minutes:1,now:Date(timeIntervalSince1970:.infinity),uptime:100))
    }
    func testLegacyDurationsCannotBecomeTheNextDefault()throws {
        var saved=FanSceneConfiguration()
        saved.selection = .scene(saved.scenes[0].id);saved.duration = .hour1
        let restored=FanSceneConfiguration.decode(try JSONEncoder().encode(saved))
        expectEqual(restored.duration,.continuous)
        expectEqual(restored.selection,saved.selection)
        expectEqual(restored.scenes,saved.scenes)
    }
}
