import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class StoreModel: ObservableObject {
    @Published private(set) var history: [StoreSample] = []
    @Published var page = 0
    @Published var minutes = 10
    @Published var theme = UserDefaults.standard.string(forKey: "theme") ?? "system" {
        didSet { UserDefaults.standard.set(theme, forKey: "theme") }
    }
    @Published var language = UserDefaults.standard.string(forKey: "language") ?? "system" {
        didSet { UserDefaults.standard.set(language, forKey: "language") }
    }
    @Published var menuCPU = UserDefaults.standard.object(forKey: "menuCPU") as? Bool ?? true { didSet { saveMenu() } }
    @Published var menuMemory = UserDefaults.standard.bool(forKey: "menuMemory") { didSet { saveMenu() } }
    @Published var menuBattery = UserDefaults.standard.bool(forKey: "menuBattery") { didSet { saveMenu() } }
    @Published var menuColor = UserDefaults.standard.string(forKey: "menuColor") ?? "monochrome" { didSet { saveMenu() } }
    @Published var menuSpacing = UserDefaults.standard.object(forKey: "menuSpacing") as? Double ?? 18 { didSet { saveMenu() } }
    @Published var interval = UserDefaults.standard.object(forKey: "interval") as? Double ?? 2 {
        didSet { UserDefaults.standard.set(interval, forKey: "interval"); start() }
    }
    var didSample: (() -> Void)?
    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.jackjohn.showmac.telemetry", qos: .utility)
    private let sampler = StoreSampler()
    var latest: StoreSample? { history.last }
    var isChinese: Bool { language == "zh" || (language == "system" && (Locale.preferredLanguages.first ?? "en").hasPrefix("zh")) }
    func text(_ en: String, _ zh: String) -> String { isChinese ? zh : en }
    var scheme: ColorScheme? { theme == "dark" ? .dark : theme == "light" ? .light : nil }
    var visibleSamples: [StoreSample] { history.filter { $0.date >= Date().addingTimeInterval(-Double(minutes) * 60) } }
    func start() {
        timer?.invalidate()
        let seconds = [1.0,2.0,5.0,10.0].contains(interval) ? interval : 2
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in self?.refresh() }
    }
    func refresh() {
        queue.async { [weak self] in
            guard let self = self else { return }
            let sample = self.sampler.sample()
            DispatchQueue.main.async {
                self.history.append(sample)
                self.history.removeAll { $0.date < sample.date.addingTimeInterval(-1800) }
                self.didSample?()
            }
        }
    }
    private func saveMenu() {
        let defaults = UserDefaults.standard
        defaults.set(menuCPU, forKey: "menuCPU"); defaults.set(menuMemory, forKey: "menuMemory")
        defaults.set(menuBattery, forKey: "menuBattery"); defaults.set(menuColor, forKey: "menuColor")
        defaults.set(menuSpacing, forKey: "menuSpacing"); didSample?()
    }
    func thermalText(_ value: ProcessInfo.ThermalState?) -> String {
        guard let value = value else { return "—" }
        switch value {
        case .nominal: return text("Normal", "正常")
        case .fair: return text("Warm", "偏热")
        case .serious: return text("High", "较高")
        case .critical: return text("Critical", "严重")
        @unknown default: return text("Unknown", "未知")
        }
    }
    func percent(_ value: Double?) -> String { value.map { String(format: "%.0f%%", $0) } ?? "—" }
    func memory(_ value: Double?) -> String { value.map { String(format: "%.1f GB", $0 / 1_073_741_824) } ?? "—" }
    func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "ShowMac-" + ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-") + ".csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let formatter = ISO8601DateFormatter()
        var rows = ["timestamp,cpu_percent,memory_bytes,battery_percent,thermal_state,low_power"]
        for sample in history {
            rows.append([formatter.string(from: sample.date), sample.cpu.map(String.init(describing:)) ?? "", sample.memoryBytes.map(String.init(describing:)) ?? "", sample.battery.map(String.init(describing:)) ?? "", String(sample.thermal.rawValue), sample.lowPower.map(String.init(describing:)) ?? ""].joined(separator: ","))
        }
        do { try (rows.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8) }
        catch { let alert = NSAlert(error: error); alert.runModal() }
    }
}
