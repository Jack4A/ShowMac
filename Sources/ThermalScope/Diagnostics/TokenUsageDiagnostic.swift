import Foundation
import ThermalCore

/// Explicit read-only diagnostic; never called by fixture checks or ordinary UI captures.
enum TokenUsageDiagnostic {
    static func run() {
        let start=Date(),scanner=TokenLogScanner()
        let snapshot=scanner.scan(roots:TokenLogScanner.defaultRoots())
        let incrementalStart=Date(),incremental=scanner.scan(roots:TokenLogScanner.defaultRoots())
        let today=ElectricityPeriod.day.interval(containing:Date())
        let report=TokenUsageReport(events:snapshot.events,in:today,intervals:ElectricityPeriod.day.chartIntervals(containing:Date()))
        let result:[String:Any]=["files":snapshot.fileCount,"events":snapshot.events.count,"bytesRead":snapshot.bytesRead,"seconds":Date().timeIntervalSince(start),"unreadable":snapshot.unreadable,"malformed":snapshot.malformed,"unresolvedForks":snapshot.unresolvedForks,"todayInput":report.counts.input,"todayOutput":report.counts.output,"todayCacheRead":report.counts.cacheRead,"todayTotal":report.counts.total,"incrementalBytesRead":incremental.bytesRead,"incrementalReparsedFiles":incremental.reparsedFiles,"incrementalAppendedFiles":incremental.appendedFiles,"incrementalUnchangedFiles":incremental.unchangedFiles,"incrementalSeconds":Date().timeIntervalSince(incrementalStart),"allTimeByTool":TokenProvider.allCases.map{provider in let counts=snapshot.events.filter{$0.provider==provider}.reduce(TokenCounts()){$0.adding($1.counts)};return ["provider":provider.rawValue,"input":counts.input,"output":counts.output] as [String:Any]},"models":report.models.map{["provider":$0.provider.rawValue,"model":$0.model,"tokens":$0.counts.total] as [String:Any]}]
        if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]),let text=String(data:data,encoding:.utf8){print(text)}
    }
}
