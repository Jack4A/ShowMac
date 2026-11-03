import Foundation
import Darwin

public struct ControlRequest:Codable {
    public var command:String
    public var profile:String?
    public var curve:FanCurve?
    public var duration:Double?
    public var label:String?
    public var powerPlan:PowerOptimizationPlan?
    public var powerBackup:PowerBackup?
    public init(_ command:String,profile:String?=nil,curve:FanCurve?=nil,duration:Double?=nil,label:String?=nil,powerPlan:PowerOptimizationPlan?=nil,powerBackup:PowerBackup?=nil) {
        self.command=command;self.profile=profile;self.curve=curve;self.duration=duration;self.label=label;self.powerPlan=powerPlan;self.powerBackup=powerBackup
    }
    public func validate() throws {
        guard ["hello","status","profile","auto","turbo-disable","turbo-enable","test-fans","shutdown","power-optimize","power-restore"].contains(command) else { throw ScopeError.message("未知控制命令") }
        if command=="power-optimize" {guard let powerPlan else{throw ScopeError.message("缺少优化方案")};try powerPlan.validate()}
        if command=="power-restore" {guard let powerBackup else{throw ScopeError.message("缺少恢复记录")};try powerBackup.validate()}
        if powerPlan != nil,command != "power-optimize" {throw ScopeError.message("电源方案命令不匹配")}
        if powerBackup != nil,command != "power-restore" {throw ScopeError.message("恢复记录命令不匹配")}
        if command=="profile" {
            guard let profile,ThermalProfile.allCases.contains(where:{$0.command==profile && $0 != .automatic}) else { throw ScopeError.message("无效模式") }
            if profile=="custom" { guard let curve else { throw ScopeError.message("缺少曲线") };try curve.validate() }
        }
        if let duration { guard duration.isFinite,duration>0,duration<=1800 else { throw ScopeError.message("无效控制时长") } }
        if let label { guard label.utf8.count<=80 else { throw ScopeError.message("模式名称过长") } }
    }
}
public struct FanTarget:Codable,Equatable,Identifiable {
    public let id:Int
    public let rpm:Double
    public init(id:Int,rpm:Double) {self.id=id;self.rpm=rpm}
}
public struct FanSessionStatus:Codable,Equatable {
    public let remainingSeconds:Double
    public let targets:[FanTarget]
    public let protectionActive:Bool
    public init(remainingSeconds:Double,targets:[FanTarget],protectionActive:Bool) {
        self.remainingSeconds=remainingSeconds;self.targets=targets;self.protectionActive=protectionActive
    }
}
public struct ControlReply:Codable {
    public var ok:Bool
    public var message:String
    public var session:String?
    public var profile:String?
    public var label:String?
    public var turbo:Int?
    public var power:PowerOutcome?
    public var fanStatus:FanSessionStatus?
    public init(ok:Bool,message:String,session:String?=nil,profile:String?=nil,label:String?=nil,turbo:Int?=nil,fanStatus:FanSessionStatus?=nil) {
        self.ok=ok;self.message=message;self.session=session;self.profile=profile;self.label=label;self.turbo=turbo
        self.fanStatus=fanStatus
    }
}
/// Framing uses a bounded line buffer. Both helper and app use the same protocol.
public final class ControlChannel {
    public let fd:Int32
    private var pending=Data()
    public init(fd:Int32) { self.fd=fd }
    public func readLine(timeout:Double=150) throws ->Data? {
        let deadline=ProcessInfo.processInfo.systemUptime+timeout
        while true {
            if let end=pending.firstIndex(of:10) {
                let data=pending[..<end];pending.removeSubrange(...end);return Data(data)
            }
            guard pending.count<16384 else { throw ScopeError.message("控制消息过长") }
            let remaining=deadline-ProcessInfo.processInfo.systemUptime
            guard remaining>0 else { throw ScopeError.message("辅助进程响应超时") }
            var descriptor=pollfd(fd:fd,events:Int16(POLLIN),revents:0)
            let ready=poll(&descriptor,1,Int32(min(remaining*1000,150000)))
            if ready<0 && errno==EINTR {continue}
            guard ready>0 else { throw ScopeError.message("辅助进程通信中断或超时") }
            var bytes=[UInt8](repeating:0,count:4096)
            let count=Darwin.read(fd,&bytes,bytes.count)
            if count==0 { return nil }
            if count<0 && errno==EINTR {continue}
            guard count>0 else { throw ScopeError.message("辅助进程读取失败") }
            pending.append(contentsOf:bytes.prefix(count))
        }
    }
    public func send<T:Encodable>(_ value:T) throws {
        var data=try JSONEncoder().encode(value);data.append(10)
        guard data.count<=16384 else { throw ScopeError.message("控制消息过长") }
        try data.withUnsafeBytes { buffer in
            var sent=0
            while sent<buffer.count {
                let count=Darwin.write(fd,buffer.baseAddress!.advanced(by:sent),buffer.count-sent)
                if count<0 && errno==EINTR {continue}
                guard count>0 else { throw ScopeError.message("辅助进程写入失败") }
                sent+=count
            }
        }
    }
}
