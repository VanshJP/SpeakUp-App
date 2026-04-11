import SwiftUI
import UIKit

/// Reference handle that a parent SwiftUI view holds to send format commands
/// into an active `RichTextEditor` without going through UIKit's keyboard
/// accessory view.
@MainActor
final class RichTextController {
    fileprivate weak var coordinator: RichTextEditor.Coordinator?

    func bold() { coordinator?.applyBold() }
    func italic() { coordinator?.applyItalic() }
    func underline() { coordinator?.applyUnderline() }
    func heading() { coordinator?.applyTextStyle(.title2, bold: true) }
    func subheading() { coordinator?.applyTextStyle(.title3, bold: true) }
    func bodyStyle() { coordinator?.applyTextStyle(.body, bold: false) }
    func bulletList() { coordinator?.applyBulletList() }
    func numberedList() { coordinator?.applyNumberedList() }
    func checklist() { coordinator?.applyChecklist() }
    func dismissKeyboard() { coordinator?.dismissKeyboard() }
}

/// Rich-text editor backed by NSAttributedString. Formatting commands are
/// driven externally via a `RichTextController` so the hosting SwiftUI view
/// can render a single unified bottom bar instead of stacking with a UIKit
/// keyboard accessory.
struct RichTextEditor: UIViewRepresentable {
    @Binding var attributedText: NSAttributedString
    @Binding var plainText: String
    var controller: RichTextController?
    var isDisabled: Bool = false
    var placeholder: String = ""
    var minHeight: CGFloat = 200
    /// One-shot focus request. When set to `true`, the editor grabs first
    /// responder once and immediately resets the binding to `false` so that
    /// subsequent re-renders (e.g. when the user taps a different field) do
    /// not steal focus back.
    @Binding var requestFocus: Bool

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isEditable = !isDisabled
        textView.isScrollEnabled = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.autocorrectionType = .default
        textView.spellCheckingType = .default
        textView.allowsEditingTextAttributes = true
        textView.tintColor = UIColor(red: 0.051, green: 0.518, blue: 0.533, alpha: 1) // teal
        textView.typingAttributes = RichTextEditor.defaultAttributes

        if attributedText.length > 0 {
            textView.attributedText = attributedText
        } else {
            textView.text = ""
        }

        textView.setContentHuggingPriority(.defaultLow, for: .vertical)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        // Placeholder label
        let placeholderLabel = UILabel()
        placeholderLabel.text = placeholder
        placeholderLabel.font = UIFont.preferredFont(forTextStyle: .body)
        placeholderLabel.textColor = UIColor.white.withAlphaComponent(0.3)
        placeholderLabel.numberOfLines = 0
        placeholderLabel.tag = 999
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor)
        ])
        placeholderLabel.isHidden = textView.attributedText.length > 0

        context.coordinator.textView = textView
        controller?.coordinator = context.coordinator
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.isEditable = !isDisabled
        controller?.coordinator = context.coordinator

        if !context.coordinator.isUserEditing,
           !textView.attributedText.isEqual(to: attributedText) {
            let selected = textView.selectedRange
            textView.attributedText = attributedText
            textView.selectedRange = selected
            textView.typingAttributes = RichTextEditor.defaultAttributes
        }

        if let placeholderLabel = textView.viewWithTag(999) as? UILabel {
            placeholderLabel.isHidden = textView.attributedText.length > 0
            placeholderLabel.text = placeholder
        }

        if requestFocus && !isDisabled {
            let binding = $requestFocus
            DispatchQueue.main.async {
                if !textView.isFirstResponder {
                    textView.becomeFirstResponder()
                }
                binding.wrappedValue = false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - Default Attributes

    static var defaultAttributes: [NSAttributedString.Key: Any] {
        [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.white
        ]
    }

    // MARK: - Markdown → Attributed String

    /// Parses a lightweight Markdown subset (headings, bold, italic, bullet and numbered
    /// lists, blank-line paragraphs) into an `NSAttributedString` styled to match the
    /// editor's default appearance. Used by the dictation formatting flow so the LLM can
    /// return Markdown and the editor can render it with real rich-text attributes.
    static func attributedString(fromMarkdown markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let bodyFont = UIFont.preferredFont(forTextStyle: .body)
        let title2Bold = boldVariant(of: UIFont.preferredFont(forTextStyle: .title2))
        let title3Bold = boldVariant(of: UIFont.preferredFont(forTextStyle: .title3))
        let textColor = UIColor.white

        let rawLines = markdown.components(separatedBy: "\n")
        for (idx, rawLine) in rawLines.enumerated() {
            var line = rawLine
            var lineFont: UIFont = bodyFont
            var prefix = ""

            if line.hasPrefix("## ") {
                line = String(line.dropFirst(3))
                lineFont = title3Bold
            } else if line.hasPrefix("# ") {
                line = String(line.dropFirst(2))
                lineFont = title2Bold
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                line = String(line.dropFirst(2))
                prefix = "•  "
            } else if let match = line.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                prefix = String(line[match])
                line = String(line[match.upperBound...])
            }

            let lineAttrs: [NSAttributedString.Key: Any] = [.font: lineFont, .foregroundColor: textColor]
            if !prefix.isEmpty {
                result.append(NSAttributedString(string: prefix, attributes: lineAttrs))
            }
            result.append(parseInlineMarkdown(line, baseFont: lineFont, color: textColor))
            if idx < rawLines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: lineAttrs))
            }
        }
        return result
    }

    private static func boldVariant(of font: UIFont) -> UIFont {
        let combined = font.fontDescriptor.symbolicTraits.union(.traitBold)
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(combined) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    private static func parseInlineMarkdown(_ text: String, baseFont: UIFont, color: UIColor) -> NSAttributedString {
        guard !text.isEmpty else {
            return NSAttributedString(string: "", attributes: [.font: baseFont, .foregroundColor: color])
        }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let parsed = try? AttributedString(markdown: text, options: options) else {
            return NSAttributedString(string: text, attributes: [.font: baseFont, .foregroundColor: color])
        }

        let result = NSMutableAttributedString()
        for run in parsed.runs {
            let chunk = String(parsed[run.range].characters)
            var traits = baseFont.fontDescriptor.symbolicTraits
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
                if intent.contains(.emphasized) { traits.insert(.traitItalic) }
            }
            var font = baseFont
            if let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) {
                font = UIFont(descriptor: descriptor, size: baseFont.pointSize)
            }
            result.append(NSAttributedString(string: chunk, attributes: [.font: font, .foregroundColor: color]))
        }
        return result
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: RichTextEditor
        weak var textView: UITextView?
        var isUserEditing = false
        private var debounceTask: Task<Void, Never>?

        init(parent: RichTextEditor) {
            self.parent = parent
        }

        // MARK: Delegate

        func textViewDidBeginEditing(_ textView: UITextView) {
            isUserEditing = true
        }

        func textViewDidChange(_ textView: UITextView) {
            if let placeholderLabel = textView.viewWithTag(999) as? UILabel {
                placeholderLabel.isHidden = textView.attributedText.length > 0
            }

            debounceTask?.cancel()
            debounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                self.parent.attributedText = textView.attributedText
                self.parent.plainText = textView.text ?? ""
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isUserEditing = false
            debounceTask?.cancel()
            parent.attributedText = textView.attributedText
            parent.plainText = textView.text ?? ""
        }

        // MARK: Format Commands

        func dismissKeyboard() {
            textView?.resignFirstResponder()
        }

        func applyBold() {
            toggleTrait(.traitBold)
        }

        func applyItalic() {
            toggleTrait(.traitItalic)
        }

        func applyUnderline() {
            guard let textView else { return }
            let range = textView.selectedRange

            if range.length > 0 {
                let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
                let current = mutable.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int
                let newValue = (current ?? 0) == 0 ? NSUnderlineStyle.single.rawValue : 0
                mutable.addAttribute(.underlineStyle, value: newValue, range: range)
                textView.attributedText = mutable
                textView.selectedRange = range
            } else {
                var attrs = textView.typingAttributes
                let current = attrs[.underlineStyle] as? Int ?? 0
                attrs[.underlineStyle] = current == 0 ? NSUnderlineStyle.single.rawValue : 0
                textView.typingAttributes = attrs
            }
            commit(textView)
        }

        func applyBulletList() {
            insertLinePrefix("•  ")
        }

        func applyNumberedList() {
            insertLinePrefix("1. ")
        }

        func applyChecklist() {
            guard let textView else { return }
            let text = textView.attributedText.string as NSString
            let caret = textView.selectedRange.location
            let lineRange = text.lineRange(for: NSRange(location: caret, length: 0))
            let line = text.substring(with: lineRange)

            // Toggle: if already has ☐/☑, flip it; else insert ☐.
            if line.hasPrefix("☐ ") {
                replaceLinePrefix(from: "☐ ", to: "☑ ", in: lineRange)
            } else if line.hasPrefix("☑ ") {
                replaceLinePrefix(from: "☑ ", to: "☐ ", in: lineRange)
            } else {
                insertLinePrefix("☐ ")
            }
        }

        // MARK: Format Helpers

        private func toggleTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
            guard let textView else { return }
            let range = textView.selectedRange

            if range.length > 0 {
                let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
                mutable.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                    let base = (value as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
                    var traits = base.fontDescriptor.symbolicTraits
                    if traits.contains(trait) {
                        traits.remove(trait)
                    } else {
                        traits.insert(trait)
                    }
                    if let descriptor = base.fontDescriptor.withSymbolicTraits(traits) {
                        mutable.addAttribute(.font, value: UIFont(descriptor: descriptor, size: base.pointSize), range: subRange)
                    }
                }
                textView.attributedText = mutable
                textView.selectedRange = range
            } else {
                var attrs = textView.typingAttributes
                let base = (attrs[.font] as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
                var traits = base.fontDescriptor.symbolicTraits
                if traits.contains(trait) {
                    traits.remove(trait)
                } else {
                    traits.insert(trait)
                }
                if let descriptor = base.fontDescriptor.withSymbolicTraits(traits) {
                    attrs[.font] = UIFont(descriptor: descriptor, size: base.pointSize)
                }
                textView.typingAttributes = attrs
            }
            commit(textView)
        }

        func applyTextStyle(_ style: UIFont.TextStyle, bold: Bool) {
            guard let textView else { return }
            let text = textView.attributedText.string as NSString
            let range: NSRange
            if textView.selectedRange.length > 0 {
                range = textView.selectedRange
            } else {
                range = text.lineRange(for: textView.selectedRange)
            }

            var font = UIFont.preferredFont(forTextStyle: style)
            if bold, let descriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) {
                font = UIFont(descriptor: descriptor, size: font.pointSize)
            }

            let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
            mutable.addAttribute(.font, value: font, range: range)
            textView.attributedText = mutable
            textView.selectedRange = range
            commit(textView)
        }

        private func insertLinePrefix(_ prefix: String) {
            guard let textView else { return }
            let full = NSMutableAttributedString(attributedString: textView.attributedText)
            let caret = textView.selectedRange.location
            let text = full.string as NSString
            let lineRange = text.lineRange(for: NSRange(location: caret, length: 0))

            let insert = NSAttributedString(string: prefix, attributes: RichTextEditor.defaultAttributes)
            full.insert(insert, at: lineRange.location)
            textView.attributedText = full
            textView.selectedRange = NSRange(location: caret + (prefix as NSString).length, length: 0)
            commit(textView)
        }

        private func replaceLinePrefix(from old: String, to new: String, in lineRange: NSRange) {
            guard let textView else { return }
            let full = NSMutableAttributedString(attributedString: textView.attributedText)
            let oldLen = (old as NSString).length
            let replaceRange = NSRange(location: lineRange.location, length: oldLen)
            let insert = NSAttributedString(string: new, attributes: RichTextEditor.defaultAttributes)
            full.replaceCharacters(in: replaceRange, with: insert)
            textView.attributedText = full
            textView.selectedRange = NSRange(location: textView.selectedRange.location, length: 0)
            commit(textView)
        }

        private func commit(_ textView: UITextView) {
            parent.attributedText = textView.attributedText
            parent.plainText = textView.text ?? ""
            if let placeholderLabel = textView.viewWithTag(999) as? UILabel {
                placeholderLabel.isHidden = textView.attributedText.length > 0
            }
        }

    }
}

// MARK: - Read-only rich text view

struct AttributedTextView: UIViewRepresentable {
    let attributedText: NSAttributedString

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.isEditable = false
        view.isScrollEnabled = false
        view.isSelectable = true
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.attributedText = attributedText
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if !view.attributedText.isEqual(to: attributedText) {
            view.attributedText = attributedText
        }
    }
}
