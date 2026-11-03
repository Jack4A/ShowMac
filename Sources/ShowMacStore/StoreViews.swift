import SwiftUI

struct StoreChart: View {
    let samples: [StoreSample]
    let maximum: Double
    let interval: TimeInterval
    let value: (StoreSample) -> Double?
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Path { path in
                    for index in 0...4 {
                        let y = geometry.size.height * CGFloat(index) / 4
                        path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                }.stroke(Color.secondary.opacity(0.13), style: StrokeStyle(lineWidth: 1, dash: [3,5]))
                Path { path in
                    guard let end = samples.last?.date else { return }
                    let start = end.addingTimeInterval(-interval)
                    var previous: Date?
                    for sample in samples {
                        guard sample.date >= start, let number = value(sample), number.isFinite else { previous = nil; continue }
                        let point = CGPoint(x: CGFloat(sample.date.timeIntervalSince(start) / interval) * geometry.size.width, y: geometry.size.height * CGFloat(1 - min(1,max(0,number / maximum))))
                        if let previous = previous, sample.date.timeIntervalSince(previous) < 30 { path.addLine(to: point) }
                        else { path.move(to: point) }
                        previous = sample.date
                    }
                }.stroke(Color(red:0.70,green:0.58,blue:0.84), style: StrokeStyle(lineWidth:2.2,lineCap:.round,lineJoin:.round))
            }
        }
        .accessibilityLabel("Recent sampled history")
    }
}
struct StoreRoot: View {
    @ObservedObject var model: StoreModel
    @Environment(\.colorScheme) private var scheme
    private var canvas: Color { scheme == .dark ? Color(red:0.095,green:0.09,blue:0.12) : Color(red:0.965,green:0.966,blue:0.975) }
    private var card: Color { scheme == .dark ? Color(red:0.145,green:0.138,blue:0.174) : .white }
    private let accent = Color(red:0.70,green:0.58,blue:0.84)
    var body: some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:14) {
                Text("ShowMac").font(.system(size:18,weight:.semibold)).padding(.bottom,24)
                navigation(model.text("Live monitor","实时监测"),"waveform.path.ecg",0)
                Spacer()
                navigation(model.text("Settings","设置"),"gearshape",1)
            }.padding(20).padding(.top,20).frame(width:200).frame(maxHeight:.infinity)
                .background(scheme == .dark ? Color(red:0.18,green:0.16,blue:0.20) : Color(red:0.91,green:0.90,blue:0.93))
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    if model.page == 0 { dashboard } else { settings }
                }.padding(28).frame(maxWidth:1100,alignment:.leading).frame(maxWidth:.infinity)
            }.background(canvas)
        }.frame(minWidth:900,minHeight:680).accentColor(accent).preferredColorScheme(model.scheme)
    }
    private func navigation(_ title:String,_ symbol:String,_ page:Int) -> some View {
        Button { model.page=page } label: {
            HStack(spacing:14) { Image(systemName:symbol).font(.system(size:18)).frame(width:24).foregroundColor(model.page == page ? accent : .secondary);Text(title).font(.system(size:14,weight:.semibold));Spacer() }
                .padding(.horizontal,14).padding(.vertical,14).contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius:14).fill(model.page == page ? Color.primary.opacity(scheme == .dark ? 0.14:0.06) : .clear))
        }.buttonStyle(PlainButtonStyle())
    }
    private var dashboard: some View {
        VStack(alignment:.leading,spacing:24) {
            HStack { Text(model.text("A clearer view of your Mac.","看清 Mac 此刻的状态。")).foregroundColor(.secondary);Spacer();Button(model.text("Export CSV…","导出 CSV…")){ model.exportCSV() } }
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:16) {
                metric(model.text("CPU usage","CPU 使用率"),"cpu",model.percent(model.latest?.cpu),model.text("100% represents all cores","100% 表示全部核心"),maximum:100) { $0.cpu }
                metric(model.text("Memory used","已用内存"),"memorychip",model.memory(model.latest?.memoryBytes),model.text("of ","共 ")+model.memory(Double(ProcessInfo.processInfo.physicalMemory)),maximum:Double(ProcessInfo.processInfo.physicalMemory)) { $0.memoryBytes }
                VStack(alignment:.leading,spacing:16) {
                    Label(model.text("Thermal state","系统热状态"),systemImage:"thermometer").foregroundColor(.secondary)
                    Text(model.thermalText(model.latest?.thermal)).font(.system(size:28,weight:.semibold))
                    Text(model.text("Reported by macOS","由 macOS 报告")).font(.system(size:12)).foregroundColor(.secondary)
                }.frame(maxWidth:.infinity,minHeight:112,alignment:.leading).padding(20).background(card).cornerRadius(18)
                VStack(alignment:.leading,spacing:16) {
                    Label(model.text("Power","电源"),systemImage:"bolt").foregroundColor(.secondary)
                    Text(model.latest?.battery != nil ? model.percent(model.latest?.battery) : sourceTitle).font(.system(size:28,weight:.semibold))
                    Text(model.latest?.charging == true ? model.text("Charging","正在充电") : sourceTitle).font(.system(size:12)).foregroundColor(.secondary)
                }.frame(maxWidth:.infinity,minHeight:112,alignment:.leading).padding(20).background(card).cornerRadius(18)
            }
            VStack(alignment:.leading,spacing:22) {
                HStack {
                    Text(model.text("CPU history","CPU 近期趋势")).font(.system(size:15,weight:.semibold));Spacer()
                    Picker(model.text("Time range","时间范围"),selection:$model.minutes) { ForEach([2,10,30],id:\.self) { n in Text("\(n) "+model.text("min","分钟")).tag(n) } }.labelsHidden().frame(width:100)
                }
                HStack(spacing:12) {
                    VStack { Text("100%");Spacer();Text("50%");Spacer();Text("0%") }.font(.system(size:10)).foregroundColor(.secondary).frame(width:30)
                    StoreChart(samples:model.visibleSamples,maximum:100,interval:Double(model.minutes)*60,value:{$0.cpu})
                }.frame(height:190)
                HStack { Text(model.text("\(model.minutes) minutes ago","\(model.minutes) 分钟前"));Spacer();Text(model.text("Now","现在")) }.font(.system(size:11)).foregroundColor(.secondary)
                Divider()
                HStack { Label(model.text("Real samples · session history","真实采样 · 本次会话历史"),systemImage:"waveform.path");Spacer();Text(model.latest?.date ?? Date(),style:.time) }.font(.system(size:11)).foregroundColor(.secondary)
            }.padding(22).background(card).cornerRadius(18)
            HStack { Text(model.text("Read-only monitoring · No administrator access needed","只读监测 · 无需管理员权限"));Spacer();Text(model.text("App Store edition","App Store 版")) }.font(.system(size:11)).foregroundColor(.secondary)
        }
    }
    private var sourceTitle: String {
        guard let source=model.latest?.powerSource else { return model.text("Unavailable","暂无读数") }
        return source == "AC Power" ? model.text("AC power","外接电源") : source == "Battery Power" ? model.text("Battery","电池供电") : model.text("UPS power","UPS 供电")
    }
    private func metric(_ title:String,_ symbol:String,_ reading:String,_ detail:String,maximum:Double,value:@escaping(StoreSample)->Double?) -> some View {
        VStack(alignment:.leading,spacing:14) {
            Label(title,systemImage:symbol).foregroundColor(.secondary)
            HStack(alignment:.center) { Text(reading).font(.system(size:30,weight:.semibold)).storeDigits().lineLimit(1).minimumScaleFactor(0.8);Spacer();StoreChart(samples:Array(model.history.suffix(120)),maximum:maximum,interval:120,value:value).frame(width:82,height:32) }
            Text(detail).font(.system(size:12)).foregroundColor(.secondary)
        }.frame(maxWidth:.infinity,minHeight:112,alignment:.leading).padding(20).background(card).cornerRadius(18)
    }
    private var settings: some View {
        VStack(alignment:.leading,spacing:24) {
            Text(model.text("Make ShowMac fit the way you work.","让 ShowMac 适合你的使用习惯。")).foregroundColor(.secondary)
            GroupBox(label:Text(model.text("Appearance","外观"))) {
                VStack(spacing:16) {
                    Picker(model.text("Theme","主题"),selection:$model.theme) { Text(model.text("System","跟随系统")).tag("system");Text(model.text("Light","浅色")).tag("light");Text(model.text("Dark","深色")).tag("dark") }.pickerStyle(SegmentedPickerStyle())
                    Picker(model.text("Language","语言"),selection:$model.language) { Text(model.text("System","跟随系统")).tag("system");Text("English").tag("en");Text("简体中文").tag("zh") }
                }.padding(12).frame(maxWidth:.infinity)
            }
            GroupBox(label:Text(model.text("Menu bar","菜单栏"))) {
                VStack(alignment:.leading,spacing:16) {
                    Toggle(model.text("CPU usage","CPU 使用率"),isOn:$model.menuCPU)
                    Toggle(model.text("Memory used","已用内存"),isOn:$model.menuMemory)
                    Toggle(model.text("Battery level (when available)","电池电量（有读数时）"),isOn:$model.menuBattery)
                    Picker(model.text("Color","颜色"),selection:$model.menuColor) { Text(model.text("Monochrome","黑白")).tag("monochrome");Text(model.text("Purple","紫色")).tag("purple");Text(model.text("Blue","蓝色")).tag("blue");Text(model.text("Green","绿色")).tag("green") }
                    HStack { Text(model.text("Item spacing","组件间距"));Slider(value:$model.menuSpacing,in:0...30,step:1);Text("\(Int(model.menuSpacing)) pt").storeDigits().frame(width:44) }
                }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
            }
            GroupBox(label:Text(model.text("Sampling","采样"))) {
                VStack(alignment:.leading,spacing:16) {
                    Picker(model.text("Sample every","采样间隔"),selection:$model.interval) { ForEach([1.0,2.0,5.0,10.0],id:\.self) { n in Text("\(Int(n)) "+model.text("seconds","秒")).tag(n) } }
                    Text(model.text("Up to 30 minutes of history stays in memory and clears when you quit. Exports are saved only where you choose.","最多保留 30 分钟内存历史，退出后清空。导出文件仅保存在你选择的位置。")).font(.system(size:12)).foregroundColor(.secondary)
                    Button(model.text("Refresh now","立即刷新")){ model.refresh() }
                }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
            }
            HStack(spacing:20) { Link(model.text("Support","支持"),destination:URL(string:"http://101.37.211.18/showmac/support/")!);Link(model.text("Privacy","隐私政策"),destination:URL(string:"http://101.37.211.18/showmac/privacy/")!);Spacer();Text("ShowMac 1.0").foregroundColor(.secondary) }.font(.system(size:12))
        }
    }
}
struct StorePopover: View {
    @ObservedObject var model:StoreModel
    var open:()->Void
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { Text("ShowMac").font(.system(size:15,weight:.semibold));Spacer();Text(model.thermalText(model.latest?.thermal)).font(.system(size:12)).foregroundColor(.secondary) }
            HStack { Label(model.text("CPU usage","CPU 使用率"),systemImage:"cpu");Spacer();Text(model.percent(model.latest?.cpu)).storeDigits() }
            StoreChart(samples:Array(model.history.suffix(120)),maximum:100,interval:120,value:{$0.cpu}).frame(height:52)
            Divider()
            HStack { Label(model.text("Memory used","已用内存"),systemImage:"memorychip");Spacer();Text(model.memory(model.latest?.memoryBytes)).storeDigits() }
            if let battery=model.latest?.battery { HStack { Label(model.text("Battery","电池"),systemImage:"battery.100");Spacer();Text(model.percent(battery)) } }
            Divider()
            HStack { Button(model.text("Open ShowMac","打开 ShowMac"),action:open);Spacer();Button(model.text("Quit","退出")){NSApp.terminate(nil)} }
        }.padding(20).frame(width:330).preferredColorScheme(model.scheme)
    }
}

private extension View {
    @ViewBuilder func storeDigits() -> some View {
        if #available(macOS 12.0, *) { self.monospacedDigit() } else { self }
    }
}
