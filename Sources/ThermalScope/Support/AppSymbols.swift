import AppKit

/// SF Symbols names evolve independently of the app's deployment target.
enum AppSymbols {
    private static let cache:NSCache<NSString,NSString> = {
        let cache=NSCache<NSString,NSString>();cache.countLimit=128;return cache
    }()
    static func resolve(_ name:String)->String {
        if let cached=cache.object(forKey:name as NSString) {return cached as String}
        let fallback:String
        switch name {
        case "thermometer.medium","thermometer.low","thermometer.high":fallback="thermometer"
        case "fanblades","fanblades.fill":fallback="wind"
        case "sensor","sensor.fill":fallback="waveform"
        case "gauge.with.dots.needle.50percent":fallback="speedometer"
        case "macwindow":fallback="rectangle"
        default:fallback="circle"
        }
        let result=NSImage(systemSymbolName:name,accessibilityDescription:nil) != nil ? name:fallback
        cache.setObject(result as NSString,forKey:name as NSString)
        return result
    }
}
