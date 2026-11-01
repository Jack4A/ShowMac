import Foundation

enum AppLanguage:String,CaseIterable,Identifiable {
    case system,en,zhHans="zh-Hans",zhHant="zh-Hant",ja,ko,de,fr,es
    var id:String {rawValue}
    var title:String {
        switch self {
        case .system:return L("跟随系统")
        case .en:return "English"
        case .zhHans:return "简体中文"
        case .zhHant:return "繁體中文"
        case .ja:return "日本語"
        case .ko:return "한국어"
        case .de:return "Deutsch"
        case .fr:return "Français"
        case .es:return "Español"
        }
    }
}
final class AppLocalization {
    static let shared=AppLocalization()
    private let lock=NSLock()
    private var resolved=AppLocalization.resolve(UserDefaults.standard.string(forKey:"appLanguage") ?? "system")
    private var traditional:[String:String]=[:]
    private let table:[String:[String:String]]
    init() {
        if let url=Bundle.main.url(forResource:"Localization",withExtension:"json"),let data=try? Data(contentsOf:url),let values=try? JSONDecoder().decode([String:[String:String]].self,from:data) {table=values}
        else {table=[:]}
    }
    private static func resolve(_ selection:String)->String {
        if selection != "system" {return selection}
        let preferred=Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("zh") {return preferred.contains("Hant") || preferred.contains("TW") || preferred.contains("HK") ? "zh-Hant":"zh-Hans"}
        return ["en","ja","ko","de","fr","es"].first(where:{preferred.hasPrefix($0)}) ?? "en"
    }
    var resolvedLanguage:String {lock.lock();defer{lock.unlock()};return resolved}
    func set(_ language:String) {let next=Self.resolve(language);lock.lock();resolved=next;lock.unlock()}
    func text(_ key:String)->String {
        let language=resolvedLanguage
        if language=="zh-Hans" {return key}
        if language=="zh-Hant" {
            lock.lock();let cached=traditional[key];lock.unlock()
            if let cached {return cached}
            let converted=key.applyingTransform(StringTransform("Hans-Hant"),reverse:false) ?? key
            lock.lock();traditional[key]=converted;lock.unlock();return converted
        }
        if let exact=table[key]?[language] ?? table[key]?["en"] {return exact}
        if key.contains(" · ") {return key.components(separatedBy:" · ").map{text($0)}.joined(separator:" · ")}
        return key
    }
}
func L(_ key:String)->String {AppLocalization.shared.text(key)}
