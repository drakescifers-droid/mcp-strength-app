//
//  MCPStrengthUITests.swift
//  MCPStrengthUITests
//
//  Created by Drake Scifers on 8/14/26.
//

import XCTest

final class MCPStrengthUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}

// MARK: - Warm-up ramp, driven and photographed
//
// A NAVIGATION HARNESS, not an assertion suite. `Add Warm-up Sets` is covered
// by unit tests already; what no test can judge is whether the generated ramp
// READS correctly in the set list, and whether a second tap visibly REPLACES
// the warm-ups rather than piling more on (docs/04-status.md, item 1).
//
// This exists because the mouse cannot reach the simulator from here: taps
// land on the Simulator window and never become touches. XCUITest drives the
// screen from inside, so the only thing left for a human is LOOKING at the
// attachments.
//
// Fixtures are deliberately OFF. `-uiPreviewFixtures` seeds a demo workout
// that already contains warm-up sets, and this project has already built the
// ramp twice because an edited ramp was mistaken for a generated one. Every
// warm-up in these screenshots was produced by the button.

final class WarmupRampWalkthroughTests: XCTestCase {

    @MainActor
    func testWalkAddWarmupSetsAndPhotographIt() throws {
        continueAfterFailure = false

        let app = XCUIApplication()
        app.launchArguments = ["-uiPreview", "1", "-uiPreviewTab", "start"]
        app.launch()

        // 1. An empty workout.
        let start = app.buttons["Start an Empty Workout"]
        XCTAssertTrue(start.waitForExistence(timeout: 20), tree(app))
        start.tap()

        // 2. One barbell exercise. The seed carries no barType, so there is no
        //    bar floor here and the ramp is the plain percentage one.
        let addExercises = app.buttons["Add Exercises"]
        XCTAssertTrue(addExercises.waitForExistence(timeout: 10), tree(app))
        addExercises.tap()

        let bench = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Bench Press (Barbell)")
        ).firstMatch
        XCTAssertTrue(bench.waitForExistence(timeout: 10), tree(app))
        bench.tap()

        // 3. A working weight to ramp up to. 90 lb is the weight the reference
        //    app's ramp was MEASURED from: 45x5, 55x5, 70x3.
        try type("90", intoTextFieldAt: 0, of: app)
        try type("5", intoTextFieldAt: 1, of: app)
        attach(named: "01-working-set-90x5", app)

        // 4. First tap.
        try chooseWarmupSets(in: app)
        attach(named: "02-after-first-tap", app)

        // 5. Second tap, same working weight. The ramp must REPLACE, not append:
        //    three warm-ups here, not six.
        try chooseWarmupSets(in: app)
        attach(named: "03-after-second-tap-same-weight", app)

        // 6. Retype the working weight and tap again. This is the case the
        //    replace behaviour exists for — somebody who typed the weight after
        //    generating the ramp. 135 lb should give 70x5, 80x5, 100x3.
        //
        //    The working set is addressed as the LAST row, not index 0: the
        //    ramp now occupies the first three rows, which is the whole point.
        try typeIntoWorkingWeight("135", of: app)
        try chooseWarmupSets(in: app)
        attach(named: "04-after-retyping-135", app)
    }

    /// The Previous column against history that CONTAINS warm-ups.
    ///
    /// Fixtures are ON here, and that is the point rather than a shortcut:
    /// `UIPreviewFixtures` installs a COMPLETED Bench Press workout whose first
    /// two sets are warm-ups at 95x10 and 135x5, with working sets at 185.
    /// Nothing else in the app can produce that history without logging and
    /// finishing a whole workout first.
    ///
    /// The ramp generated here is still generated — it is a NEW workout, and
    /// the fixture's own warm-ups are history rather than rows on this screen.
    /// Worth saying because reading a fixture's ramp as the generator's output
    /// is exactly the mistake that built this feature twice (docs/04-status.md).
    ///
    /// Expected, with a 200 lb working set (ramp 100 / 120 / 150):
    ///
    ///     W  100   <- 95 lb x 10 (W)     last time's first warm-up
    ///     W  120   <- 135 lb x 5 (W)     last time's second warm-up
    ///     W  150   <- "—"                there was no third warm-up
    ///     1  200   <- 185 lb x 8         last time's first WORKING set
    @MainActor
    func testWarmupRowsReadLastTimesWarmups() throws {
        continueAfterFailure = false

        let app = XCUIApplication()
        app.launchArguments = ["-uiPreview", "1", "-uiPreviewFixtures", "1", "-uiPreviewTab", "start"]
        app.launch()

        let start = app.buttons["Start an Empty Workout"]
        XCTAssertTrue(start.waitForExistence(timeout: 20), tree(app))
        start.tap()

        let addExercises = app.buttons["Add Exercises"]
        XCTAssertTrue(addExercises.waitForExistence(timeout: 10), tree(app))
        addExercises.tap()

        let bench = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Bench Press (Barbell)")
        ).firstMatch
        XCTAssertTrue(bench.waitForExistence(timeout: 10), tree(app))
        bench.tap()

        try type("200", intoTextFieldAt: 0, of: app)
        try type("5", intoTextFieldAt: 1, of: app)
        attach(named: "05-working-set-200x5-with-warmup-history", app)

        try chooseWarmupSets(in: app)
        attach(named: "06-previous-column-against-warmup-history", app)
    }

    // MARK: - Helpers

    /// The `⋯` menu carries an accessibility label; the item is plain text.
    @MainActor
    private func chooseWarmupSets(in app: XCUIApplication) throws {
        let menu = app.buttons["Exercise options"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10), tree(app))
        menu.tap()

        let item = app.buttons["Add Warm-up Sets"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10), tree(app))
        item.tap()
    }

    /// Set rows carry unlabelled TextFields, so they are addressed by order:
    /// each row contributes weight then reps. Deliberately index-based rather
    /// than adding accessibility identifiers to the app for a harness's
    /// convenience.
    @MainActor
    private func type(
        _ text: String,
        intoTextFieldAt index: Int,
        of app: XCUIApplication,
        clearFirst: Bool = false
    ) throws {
        let field = app.textFields.element(boundBy: index)
        XCTAssertTrue(field.waitForExistence(timeout: 10), tree(app))
        try focus(field, of: app)
        if clearFirst, let existing = field.value as? String, !existing.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
            // Asserted, not assumed. A silent failure to clear is what turned
            // 135 into 13590 last run, and the screenshot still looked sane.
            XCTAssertEqual(field.value as? String ?? "", "", tree(app))
        }
        field.typeText(text)
    }

    /// The working set's weight field, wherever the ramp has pushed it.
    ///
    /// Two fields per row (weight, reps) and the working set is last, so the
    /// weight field is the second-to-last. An absolute index would silently
    /// address a warm-up the moment one exists — which is exactly how the
    /// first run of this harness failed.
    @MainActor
    private func typeIntoWorkingWeight(_ text: String, of app: XCUIApplication) throws {
        let count = app.textFields.count
        XCTAssertGreaterThanOrEqual(count, 2, tree(app))
        try type(text, intoTextFieldAt: count - 2, of: app, clearFirst: true)
    }

    /// Tap until the field actually holds keyboard focus, with the caret at the
    /// END of the existing text.
    ///
    /// Two things learned from earlier runs of this harness, both of which
    /// produced a plausible-looking screenshot of the wrong thing:
    ///
    ///   * `tap()` returning is not the same as the field being focused. Run
    ///     one typed into a field that had never taken focus and failed with
    ///     "Neither element nor any descendant has keyboard focus".
    ///   * Tapping the ELEMENT puts the caret where the tap landed, which for a
    ///     right-aligned entry chip is before the text. Run two sent backspaces
    ///     that deleted nothing and then typed 135 in front of 90, so the ramp
    ///     was generated from 13590 lb. The numbers were all self-consistent
    ///     and completely wrong — the same trap as reading a hand-edited ramp
    ///     as a generated one (docs/04-status.md).
    @MainActor
    private func focus(_ field: XCUIElement, of app: XCUIApplication) throws {
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        let rightEdge = field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        for _ in 0..<3 {
            rightEdge.tap()
            let check = XCTNSPredicateExpectation(predicate: focused, object: field)
            if XCTWaiter().wait(for: [check], timeout: 3) == .completed { return }
        }
        XCTFail("Field never took keyboard focus.\n" + tree(app))
    }

    @MainActor
    private func attach(named name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Printed into a failure so a missing element is diagnosable without
    /// another build.
    @MainActor
    private func tree(_ app: XCUIApplication) -> String {
        app.debugDescription
    }
}

// MARK: - Swipe to delete a set

/// A camera, like `WarmupRampWalkthroughTests`. It asserts the one thing a
/// screenshot cannot show — that the set count actually dropped — and
/// photographs everything else so a human can judge whether the affordance
/// looks right.
///
/// Worth driving rather than reasoning about, because the gesture is
/// hand-built. `.swipeActions` only exists on `List` rows and this app has no
/// `List`, so `SetRow` implements the drag itself, and the risk is not that
/// deletion fails — it is that the row fights the ScrollView and the screen
/// stops scrolling where the sets are.
final class SwipeToDeleteSetWalkthroughTests: XCTestCase {

    @MainActor
    func testSwipeASetAwayAndPhotographIt() throws {
        continueAfterFailure = false

        let app = XCUIApplication()
        app.launchArguments = ["-uiPreview", "1", "-uiPreviewTab", "start"]
        app.launch()

        let start = app.buttons["Start an Empty Workout"]
        XCTAssertTrue(start.waitForExistence(timeout: 20), app.debugDescription)
        start.tap()

        let addExercises = app.buttons["Add Exercises"]
        XCTAssertTrue(addExercises.waitForExistence(timeout: 10), app.debugDescription)
        addExercises.tap()

        let bench = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Bench Press (Barbell)")
        ).firstMatch
        XCTAssertTrue(bench.waitForExistence(timeout: 10), app.debugDescription)
        bench.tap()

        // Three sets, so there is something to delete from the MIDDLE — the
        // case that proves the survivors renumber rather than leave a hole.
        let addSet = app.buttons.containing(
            NSPredicate(format: "label BEGINSWITH %@", "+ Add Set")
        ).firstMatch
        XCTAssertTrue(addSet.waitForExistence(timeout: 10), app.debugDescription)
        addSet.tap()
        addSet.tap()

        let before = app.textFields.count
        shot("01-three-sets-before", self)

        // Half-open, to photograph the affordance mid-reveal rather than only
        // its end state. `press(forDuration:thenDragTo:)` keeps the drag slow
        // enough to be a drag rather than a flick.
        let firstField = app.textFields.element(boundBy: 0)
        XCTAssertTrue(firstField.exists, app.debugDescription)

        let rowStart = firstField.coordinate(withNormalizedOffset: CGVector(dx: -0.6, dy: 0.5))
        let rowEnd = rowStart.withOffset(CGVector(dx: -110, dy: 0))
        rowStart.press(forDuration: 0.15, thenDragTo: rowEnd)
        shot("02-swiped-open", self)

        // The delete button should now be reachable.
        let deleteButton = app.buttons["Delete"].firstMatch
        XCTAssertTrue(
            deleteButton.waitForExistence(timeout: 5),
            "No Delete button after swiping left.\n" + app.debugDescription
        )
        deleteButton.tap()
        shot("03-after-delete", self)

        // The assertion a picture cannot make. Two text fields per set (weight
        // and reps), so one fewer set is two fewer fields.
        XCTAssertLessThan(
            app.textFields.count, before,
            "Set count did not drop after tapping Delete."
        )
    }

    @MainActor
    private func shot(_ name: String, _ testCase: XCTestCase) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }
}

// MARK: - Dragging a template between folders

/// The interaction `docs/04-status.md` claimed was finished and which did not
/// work on a device.
///
/// The cause was that `TemplateCard`'s root was a `Button`, which consumes the
/// long press `.draggable` needs to begin a drag — so the card was draggable in
/// the source and immovable in the hand. Nothing threw and nothing logged; the
/// drop handlers simply never ran.
///
/// This test exists because that class of bug is invisible to every other kind
/// of check. The move rule (`ListOrdering`) is already unit-tested and was
/// always correct. What was broken was whether a finger could reach it.
final class TemplateFolderDragTests: XCTestCase {

    @MainActor
    func testDragATemplateIntoAnotherFolder() throws {
        continueAfterFailure = false

        let app = XCUIApplication()
        app.launchArguments = ["-uiPreview", "1", "-uiPreviewFixtures", "1", "-uiPreviewTab", "start"]
        app.launch()

        // Fixture layout: "Preview Push" has two templates, "Preview Pull" has
        // one. Counts are in the folder headers, which is what makes a move
        // between them observable without reading the store.
        let pushHeader = app.staticTexts["Preview Push (2)"]
        XCTAssertTrue(
            pushHeader.waitForExistence(timeout: 20),
            "Template fixtures missing.\n" + app.debugDescription
        )
        XCTAssertTrue(app.staticTexts["Preview Pull (1)"].exists, app.debugDescription)

        let card = app.staticTexts["Preview Shoulder Day"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), app.debugDescription)

        let target = app.staticTexts["Preview Back Day"].firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10), app.debugDescription)

        shot("01-before-drag", self)

        // A long press to lift, then a slow drag — a flick is not a drag and
        // will not start one.
        card.press(forDuration: 1.0, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.8)
        shot("02-after-drop", self)

        // The assertion. Counts move in opposite directions, which a reorder
        // WITHIN a folder could not produce.
        XCTAssertTrue(
            app.staticTexts["Preview Push (1)"].waitForExistence(timeout: 5),
            "Source folder count did not drop — the drag never moved the template.\n"
                + app.debugDescription
        )
        XCTAssertTrue(
            app.staticTexts["Preview Pull (2)"].exists,
            "Destination folder count did not rise.\n" + app.debugDescription
        )
    }

    @MainActor
    private func shot(_ name: String, _ testCase: XCTestCase) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }
}

// MARK: - Control: can XCUITest start a SwiftUI drag at all?

/// Not a test of the app. A test of the HARNESS.
///
/// `TemplateFolderDragTests` failed, and that has two possible meanings which
/// call for opposite responses: either the template fix does not work, or
/// XCUITest cannot initiate a SwiftUI `.draggable` session and the test could
/// never have passed either way.
///
/// This distinguishes them. Exercise reordering on the workout screen uses the
/// SAME `.draggable` / `.dropDestination` API and is known to work by hand —
/// Drake reorders exercises, and the only complaint about it (#6) is that
/// there is no live feedback WHILE dragging, which means the drag itself
/// starts. So if the same synthesized gesture fails to move an exercise, the
/// gesture is the thing that does not work, not the code under it.
///
/// A failure here is therefore GOOD NEWS about the app and bad news about the
/// tooling: it means drag features on this project cannot be verified by
/// XCUITest and need a thumb, which is worth knowing before writing more tests
/// that cannot pass.
final class CanXCUITestStartASwiftUIDragTests: XCTestCase {

    @MainActor
    func testReorderingAnExerciseByDragMovesIt() throws {
        continueAfterFailure = false

        let app = XCUIApplication()
        app.launchArguments = ["-uiPreview", "1", "-uiPreviewTab", "start"]
        app.launch()

        let start = app.buttons["Start an Empty Workout"]
        XCTAssertTrue(start.waitForExistence(timeout: 20), app.debugDescription)
        start.tap()

        func addExercise(_ name: String) {
            let add = app.buttons["Add Exercises"]
            XCTAssertTrue(add.waitForExistence(timeout: 10), app.debugDescription)
            add.tap()
            let row = app.buttons.containing(
                NSPredicate(format: "label CONTAINS[c] %@", name)
            ).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
            row.tap()
        }

        addExercise("Bench Press (Barbell)")
        addExercise("Pull Up")

        let first = app.staticTexts["Bench Press (Barbell)"].firstMatch
        let second = app.staticTexts["Pull Up"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(second.waitForExistence(timeout: 10), app.debugDescription)

        let firstWasAbove = first.frame.minY < second.frame.minY
        XCTAssertTrue(firstWasAbove, "precondition: Bench Press starts above Pull Up")

        // The exercise title is the drag handle.
        first.press(forDuration: 1.0, thenDragTo: second, withVelocity: .slow, thenHoldForDuration: 0.8)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "control-after-exercise-drag"
        attachment.lifetime = .keepAlways
        add(attachment)

        let firstIsStillAbove = app.staticTexts["Bench Press (Barbell)"].firstMatch.frame.minY
            < app.staticTexts["Pull Up"].firstMatch.frame.minY
        XCTAssertFalse(
            firstIsStillAbove,
            "The KNOWN-WORKING exercise drag also did not move. XCUITest cannot start a SwiftUI drag on this setup, so TemplateFolderDragTests proves nothing about the template fix."
        )
    }
}
