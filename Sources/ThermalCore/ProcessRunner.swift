import Foundation
import Darwin

public struct CommandResult {
    public let status: Int32
    public let output: String
}
public enum ProcessRunner {
    /// Output goes to a private temporary file, so full pipes cannot deadlock a helper.
    public static func run(_ executable: String, _ arguments: [String], timeout: Double=20) throws -> CommandResult {
        var template=Array((NSTemporaryDirectory()+"thermalscope-command-XXXXXX").utf8CString)
        let fd=mkstemp(&template)
        guard fd>=0 else { throw ScopeError.message("无法创建命令输出文件") }
        let path=String(cString:template)
        let handle=FileHandle(fileDescriptor:fd,closeOnDealloc:true)
        defer { try? handle.close(); unlink(path) }
        let process=Process()
        process.executableURL=URL(fileURLWithPath:executable)
        process.arguments=arguments
        process.standardOutput=handle; process.standardError=handle
        process.standardInput=FileHandle.nullDevice
        let finished=DispatchSemaphore(value:0)
        process.terminationHandler={ _ in finished.signal() }
        try process.run()
        if finished.wait(timeout:.now()+timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout:.now()+2) == .timedOut { kill(process.processIdentifier,SIGKILL) }
            throw ScopeError.message("命令超时。请刷新状态确认结果。")
        }
        try handle.seek(toOffset:0)
        let data=try handle.read(upToCount:128*1024) ?? Data()
        return CommandResult(status:process.terminationStatus,output:String(decoding:data,as:UTF8.self))
    }
    public static func shellQuote(_ value: String) -> String { "'"+value.replacingOccurrences(of:"'",with:"'\\''")+"'" }
    public static func appleScriptString(_ value: String) -> String {
        "\""+value.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"").replacingOccurrences(of:"\n",with:"\\n")+"\""
    }
}
