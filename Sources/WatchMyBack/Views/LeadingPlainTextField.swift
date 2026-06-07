import AppKit
import SwiftUI

struct LeadingPlainTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.isEditable = true
        field.isSelectable = true
        field.alignment = .left
        field.focusRingType = .none
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 0
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.delegate = context.coordinator
        field.font = .preferredFont(forTextStyle: .body)
        field.placeholderString = placeholder
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
        nsView.alignment = .left
        nsView.focusRingType = .none
        nsView.lineBreakMode = .byWordWrapping
        nsView.maximumNumberOfLines = 0
        nsView.cell?.wraps = true
        nsView.cell?.isScrollable = false
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
