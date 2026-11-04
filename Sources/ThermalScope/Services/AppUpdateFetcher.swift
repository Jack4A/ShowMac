import Foundation
import ThermalCore

@MainActor protocol AppUpdateFetching:AnyObject {
    func fetch(_ source:ReleaseMetadataSource,completion:@escaping @MainActor(Result<ReleaseVersion,Error>)->Void)
    func cancel()
}

/// Callback-based URLSession keeps the network path available on macOS 11.
@MainActor final class AppUpdateFetcher:AppUpdateFetching {
    private let session:URLSession
    private var tasks:[URLSessionDataTask]=[]

    init() {
        let configuration=URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest=8
        configuration.timeoutIntervalForResource=15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache=nil
        configuration.httpCookieStorage=nil
        configuration.httpShouldSetCookies=false
        session=URLSession(configuration:configuration)
    }
    func fetch(_ source:ReleaseMetadataSource,completion:@escaping @MainActor(Result<ReleaseVersion,Error>)->Void) {
        let url=source == .website ? AppInfo.releaseMetadataURL:AppInfo.githubReleaseAPIURL
        var request=URLRequest(url:url)
        request.setValue("showmac-update-check",forHTTPHeaderField:"User-Agent")
        request.setValue(source == .github ? "application/vnd.github+json":"application/json",forHTTPHeaderField:"Accept")
        if source == .github {request.setValue("2026-03-10",forHTTPHeaderField:"X-GitHub-Api-Version")}
        tasks.removeAll{$0.state == .completed || $0.state == .canceling}
        let task=session.dataTask(with:request) {data,response,error in
            let result:Result<ReleaseVersion,Error>
            do {
                if let error {throw error}
                guard let response=response as? HTTPURLResponse,response.statusCode==200,
                      response.url?.scheme=="https",response.url?.host==url.host,let data else{throw ReleaseMetadataError.invalid}
                result = .success(try ReleaseMetadata.version(from:data,source:source))
            }catch{result = .failure(error)}
            DispatchQueue.main.async{completion(result)}
        }
        tasks.append(task);task.resume()
    }
    func cancel() {tasks.forEach{$0.cancel()};tasks.removeAll()}
}
