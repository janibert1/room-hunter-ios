import SwiftUI
import UIKit

/// A UITextView wrapper (not SwiftUI's TextEditor, which has no way to show
/// per-character-range styling) that's fully editable but starts with the
/// Gemini-personalized spans highlighted with a distinct background, per
/// Jan's explicit spec: "make the entire message editable and gemini's
/// sentences highlighted" -- both at once, not a read-only preview + a
/// separate edit mode. Highlighting is applied once from the server's
/// character offsets when the draft loads; after that, UITextView's normal
/// typing-attribute behavior (new text inherits the attributes already at
/// the cursor) is left alone rather than fought -- editing inside a
/// highlighted sentence keeps it highlighted, editing outside doesn't
/// spuriously highlight new text. Good enough for a personal single-user
/// tool; not attempting to track "logical spans" through arbitrary edits.
struct HighlightedTextEditor: UIViewRepresentable {
    @Binding var text: String
    let highlightSpans: [HighlightSpan]
    /// Bumped by the caller whenever a *new* draft is loaded (not on every
    /// keystroke) so we know to re-apply highlighting instead of clobbering
    /// the user's live edits on every SwiftUI re-render.
    let loadToken: Int

    static let highlightColor = UIColor.systemYellow.withAlphaComponent(0.35)

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = true
        tv.isScrollEnabled = true
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        tv.delegate = context.coordinator
        applyHighlighted(to: tv)
        context.coordinator.lastLoadToken = loadToken
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // Only re-apply full highlighting when a genuinely new draft loaded
        // (loadToken changed) -- otherwise leave the view's live attributed
        // text alone so the user's cursor position / in-progress edit isn't
        // disrupted by SwiftUI re-rendering this wrapper on unrelated state
        // changes elsewhere in the screen.
        if context.coordinator.lastLoadToken != loadToken {
            applyHighlighted(to: uiView)
            context.coordinator.lastLoadToken = loadToken
        } else if uiView.text != text {
            // External programmatic change (rare) -- fall back to plain text,
            // losing highlighting, rather than silently ignoring it.
            uiView.text = text
        }
    }

    private func applyHighlighted(to tv: UITextView) {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [.font: UIFont.preferredFont(forTextStyle: .body)]
        )
        let nsText = text as NSString
        for span in highlightSpans {
            let start = max(0, min(span.start, nsText.length))
            let end = max(start, min(span.end, nsText.length))
            guard end > start else { continue }
            attributed.addAttribute(.backgroundColor, value: Self.highlightColor, range: NSRange(location: start, length: end - start))
        }
        tv.attributedText = attributed
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: HighlightedTextEditor
        var lastLoadToken: Int = -1

        init(_ parent: HighlightedTextEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
    }
}
