import Foundation

/// A one-shot timer for this app run. It intentionally cannot be persisted.
public struct FanStopTimer:Equatable {
    public static let minuteRange=1...1440
    public let minutes:Int
    public let wallDeadline:Date
    public let uptimeDeadline:TimeInterval
    public init(minutes:Int,now:Date=Date(),uptime:TimeInterval=ProcessInfo.processInfo.systemUptime)throws {
        guard Self.minuteRange.contains(minutes),now.timeIntervalSinceReferenceDate.isFinite,uptime.isFinite,uptime>=0 else {throw ScopeError.message("请输入 1–1440 分钟")}
        self.minutes=minutes
        wallDeadline=now.addingTimeInterval(Double(minutes)*60)
        uptimeDeadline=uptime+Double(minutes)*60
    }
    public func remaining(now:Date=Date(),uptime:TimeInterval=ProcessInfo.processInfo.systemUptime)->Double {
        guard now.timeIntervalSinceReferenceDate.isFinite,uptime.isFinite else{return 0}
        // Wall time counts sleep; uptime prevents a backward clock change extending the timer.
        return max(0,min(Double(minutes)*60,wallDeadline.timeIntervalSince(now),uptimeDeadline-uptime))
    }
}
