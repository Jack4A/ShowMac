import AppKit
import ThermalCore

@MainActor enum AppUpdateCheck {
    private final class FixtureFetcher:AppUpdateFetching {
        var requests:[(ReleaseMetadataSource,@MainActor(Result<ReleaseVersion,Error>)->Void)]=[]
        var cancelled=0
        func fetch(_ source:ReleaseMetadataSource,completion:@escaping @MainActor(Result<ReleaseVersion,Error>)->Void){requests.append((source,completion))}
        func cancel(){cancelled+=1}
        func finish(_ source:ReleaseMetadataSource,_ version:String?) {
            guard let index=requests.firstIndex(where:{$0.0==source}) else{fatalError("Missing request")}
            let callback=requests.remove(at:index).1
            callback(version.flatMap(ReleaseVersion.init).map{.success($0)} ?? .failure(ReleaseMetadataError.invalid))
        }
    }
    static func run() {
        guard CommandLine.arguments.contains("--ui-check") else {print("Use --app-update-check --ui-check.");exit(2)}
        func require(_ result:Bool,_ message:String){if !result {print("FAIL: "+message);exit(1)}}
        var clock=Date(timeIntervalSince1970:1_800_000_000)
        let fetcher=FixtureFetcher()
        let controller=AppUpdateController(installedVersion:ReleaseVersion("1.18.3"),defaults:nil,fetcher:fetcher,now:{clock})
        controller.checkNow();controller.checkNow()
        require(fetcher.requests.count==2,"Concurrent checks were not coalesced")
        fetcher.finish(.github,"1.19.0");fetcher.finish(.website,"1.18.4")
        require(controller.availableVersion?.description=="1.19.0" && controller.state == .available,"Stale website hid a newer GitHub release")
        require(controller.lastCheckedAt==clock,"Successful check was not timestamped")
        controller.checkIfDue();require(fetcher.requests.isEmpty,"Daily check ran twice")
        clock=clock.addingTimeInterval(86401);controller.checkIfDue()
        require(fetcher.requests.count==2,"A new day did not schedule a check")
        fetcher.finish(.github,nil);fetcher.finish(.website,"1.19.0")
        require(controller.state == .available,"Website fallback failed")
        controller.checkNow();fetcher.finish(.github,nil);fetcher.finish(.website,nil)
        require(controller.state == .failed && controller.availableVersion != nil,"Outage erased a previously found update or claimed success")
        require(controller.statusText==L("暂时无法检查更新，请稍后重试。"),"Cached update hid a failed manual refresh")
        controller.checkNow()
        controller.automaticChecks=false
        require(fetcher.cancelled==1 && controller.state != .checking,"Opting out did not cancel a check")
        fetcher.finish(.github,"99.0.0");fetcher.finish(.website,"99.0.0")
        require(controller.availableVersion?.description=="1.19.0","Cancelled response overwrote state")
        clock=clock.addingTimeInterval(86401);controller.checkIfDue()
        require(fetcher.requests.isEmpty,"Disabled background checks still made requests")
        controller.checkNow();fetcher.finish(.github,"1.18.3");fetcher.finish(.website,nil)
        require(controller.state == .current && controller.availableVersion==nil,"Manual check while automatic checks are off failed")
        controller.shutdown()
        let newer=FixtureFetcher(),preview=AppUpdateController(installedVersion:ReleaseVersion("2.0.0"),defaults:nil,fetcher:newer)
        preview.checkNow();newer.finish(.website,"1.18.3");newer.finish(.github,"1.18.4")
        require(preview.state == .current && preview.availableVersion==nil,"Installed development version was offered a downgrade")
        preview.shutdown()
        let suite="ShowMac.UpdateCheck.Fixture."+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer{defaults.removePersistentDomain(forName:suite)}
        let cacheFetcher=FixtureFetcher()
        let first=AppUpdateController(installedVersion:ReleaseVersion("1.18.3"),defaults:defaults,fetcher:cacheFetcher,now:{clock})
        first.checkNow();cacheFetcher.finish(.website,"1.18.4");cacheFetcher.finish(.github,nil);first.shutdown()
        let restored=AppUpdateController(installedVersion:ReleaseVersion("1.18.3"),defaults:defaults,fetcher:FixtureFetcher(),now:{clock})
        require(restored.state == .available && restored.availableVersion?.description=="1.18.4" && restored.lastCheckedAt==clock,"Restart lost cached update discovery")
        restored.automaticChecks=false;restored.shutdown()
        let optedOut=AppUpdateController(installedVersion:ReleaseVersion("1.18.3"),defaults:defaults,fetcher:FixtureFetcher())
        require(!optedOut.automaticChecks,"Automatic-check preference was not retained")
        optedOut.shutdown()
        require(AppInfo.releasesURL.absoluteString=="https://github.com/Jack4A/ShowMac/releases/latest","Untrusted download destination")
        for language in ["en","zh-Hans"] {
            AppLocalization.shared.set(language)
            require(AppInfo.downloadURL.absoluteString=="https://show-mac.cc/"+(language=="en" ? "en":"zh")+"/#download","Wrong localized download destination")
        }
        print("PASS: two-source updates, numeric version selection, daily scheduling, request coalescing, offline fallback, opt-out/cancellation, restart persistence and trusted localized download destinations. Fixture responses only; no network requests or user preference changes.")
    }
}
