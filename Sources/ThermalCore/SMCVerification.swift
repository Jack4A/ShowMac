import Foundation

/// Firmware writes may commit after the IOKit call returns. Poll reads only;
/// never repeat a write or widen its tolerance to turn a mismatch into success.
public enum SMCVerification {
    public static func waitFor(_ expected:Double,timeout:Double=2,
                               now:()->Double,read:()->Double?,wait:()->Void)->Bool {
        let deadline=now()+timeout
        var consecutive=0
        for _ in 0..<45 {
            if now()>deadline { return false }
            let matched=read().map { $0.isFinite && abs($0-expected)<1 } ?? false
            consecutive=matched ? consecutive+1:0
            if consecutive>=2 { return true }
            if now()>=deadline { return false }
            wait()
        }
        return false
    }
    public static func manualState(local:Double?,flags:Double?,id:Int,handoff:Double?=nil)->Bool? {
        if let local {
            if local==1 { return true }
            // A per-fan automatic byte does not prove the system owns cooling
            // while the Apple Silicon diagnostic handoff is still asserted.
            if local==0 || local==3 {
                if let handoff,handoff != 0 {return nil}
                return false
            }
            return nil
        }
        guard (0..<10).contains(id),let flags,flags.isFinite,(0...65535).contains(flags) else { return nil }
        if Int(flags)&(1<<id) != 0 {return true}
        if let handoff,handoff != 0 {return nil}
        return false
    }
}
