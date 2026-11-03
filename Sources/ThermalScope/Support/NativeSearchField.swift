import AppKit
import SwiftUI

/// Embed the system search field, including its native clear button and focus behavior.
struct NativeSearchField:NSViewRepresentable {
    let title:String
    @Binding var text:String
    func makeCoordinator()->Coordinator {Coordinator(text:$text)}
    func makeNSView(context:Context)->NSSearchField {
        let field=NSSearchField()
        field.delegate=context.coordinator
        field.sendsSearchStringImmediately=true
        field.setContentHuggingPriority(.defaultLow,for:.horizontal)
        return field
    }
    func updateNSView(_ field:NSSearchField,context:Context) {
        context.coordinator.text=$text
        field.placeholderString=title
        field.setAccessibilityLabel(title)
        if field.stringValue != text {field.stringValue=text}
    }
    final class Coordinator:NSObject,NSSearchFieldDelegate {
        var text:Binding<String>
        init(text:Binding<String>){self.text=text}
        func controlTextDidChange(_ notification:Notification) {
            if let field=notification.object as? NSSearchField {text.wrappedValue=field.stringValue}
        }
    }
}
