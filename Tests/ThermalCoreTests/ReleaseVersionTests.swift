import Foundation
import ThermalCore

final class ReleaseVersionTests {
    func testNumericVersions() {
        expectTrue(ReleaseVersion("1.10.0")!>ReleaseVersion("1.9.9")!)
        expectTrue(ReleaseVersion("2.0.0")!>ReleaseVersion("1.99.99")!)
        expectTrue(ReleaseVersion("1.18.4")!>ReleaseVersion("1.18.3")!)
        expectEqual(ReleaseVersion("v1.18.3"),ReleaseVersion("1.18.3"))
        expectEqual(ReleaseVersion(" 1.18.3\n")?.description,"1.18.3")
        for bad in ["","v","1.18","1..3","1.18.4.0","-1.18.4","1.18.4-beta.1","1.18.4+dev","1.18.4/evil","1.18.999999999999999999999999999999","一.18.3"] {
            expectNil(ReleaseVersion(bad))
        }
    }
    func testPublishedMetadata()throws {
        let site=Data(#"{"version":"1.18.4","build":"271","siteCommit":"unrelated"}"#.utf8)
        let github=Data(#"{"tag_name":"v1.19.0","draft":false,"prerelease":false,"html_url":"https://untrusted.example"}"#.utf8)
        let versions=[try ReleaseMetadata.version(from:site,source:.website),try ReleaseMetadata.version(from:github,source:.github)]
        expectEqual(versions.max()?.description,"1.19.0")
        for invalid in [#"{"tag_name":"v9.0.0","draft":true,"prerelease":false}"#,
                        #"{"tag_name":"v9.0.0","draft":false,"prerelease":true}"#,
                        #"{"tag_name":"v9.0.0"}"#,
                        #"{"tag_name":"v9.0.0-beta.1","draft":false,"prerelease":false}"#] {
            expectThrows(try ReleaseMetadata.version(from:Data(invalid.utf8),source:.github))
        }
        expectThrows(try ReleaseMetadata.version(from:Data("<html>unavailable</html>".utf8),source:.website))
        expectThrows(try ReleaseMetadata.version(from:Data(#"{"version":"latest"}"#.utf8),source:.website))
        expectThrows(try ReleaseMetadata.version(from:Data(repeating:32,count:262_145),source:.website))
    }
}
