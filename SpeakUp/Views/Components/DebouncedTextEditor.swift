import SwiftUI
import UIKit

struct DebouncedTextEditor: UIViewRepresentable {
    @Binding var text: String
    var isDisabled: Bool = false
    var placeholder: String = ""
    var minHeight: CGFloat = 200
    var requestFocus: Bool = false

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.textColor = .white
        textView.isEditable = !isDisabled
        textView.isScrollEnabled = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.autocorrectionType = .default
        textView.spellCheckingType = .default
        textView.text = text

        textView.setContentHuggingPriority(.defaultLow, for: .vertical)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        // Placeholder label
        let placeholderLabel = UILabel()
        placeholderLabel.text = placeholder
        placeholderLabel.font = UIFont.preferredFont(forTextStyle: .body)
        placeholderLabel.textColor = UIColor.white.withAlphaComponent(0.3)
        placeholderLabel.tag = 999
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
        ])
        placeholderLabel.isHidden = !text.isEmpty

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.isEditable = !isDisabled

        if textView.text != text && !context.coordinator.isUserEditing {
            textView.text = text
        }

        // Update placeholder visibility
        if let placeholderLabel = textView.viewWithTag(999) as? UILabel {
            placeholderLabel.isHidden = !textView.text.isEmpty
            placeholderLabel.text = placeholder
        }

        if requestFocus && !textView.isFirstResponder && !isDisabled {
            DispatchQueue.main.async { textView.becomeFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        var isUserEditing = false
        private var debounceTask: Task<Void, Never>?

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isUserEditing = true
        }

        func textViewDidChange(_ textView: UITextView) {
            // Update placeholder visibility immediately
            if let placeholderLabel = textView.viewWithTag(999) as? UILabel {
                placeholderLabel.isHidden = !textView.text.isEmpty
            }

            debounceTask?.cancel()
            debounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                self.text.wrappedValue = textView.text
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isUserEditing = false
            debounceTask?.cancel()
            text.wrappedValue = textView.text
        }
    }
}
