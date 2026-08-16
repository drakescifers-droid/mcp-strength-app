//
//  ExpandableNote.swift
//  MCPStrength
//
//  A note that shows a short preview and expands when tapped.
//
//  ## Why notes need this at all
//
//  Notes are a two-way coaching channel (docs/03-mcp-tools.md): the AI writes
//  instructions into them and the user writes back how the session felt. Both
//  sides produce text of unpredictable length — "elbows tucked" and three
//  sentences about sleep are the same field — and an unbounded note pushes the
//  thing you came to the screen for off the bottom.
//
//  ## Two limits, because the two notes are read differently
//
//    * A SESSION note is context you may want to read: "slept badly, gym was
//      packed, rushed the last two sets". 200 characters.
//    * An EXERCISE note is a glance mid-set: "elbows tucked". 100 characters,
//      because it repeats down the screen once per exercise and four of them
//      at session length would bury the sets.
//
//  ## Truncation is at a word boundary
//
//  Cutting mid-word — "felt weak on the last t…" — reads as a rendering fault.
//  Cutting at the last space before the limit reads as deliberate. The
//  difference costs one line of code and is the whole impression the feature
//  makes.
//
//  ## The affordance only appears when there is something to expand
//
//  A permanent "more" on a twelve-character note is exactly the clutter this
//  view exists to prevent, so short notes render as plain text with no
//  interaction at all — nothing to tap, nothing to misread as tappable.
//

import SwiftUI

struct ExpandableNote: View {

    enum Kind {
        /// A note about the whole session or template.
        case session
        /// A note about one exercise. Shorter, because it repeats per exercise.
        case exercise

        var characterLimit: Int {
            switch self {
            case .session:  200
            case .exercise: 100
            }
        }
    }

    let text: String
    var kind: Kind = .exercise
    /// Sticky notes are tinted so the same note looks like the same note
    /// wherever it appears — pinned during a workout, and again in history.
    var tint: Color = Theme.textSecondary

    @State private var isExpanded = false

    private var isTruncatable: Bool {
        text.count > kind.characterLimit
    }

    var body: some View {
        if isTruncatable {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isExpanded ? text : Self.preview(of: text, limit: kind.characterLimit))
                        .font(Typography.secondary)
                        .foregroundStyle(tint)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(isExpanded ? "Less" : "More")
                        .font(Typography.secondary.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            // No affordance, no tap target, no ellipsis. A short note is just
            // text, and dressing it up as interactive would be a lie.
            Text(text)
                .font(Typography.secondary)
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The collapsed form: cut at the last word boundary at or before `limit`.
    ///
    /// Falls back to a hard cut only when a single "word" is longer than the
    /// limit — a pasted URL, say — because in that case there is no boundary to
    /// find and showing nothing would be worse than showing a cut.
    static func preview(of text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let cut = text.prefix(limit)
        if let lastSpace = cut.lastIndex(of: " ") {
            let word = cut[..<lastSpace]
            // Guard against a limit that lands just after the first space,
            // which would leave a one-word preview of a long note.
            if word.count >= limit / 2 {
                return word.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
            }
        }
        return cut.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Spacing.comfortable) {
        ExpandableNote(text: "Elbows tucked", kind: .exercise)
        ExpandableNote(
            text: String(repeating: "Felt heavy today and the bar drifted forward. ", count: 4),
            kind: .exercise,
            tint: Theme.warmup
        )
        ExpandableNote(
            text: String(repeating: "Slept about four hours and the gym was packed. ", count: 6),
            kind: .session
        )
    }
    .padding()
    .background(Theme.surface)
    .preferredColorScheme(.dark)
}
