import AppKit
import SwiftUI

/// Keep system controls on Big Sur, and use the richer native APIs when present.
struct AppNativeButtonStyle: PrimitiveButtonStyle {
    var prominent = false
    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 12,*),!PlatformUI.classic {
            if prominent { Button(configuration).buttonStyle(.borderedProminent) }
            else { Button(configuration).buttonStyle(.bordered) }
        } else { Button(configuration).buttonStyle(DefaultButtonStyle()) }
    }
}

extension View {
    @ViewBuilder func appHideScrollIndicators() -> some View {
        if #available(macOS 13,*),!PlatformUI.classic { scrollIndicators(.hidden) }
        else { background(ScrollIndicatorHider()) }
    }
    func appMonospacedDigit() -> some View { modifier(AppMonospacedDigits()) }
    func appBackground<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View {
        background(content(), alignment: alignment)
    }
    func appBackground<S: Shape>(_ color: Color, in shape: S) -> some View { background(shape.fill(color)) }
    func appOverlay<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View {
        overlay(content(), alignment: alignment)
    }
    func appMask<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View {
        mask(content().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment))
    }
    @ViewBuilder func appTextSelection() -> some View {
        if #available(macOS 12,*),!PlatformUI.classic { textSelection(.enabled) } else { self }
    }
    @ViewBuilder func appControlSize(_ size: ControlSize) -> some View {
        if #available(macOS 12,*),!PlatformUI.classic { controlSize(size) } else { self }
    }
    @ViewBuilder func appGroupedForm() -> some View {
        if #available(macOS 13,*),!PlatformUI.classic { formStyle(.grouped) } else { self }
    }
    @ViewBuilder func appHideToolbarBackground() -> some View {
        if #available(macOS 13,*),!PlatformUI.classic { toolbarBackground(.hidden, for: .windowToolbar) } else { self }
    }
}

private struct ScrollIndicatorHider: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) { view.hideIndicators() }
    final class Probe: NSView {
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); hideIndicators() }
        func hideIndicators() {
            DispatchQueue.main.async { [weak self] in
                var parent=self?.superview
                for _ in 0..<6 {
                    guard let view=parent else{return}
                    if let scroll=view as? NSScrollView {
                        scroll.hasVerticalScroller=false;scroll.hasHorizontalScroller=false;return
                    }
                    parent=view.superview
                }
            }
        }
    }
}

private struct AppMonospacedDigits: ViewModifier {
    @Environment(\.font) private var font
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 12,*),!PlatformUI.classic { content.monospacedDigit() }
        else { content.font((font ?? .body).monospacedDigit()) }
    }
}

struct AppPopoverMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover; view.blendingMode = .withinWindow; view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct AppTimelineContext { let date: Date }
struct AppTimelineView<Content: View>: View {
    let interval: TimeInterval
    let content: (AppTimelineContext) -> Content
    init(interval:TimeInterval,@ViewBuilder content:@escaping(AppTimelineContext)->Content) {
        self.interval=interval;self.content=content
    }
    @StateObject private var clock = VisibleClock()
    @ViewBuilder var body: some View {
        if #available(macOS 12,*),!PlatformUI.classic {
            TimelineView(.periodic(from: Date(), by: interval)) { context in content(AppTimelineContext(date: context.date)) }
        } else {
            content(AppTimelineContext(date: clock.date)).onAppear { clock.start(interval) }.onDisappear { clock.stop() }
        }
    }
    private final class VisibleClock: ObservableObject {
        @Published var date = Date()
        private var timer: Timer?
        func start(_ interval: TimeInterval) {
            stop(); date = Date()
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.date = Date() }
        }
        func stop() { timer?.invalidate(); timer = nil }
        deinit { timer?.invalidate() }
    }
}
