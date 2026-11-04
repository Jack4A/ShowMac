import AppKit

enum AppInfo {
    static let developer="Jack4A"
    static let developerURL=URL(string:"https://github.com/Jack4A")!
    static let repositoryURL=URL(string:"https://github.com/Jack4A/ShowMac")!
    static let releasesURL=repositoryURL.appendingPathComponent("releases/latest")
    static let releaseMetadataURL=URL(string:"https://show-mac.cc/release.json")!
    static let githubReleaseAPIURL=URL(string:"https://api.github.com/repos/Jack4A/ShowMac/releases/latest")!
    static var downloadURL:URL {URL(string:"https://show-mac.cc/"+(AppLocalization.shared.resolvedLanguage.hasPrefix("zh") ? "zh":"en")+"/#download")!}
    static var version:String {Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? ""}

    // Offscreen UI checks do not launch NSApplication; read the bundled artwork
    // directly rather than asking the application/LaunchServices for its icon.
    @MainActor static let icon:NSImage?=Bundle.main.url(forResource:"AppIcon",withExtension:"icns").flatMap {NSImage(contentsOf:$0)}

    static var versionLabel:String {
        let version=Self.version.isEmpty ? "—":Self.version
        let build=Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "—"
        return version+" ("+build+")"
    }

    @MainActor static func showAbout() {
        let paragraph=NSMutableParagraphStyle();paragraph.alignment = .center
        let attributes:[NSAttributedString.Key:Any]=[
            .font:NSFont.systemFont(ofSize:NSFont.smallSystemFontSize),
            .foregroundColor:NSColor.labelColor,.paragraphStyle:paragraph
        ]
        let credits=NSMutableAttributedString(string:L("开发者")+" · ",attributes:attributes)
        var linkAttributes=attributes
        linkAttributes[.link]=developerURL;linkAttributes[.foregroundColor]=NSColor.linkColor
        credits.append(NSAttributedString(string:"@"+developer,attributes:linkAttributes))
        credits.append(NSAttributedString(string:"\n"+L("免费开源 · MIT 许可证")+"\n",attributes:attributes))
        linkAttributes[.link]=repositoryURL
        credits.append(NSAttributedString(string:"GitHub",attributes:linkAttributes))
        NSApp.orderFrontStandardAboutPanel(options:[.credits:credits])
        NSApp.activate(ignoringOtherApps:true)
    }
}
