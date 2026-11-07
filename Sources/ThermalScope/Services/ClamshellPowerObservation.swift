import Foundation
import IOKit.ps

/// Power-source notifications avoid waiting for the next sensor sampling tick.
@MainActor final class ClamshellPowerObservation {
    private var source:CFRunLoopSource?
    private let onChange:()->Void
    init(onChange:@escaping()->Void) {
        self.onChange=onChange
        source=IOPSNotificationCreateRunLoopSource({context in
            guard let context else{return}
            MainActor.assumeIsolated {
                Unmanaged<ClamshellPowerObservation>.fromOpaque(context).takeUnretainedValue().onChange()
            }
        },Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let source {CFRunLoopAddSource(CFRunLoopGetMain(),source,.commonModes)}
    }
    func invalidate() {
        if let source {CFRunLoopSourceInvalidate(source)}
        source=nil
    }
    deinit {if let source {CFRunLoopSourceInvalidate(source)}}
}
