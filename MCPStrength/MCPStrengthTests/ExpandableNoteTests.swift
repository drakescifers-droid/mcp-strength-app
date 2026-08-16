//
//  ExpandableNoteTests.swift
//  MCPStrengthTests
//
//  Covers the collapsed preview of a note.
//
//  The view itself cannot be tested here — whether it looks cramped is a
//  question for the simulator. What IS testable is the string rule, and it is
//  the part with a wrong answer: cutting mid-word reads as a rendering fault,
//  and a preview longer than the limit defeats the point of having one.
//

import Testing
import Foundation
@testable import MCPStrength

struct ExpandableNoteTests {

    // MARK: - Short notes are left alone

    @Test func aShortNoteIsReturnedUntouched() {
        // No ellipsis, no trimming, nothing. A short note is just text — the
        // view does not even make it tappable.
        #expect(ExpandableNote.preview(of: "Elbows tucked", limit: 100) == "Elbows tucked")
    }

    @Test func aNoteExactlyAtTheLimitIsNotTruncated() {
        // Off-by-one guard: `>` not `>=`. Truncating a note that fits would add
        // an ellipsis and a More button for nothing.
        let text = String(repeating: "a", count: 100)
        #expect(ExpandableNote.preview(of: text, limit: 100) == text)
    }

    @Test func emptyStaysEmpty() {
        #expect(ExpandableNote.preview(of: "", limit: 100).isEmpty)
    }

    // MARK: - The word boundary

    @Test func truncationCutsAtAWordBoundary() {
        let text = "Slept about four hours and the gym was absolutely packed today"
        let preview = ExpandableNote.preview(of: text, limit: 30)

        #expect(preview.hasSuffix("…"))
        let body = String(preview.dropLast())
        #expect(text.hasPrefix(body), "the preview is not a prefix of the note")
        // The cut landed on a boundary: the character after it is a space, or
        // the body is a whole-word prefix.
        let next = text[text.index(text.startIndex, offsetBy: body.count)]
        #expect(next == " ", "cut mid-word — got \\(preview)")
    }

    @Test func thePreviewNeverExceedsTheLimit() {
        // Including the ellipsis. A preview that overruns is not a preview.
        let text = String(repeating: "word ", count: 200)
        for limit in [10, 50, 100, 200] {
            let preview = ExpandableNote.preview(of: text, limit: limit)
            #expect(preview.count <= limit + 1, "limit \\(limit) produced \\(preview.count) chars")
        }
    }

    @Test func aSingleLongWordIsCutRatherThanShownWhole() {
        // A pasted URL has no boundary to find. Showing it whole would defeat
        // the limit, and showing nothing would be worse than a hard cut.
        let text = String(repeating: "x", count: 300)
        let preview = ExpandableNote.preview(of: text, limit: 100)
        #expect(preview.count <= 101)
        #expect(preview.hasSuffix("…"))
    }

    @Test func aLongNoteStartingWithAShortWordIsNotCutToOneWord() {
        // The guard against a limit landing just after the first space: "I …"
        // is technically a word boundary and useless as a preview.
        let text = "I " + String(repeating: "y", count: 300)
        let preview = ExpandableNote.preview(of: text, limit: 100)
        #expect(preview.count > 50, "collapsed to a near-empty preview: \\(preview)")
    }

    @Test func trailingWhitespaceIsNotLeftBeforeTheEllipsis() {
        let text = "Felt strong    " + String(repeating: "z", count: 200)
        let preview = ExpandableNote.preview(of: text, limit: 20)
        #expect(!preview.contains(" …"), "space left before the ellipsis: \\(preview)")
    }

    // MARK: - The two limits

    @Test func aSessionNoteGetsMoreRoomThanAnExerciseNote() {
        // The whole reason there are two kinds. A session note is context worth
        // reading; an exercise note repeats once per exercise down the screen.
        #expect(ExpandableNote.Kind.session.characterLimit == 200)
        #expect(ExpandableNote.Kind.exercise.characterLimit == 100)
        #expect(
            ExpandableNote.Kind.session.characterLimit
                > ExpandableNote.Kind.exercise.characterLimit
        )
    }

    @Test func aNoteBetweenTheTwoLimitsTruncatesOnlyAsAnExerciseNote() {
        // The case that proves the two limits actually do different things.
        let text = String(repeating: "note ", count: 30)  // 150 chars
        #expect(text.count > ExpandableNote.Kind.exercise.characterLimit)
        #expect(text.count < ExpandableNote.Kind.session.characterLimit)

        let asExercise = ExpandableNote.preview(
            of: text, limit: ExpandableNote.Kind.exercise.characterLimit
        )
        let asSession = ExpandableNote.preview(
            of: text, limit: ExpandableNote.Kind.session.characterLimit
        )
        #expect(asExercise.hasSuffix("…"))
        #expect(asSession == text)
    }
}
