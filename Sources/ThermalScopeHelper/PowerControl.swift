import Foundation
import CSMC
import ThermalCore

final class SystemPowerAccess:PowerSettingsAccess {
    func configuration() throws ->PowerConfiguration {try NativePowerSettings.read()}
    func set(_ key:PowerSetting,on source:PowerSource,to value:Int) throws {try NativePowerSettings.write(key,on:source,value:value)}
    func currentSource()->PowerSource? {let value=ts_ac_power();return value<0 ? nil:(value==1 ? .ac:.battery)}
    func hasSleepBlockers() throws ->Bool {try !SleepBlocker.read().isEmpty}
    func turboState()->Int? {let state=ts_turbo_driver_state();return state<0 ? nil:Int(state)}
    func setTurbo(disabled:Bool) throws {try ThermalScopeHelper_setTurbo(disabled)}
}
// Keep the existing strictly verified driver path shared with direct controls.
func ThermalScopeHelper_setTurbo(_ disable:Bool) throws {try setTurbo(disable:disable)}
