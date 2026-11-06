import AppKit
import SwiftUI
import ThermalCore

@MainActor enum AgentProviderArtwork {
    private static var cache:[String:NSImage]=[:]
    static func image(_ provider:TokenProvider)->NSImage? {
        guard [TokenProvider.codex,.claude].contains(provider) else{return nil}
        if let image=cache[provider.rawValue] {return image}
        guard let url=Bundle.main.url(forResource:provider.rawValue,withExtension:"pdf",subdirectory:"ProviderIcons") ?? Bundle.main.url(forResource:provider.rawValue,withExtension:"pdf"),let image=NSImage(contentsOf:url),image.isValid else{return nil}
        image.isTemplate=true;cache[provider.rawValue]=image;return image
    }
    static func title(_ provider:TokenProvider)->String {provider == .codex ? "Codex":provider.title}
    static func color(_ provider:TokenProvider)->Color {provider == .claude ? Color(red:0.77,green:0.40,blue:0.27):Palette.violet}
}
struct AgentProviderBadge:View {
    let provider:TokenProvider
    var size:CGFloat=30
    var background=true
    var body:some View {
        Group {
            if let image=AgentProviderArtwork.image(provider) {Image(nsImage:image).renderingMode(.template).resizable().scaledToFit()}
            else {Image(systemName:AppSymbols.resolve("terminal")).resizable().scaledToFit()}
        }.foregroundColor(AgentProviderArtwork.color(provider)).padding(size*0.12).frame(width:size,height:size)
            .appBackground(background ? AgentProviderArtwork.color(provider).opacity(0.08):Color.clear,in:RoundedRectangle(cornerRadius:size*0.25))
            .accessibilityLabel(AgentProviderArtwork.title(provider))
    }
}
