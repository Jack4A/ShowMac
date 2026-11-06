// Standalone checks work with Command Line Tools alone; full Xcode/XCTest is not required.
import Foundation
import Darwin
import ThermalCore

var failures=0
func failCheck(_ message:String,file:StaticString,line:UInt) {
    failures+=1;print("FAIL \(file):\(line): \(message)")
}
func expectTrue(_ value:Bool,file:StaticString=#filePath,line:UInt=#line) {
    if !value { failCheck("expected true",file:file,line:line) }
}
func expectFalse(_ value:Bool,file:StaticString=#filePath,line:UInt=#line) { expectTrue(!value,file:file,line:line) }
func expectNil<T>(_ value:T?,file:StaticString=#filePath,line:UInt=#line) { expectTrue(value==nil,file:file,line:line) }
func expectEqual<T:Equatable>(_ a:T,_ b:T,file:StaticString=#filePath,line:UInt=#line) {
    if a != b { failCheck("\(a) != \(b)",file:file,line:line) }
}
func expectEqual(_ a:Double,_ b:Double,accuracy:Double,file:StaticString=#filePath,line:UInt=#line) {
    expectTrue(abs(a-b)<=accuracy,file:file,line:line)
}
func expectNotEqual<T:Equatable>(_ a:T,_ b:T,file:StaticString=#filePath,line:UInt=#line) { expectTrue(a != b,file:file,line:line) }
func expectThrows(_ expression:@autoclosure () throws ->Any,file:StaticString=#filePath,line:UInt=#line) {
    do { _=try expression();failCheck("expected error",file:file,line:line) } catch {}
}
@main struct CheckRunner {
    static func main() {
        let core=CoreTests(),cooling=CoolingTests(),history=HistoryTests(),curve=CurveTests()
        let checks:[(String,() throws ->Void)]=[
            ("Token counters and request records reconcile without double counting",TokenUsageTests().testCodexCountersAndRequests),
            ("Claude stream revisions normalize cache tokens without retaining chat",TokenUsageTests().testClaudeStreamRevisionsAndCaches),
            ("Forked token histories exclude inherited and unresolved counter prefixes",TokenUsageTests().testForkReplayAndMissingParent),
            ("Token parsing rejects invalid numbers and respects period boundaries",TokenUsageTests().testInvalidCountsAndReportBoundaries),
            ("Token scans skip large transcript lines and count counter resets",TokenUsageTests().testLargeNonUsageLinesAndCounterReset),
            ("Token scanning resumes partial lines and handles truncation and cache recovery",TokenUsageTests().testIncrementalPartialLinesTruncationAndCache),
            ("Power history retains original timestamps and measured peaks after compaction",ElectricityPowerTests().testRealSamplesSurviveCompaction),
            ("Power curves and inspection preserve outages and restart gaps",ElectricityPowerTests().testGapsAndRestartStaySeparate),
            ("Power history rejects invalid data and never derives legacy watts",ElectricityPowerTests().testRejectsInvalidAndDoesNotInventLegacyPower),
            ("Power integrates to kWh without mixing measurement sources",ElectricityUsageTests().testIntegrationAndSources),
            ("Electricity history excludes outages, sleep and restart gaps",ElectricityUsageTests().testOutagesSleepAndRestart),
            ("Electricity ignores invalid power, duplicate samples and backwards clocks",ElectricityUsageTests().testInvalidReadingsAndClockJumps),
            ("Electricity periods split midnight and retain DST calendar boundaries",ElectricityUsageTests().testCalendarBoundariesAndDST),
            ("Electricity archives reject corrupt and duplicate records",ElectricityUsageTests().testArchiveValidation),
            ("Named fan scenes persist curves and explicit resume intent",FanScenesTests().testSceneStorageAndRestoration),
            ("Invalid or deleted fan scenes cannot silently restore",FanScenesTests().testInvalidScenesCannotRestoreOrOverwrite),
            ("Continuous control exceeds thirty minutes and retains recovery",FanScenesTests().testContinuousControlOutlivesThirtyMinutesAndStops),
            ("Timed fan control and continuous protocol stay bounded",FanScenesTests().testTimedControlAndProtocolBoundaries),
            ("Application scenes prefer foreground and follow workload lifetime",FanAutomationTests().testForegroundPriorityAndWorkloadLifetime),
            ("Application mappings persist and move without duplicates",FanAutomationTests().testMappingsMoveAndSurviveRelaunch),
            ("Application rules reject invalid input and removed scenes",FanAutomationTests().testUntrustedRulesAreBoundedAndDeletedScenesDoNotRun),
            ("One-shot fan timers are bounded and count sleep without clock extension",FanStopTimerTests().testOneShotClockAndSleepBoundaries),
            ("Saved durations migrate back to continuous without losing scenes",FanStopTimerTests().testLegacyDurationsCannotBecomeTheNextDefault),
            ("Stable release versions compare numerically",ReleaseVersionTests().testNumericVersions),
            ("Update metadata excludes drafts, previews and malformed payloads",ReleaseVersionTests().testPublishedMetadata),
            ("All macOS versions share readable chart ticks",ChartCoordinatesTests().testSharedAxisTicks),
            ("Big Sur chart inspection preserves signed values and coordinates",ChartCoordinatesTests().testSignedValuesAndInspection),
            ("Big Sur fan dragging clamps outside the chart",ChartCoordinatesTests().testCurveDragClampsAtPlotEdges),
            ("Common sensor histories match cards and preserve signed power",CommonSensorHistoryTests().testMatchesCardsAndPreservesSignedPower),
            ("Common sensor outages and sleep preserve gaps and known cards",CommonSensorHistoryTests().testOutagesAndSleepBreakLinesWithoutLosingCards),
            ("Common sensor windows bound retention and ignore stale samples",CommonSensorHistoryTests().testTimeWindowsRetentionAndOutOfOrderSamples),
            ("Sensor names respect platform, case and measurement kind",SensorCatalogTests().testPlatformAndCaseSensitiveNames),
            ("Common readings preserve sources, missing values and real zero power",SensorCatalogTests().testCommonReadingsUseRecognizedSources),
            ("Temperature control uses known platform-specific CPU and GPU probes",SensorCatalogTests().testTemperatureSourcesMatchKnownPlatformProbes),
            ("Physical sensor formats preserve signed values and reject invalid flags",SensorInventoryTests().testPhysicalFormatsAndMissingValues),
            ("Sensor inventory is complete and decodes legacy snapshots",SensorInventoryTests().testCompleteInventoryAndBackwardCompatibility),
            ("Fan progress reports verified targets and thermal override",FanTelemetryTests().testProgressFollowsVerifiedTargetsAndProtection),
            ("High temperature with low fan speed needs actual evidence",FanTelemetryTests().testHighTemperatureAndLowFanObservationRequiresEvidence),
            ("Fan session telemetry preserves reply compatibility",FanTelemetryTests().testReplyMetadataCompatibility),
            ("RPM input honors rated ranges and high-temperature ramp",FanTelemetryTests().testRPMInputUsesRatedRangeAndThermalRamp),
            ("Continuous fan curve edits preserve decimals and persistence",curve.testContinuousEditingAndPersistence),
            ("Maximum fan curve point sets a monotonic adjustable ceiling",curve.testMaximumPointLowersCurveCeiling),
            ("Capped fan curves retain full-speed thermal protection",curve.testCappedCurveStillUsesThermalProtection),
            ("CPU and GPU share a curve using the hotter source",curve.testCPUAndGPUShareOneCurveUsingHighestTemperature),
            ("GPU curves retain cross-component protection and missing-source recovery",curve.testGPUCurveDoesNotIgnoreOtherComponentProtection),
            ("Unsupported Turbo is omitted from temperature timeline labels",NativeControlTests().testUnsupportedTurboLabels),
            ("ARM direct fan mode preserves original automatic state",AppleSiliconFanTests().testDirectAndOriginalModeRestore),
            ("ARM global handoff releases only after all fans restore",AppleSiliconFanTests().testHandoffSharedUntilAllFansRestore),
            ("ARM failed acquisition rolls back handoff",AppleSiliconFanTests().testFailedAcquisitionReleasesHandoff),
            ("ARM rejects occupied and unknown fan modes",AppleSiliconFanTests().testExistingOwnerAndUnknownModesAreRejected),
            ("ARM handoff releases after mode restore failure",AppleSiliconFanTests().testReleaseAttemptedAfterModeRestoreFailure),
            ("ARM release failures remain visible and retryable",AppleSiliconFanTests().testReleaseFailureIsReportedAndRetryable),
            ("ARM failed restore retains original mode for retry",AppleSiliconFanTests().testFailedRestoreRetainsOriginalForRetry),
            ("ARM handoff cannot masquerade as system automatic",AppleSiliconFanTests().testHandoffCannotMasqueradeAsSystemAutomatic),
            ("ARM lowercase mode without handoff flag",AppleSiliconFanTests().testLowercaseAndNoHandoffFirmware),
            ("ARM slow writes respect acquisition deadline",AppleSiliconFanTests().testSlowWritesRespectDeadline),
            ("ARM helper rejects Turbo and power requests",AppleSiliconFanTests().testARMRequestBoundary),

            ("CPU display bands respect thresholds and sustained duration",CPULoadBandsTests().testThresholdsAndDuration),
            ("CPU display bands reset across gaps and invalid samples",CPULoadBandsTests().testGapsAndMissingResetSustainedTime),
            ("CPU color runs preserve transitions and actual samples",CPULoadBandsTests().testRunsKeepTransitionsAndActualSamples),
            ("Widget state transitions coalesce without losing confirmation",WidgetTests().testReloadCoalescingKeepsConfirmedState),
            ("Widget freshness, missing readings and bounded fans",WidgetTests().testFreshnessAndMissingValues),
            ("Widget schema, bounded histories and atomic roundtrip",WidgetTests().testBoundedRoundtripAndAtomicStorage),
            ("Widget URLs only allow safe navigation",WidgetTests().testNavigationOnlyURLs),
            ("Plot preserves extrema and actual segment boundaries",MetricHistoryTests().testPlotPreservesPeaksAndSegments),
            ("Plot inspection rejects missing and distant samples",MetricHistoryTests().testPlotInspectionRejectsGaps),
            ("Fixed and automatic plot scales remain readable",MetricHistoryTests().testPlotScalesRemainReadable),
            ("Metric history preserves missing values and sample gaps",MetricHistoryTests().testMissingAndSampleGaps),
            ("Metric history is bounded and keeps actual sample timestamps",MetricHistoryTests().testBoundedHistoryAndActualTimestamps),
            ("Diagnostic metrics capture the exact evidence used by rules",DiagnosticTests().testMetricsMatchRuleEvidence),
            ("Stale, missing and invalid diagnostic metrics stay unavailable",DiagnosticTests().testStaleAndInvalidMetricsStayUnavailable),
            ("Diagnosis normal state and Turbo independence",DiagnosticTests().testNormalAndTurboIndependence),
            ("Diagnosis distinguishes sustained, stale and completed CPU work",DiagnosticTests().testSustainedVersusShortCPU),
            ("Diagnosis heat duration resets across sample gaps",DiagnosticTests().testHeatDurationAndGapReset),
            ("Elevated temperature is observed without a false fault",DiagnosticTests().testElevatedTemperatureIsObservation),
            ("Diagnosis uses native memory/thermal evidence and priority",DiagnosticTests().testThermalAndMemoryPriorities),
            ("Wake requests and disk transfers are informational",DiagnosticTests().testWakeAndDiskAreInformation),
            ("Battery advice only prepares a reviewable plan",DiagnosticTests().testBatteryOnlyPreparesPlan),
            ("Missing diagnosis data never implies healthy or zero",DiagnosticTests().testMissingAndStaleNeverHealthy),
            ("Disk counter units, PID identity and app grouping",DiagnosticTests().testDiskCountersAndGroupedActivity),
            ("Optimization baseline excludes authorization wait",DiagnosticTests().testBaselineUsesActualWriteTime),
            ("Power settings parser preserves unknown fields",PowerTests().testSettingsParsing),
            ("Power scopes, noops and Turbo independence",PowerTests().testPowerScopesAndNoops),
            ("Power preflight blocks stale supply, wake tasks and unreadable settings",PowerTests().testPowerPreflight),
            ("Partial power write failure rolls back all attempted settings",PowerTests().testPartialPowerRollback),
            ("Turbo failure rolls back system power settings",PowerTests().testTurboTransactionRollback),
            ("Power restore preserves external changes and is repeatable",PowerTests().testRestorePreservesExternalChanges),
            ("Power protocol and durable backup validation",PowerTests().testPowerProtocolValidation),
            ("Optimization comparison respects battery coverage",PowerTests().testComparisonCoverage),
            ("Sustained CPU activity groups helpers and weights time",EnergyTests().testWeightedGrouping),
            ("Sustained activity expires partial intervals",EnergyTests().testPartialIntervalExpiry),
            ("Sustained activity excludes exited and reused identities",EnergyTests().testExitedAndReusedIdentities),
            ("Sustained activity preserves gaps and unknown coverage",EnergyTests().testSamplingGapsAndUnavailableData),
            ("Mode history boundaries and gaps",{
                var h=ModeHistory();let t=Date(timeIntervalSince1970:1000)
                h.append(date:t,mode:"自动",session:nil,temperature:60,load:20)
                h.append(date:t.addingTimeInterval(2),mode:"自动",session:nil,temperature:62,load:22)
                expectEqual(h.records[1].elapsed,2)
                expectEqual(h.records[0].segment,h.records[1].segment)
                h.append(date:t.addingTimeInterval(4),mode:"性能",session:"a",temperature:65,load:30)
                expectEqual(h.records[2].elapsed,0)
                expectNotEqual(h.records[1].segment,h.records[2].segment)
                h.append(date:t.addingTimeInterval(6),mode:nil,session:nil,temperature:65,load:30)
                expectEqual(h.records.count,3)
                h.append(date:t.addingTimeInterval(8),mode:"性能",session:"a",temperature:66,load:30)
                expectNotEqual(h.records[2].segment,h.records[3].segment)
                h.append(date:t.addingTimeInterval(40),mode:"性能",session:"a",temperature:67,load:30)
                expectEqual(h.records.last!.elapsed,0)
                h.append(date:t.addingTimeInterval(1900),mode:"静音",session:"b",temperature:55,load:10)
                expectEqual(h.records.count,1)
            }),
            ("Operation issue presentation preserves recovery priority",{
                expectEqual(OperationIssue("0:492 execution error: SMC F0Tg 回读不一致").title,"风扇设置尚未确认")
                expectEqual(OperationIssue("SMC F0Tg 回读不一致；恢复自动风扇失败").title,"系统自动风扇未确认恢复")
                expectEqual(OperationIssue("User canceled. (-128)").title,"授权已取消")
                expectEqual(OperationIssue("unrecognized failure").title,"操作未完成")
            }),
            ("Battery power sign and unavailable readings",{
                expectEqual(SystemTelemetry.watts(millivolts:12000,milliamps:-2000),-24)
                expectEqual(SystemTelemetry.watts(millivolts:12000,milliamps:0),0)
                expectNil(SystemTelemetry.watts(millivolts:nil,milliamps:100))
                expectNil(SystemTelemetry.watts(millivolts:12000,milliamps:Double.nan))
                expectNil(SystemTelemetry.watts(millivolts:12000,milliamps:Double(UInt64.max)))
            }),
            ("Turbo changes create distinct chart segments",NativeControlTests().testTurboSegments),
            ("Per-process CPU units and PID reuse",NativeControlTests().testProcessCPUAccounting),
            ("Native process scanner reads live process counters",NativeControlTests().testNativeProcessSampler),
            ("Sensor selection and missing-source gaps",NativeControlTests().testSourcesAndGaps),
            ("Timeline decimation preserves peaks and boundaries",NativeControlTests().testDecimationPreservesExtremes),
            ("Native control allowlist and bidirectional framing",NativeControlTests().testAllowlistAndFraming),
            ("Confirmation only follows all verified fan writes",NativeControlTests().testAppliedOnlyAfterVerifiedWrites),
            ("CPU normalization",core.testNormalizedCPUUsageAndZeroDelta),
            ("CPU counter rollover",core.testCPUCounterRollover),
            ("Turbo versus system limits",core.testTurboDisabledDoesNotImplySystemThrottling),
            ("Missing metrics",core.testMissingLimitsStayUnknown),
            ("Evidence-based attribution",core.testAttributionRequiresEvidence),
            ("Delayed SMC commits and bounded mismatch",{
                var clock=0.0
                expectTrue(SMCVerification.waitFor(1,now:{clock},read:{clock>=0.6 ? 1:0},wait:{clock+=0.05}))
                expectTrue(clock>=0.65)
                clock=0
                expectFalse(SMCVerification.waitFor(1,now:{clock},read:{0},wait:{clock+=0.05}))
                expectTrue(clock>=2 && clock<2.1)
                clock=0
                expectFalse(SMCVerification.waitFor(1,now:{clock},read:{clock==0 ? 1:0},wait:{clock+=0.05}))
                clock=0
                expectFalse(SMCVerification.waitFor(1,now:{clock},read:{nil},wait:{clock+=0.05}))
            }),
            ("Fan mode semantics preserve unknown and system states",{
                expectEqual(SMCVerification.manualState(local:0,flags:nil,id:0),false)
                expectEqual(SMCVerification.manualState(local:1,flags:nil,id:0),true)
                expectEqual(SMCVerification.manualState(local:3,flags:nil,id:0),false)
                expectNil(SMCVerification.manualState(local:2,flags:nil,id:0))
                expectEqual(SMCVerification.manualState(local:nil,flags:2,id:1),true)
                expectEqual(SMCVerification.manualState(local:nil,flags:2,id:0),false)
                expectNil(SMCVerification.manualState(local:nil,flags:nil,id:0))
            }),
            ("SMC numeric encoding",core.testSMCNumberEncoding),
            ("Shell quoting",core.testShellQuotingDoesNotInterpolate),
            ("Command timeout",core.testCommandTimeout),
            ("Cooling expiry and write ordering",cooling.testExpirationRestoresAllAndManualPrecedesTarget),
            ("Automatic SMC target ownership and failed target rollback",cooling.testSMCWithAutomaticTargetOwnership),
            ("Partial activation rollback",cooling.testPartialWriteFailureRollsBackBothFans),
            ("Pre-start cancellation",cooling.testCancellationBeforeStartHasNoWrites),
            ("Owner exit / stop",cooling.testOwnerExitOrStopRestoresAutomatic),
            ("Sleep lease expiry",cooling.testSleepDoesNotExtendLease),
            ("Invalid/manual preflight rejection",cooling.testManualModeAndInvalidRPMRefuseBeforeWrites),
            ("Restore failure isolation",cooling.testRestoreFailureStillAttemptsOtherFan),
            ("Turbo curve segments and alignment",history.testSwitchCreatesIndependentSegmentsAndAlignedTime),
            ("Curve gaps and missing data",history.testUnknownMissingAndGapBreakCurves),
            ("No invented comparison samples",history.testMissingComparisonNotInvented),
            ("Three visible energy policies",{
                expectEqual(ThermalProfile.energyModes,[.eco,.performance,.quiet])
                expectTrue(ThermalProfile.eco.disablesTurbo)
                expectTrue(ThermalProfile.quiet.disablesTurbo)
                expectFalse(ThermalProfile.performance.disablesTurbo)
                try ThermalProfile.eco.curve.validate()
                expectTrue(ThermalProfile.quiet.curve.percent(at:70)<ThermalProfile.eco.curve.percent(at:70))
                expectTrue(ThermalProfile.performance.curve.percent(at:70)>ThermalProfile.eco.curve.percent(at:70))
            }),
            ("Manual fan curve preserves thermal protection",{
                for value in [0.0,50,100,-10,110,Double.nan] {
                    let c=FanCurve.manual(percent:value)
                    try c.validate()
                    expectEqual(c.percent(at:95),100)
                }
                let c=FanCurve.manual(percent:40)
                expectEqual(c.percent(at:50),40)
                expectEqual(c.percent(at:80),40)
                expectTrue(c.percent(at:85)>40)
                let fans=FakeFans();fans.rejectAutomaticTargetWrites=true;var clock=0.0
                try CurveLease.run(hardware:fans,curve:c,duration:4,sample:{curve.snapshot(clock<2 ? 50:95)},now:{clock},isCancelled:{false},wait:{clock+=2})
                expectEqual(fans.targets,[5500,5500]);expectEqual(fans.modes,[false,false])
            }),
            ("Fan curve validation and interpolation",curve.testPresetValidationAndInterpolation),
            ("Fan safety overrides and rated RPM",curve.testSafetyOverridesAndRatedRPM),
            ("Dynamic fan curve and cleanup",curve.testDynamicCurveAndCleanup),
            ("Missing control sensor recovery",curve.testMissingSensorRestoresAutomatic),
            ("GPU unavailability and partial writes",curve.testGPUUnavailableAndPartialWriteFailure),
            ("Sensor category mapping",curve.testStorageClassificationDoesNotMislabelPalmRest)
        ]
        for (name,run) in checks {
            let before=failures
            do { try run() } catch { failCheck(error.localizedDescription,file:#filePath,line:#line) }
            print("\(failures==before ? "PASS":"FAIL"): \(name)")
        }
        print("\(checks.count) checks; \(failures) failures. No hardware writes performed.")
        exit(failures==0 ? 0:1)
    }
}
