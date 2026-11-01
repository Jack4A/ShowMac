import Foundation

/// Presentation only. The original diagnostic and failed operation remain intact.
public struct OperationIssue {
    public private(set) var title:String
    public private(set) var guidance:String
    public init(_ diagnostic:String) {
        if diagnostic.contains("回读不一致") {
            title="风扇设置尚未确认"
            guidance="写入后的读数与目标不一致，不能确认散热模式已生效。请检查当前风扇状态，并确认其他风扇控制软件已退出；需要时恢复系统自动。"
        } else if diagnostic.contains("恢复自动风扇失败") {
            title="系统自动风扇未确认恢复"
            guidance="请检查当前风扇模式，再尝试恢复系统自动。技术详情包含失败原因。"
        } else if diagnostic.contains("(-128)") || diagnostic.contains("User canceled") || diagnostic.contains("用户取消") {
            title="授权已取消"
            guidance="本次操作未完成。需要更改设置时，请重新操作并完成系统授权。"
        } else {
            title="操作未完成"
            guidance="当前设置未确认生效，请查看技术详情并检查硬件状态。"
        }
        // A failed rollback takes precedence over the initiating error.
        if diagnostic.contains("恢复自动风扇失败") {
            self.title="系统自动风扇未确认恢复"
            self.guidance="恢复自动模式时发生错误。请检查当前风扇状态，再尝试恢复系统自动；不要将本次操作视为成功。"
        }
    }
}
