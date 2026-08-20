//
//  NumberKeypad.swift
//  MCPStrength
//
//  The custom number keypad that replaces the system keyboard on every
//  numeric entry field. Visual work — the rules live in `NumberKeypadEditing`.
//
//  Layout matches the reference: a 3-column digit grid, extra key / 0 /
//  backspace along the bottom, and a right column of dismiss, − / +, Next.
//  SwiftUI `TextField` has no `inputView`, so this is a pinned view driven by
//  tap-targets, not a `ToolbarItemGroup(placement: .keyboard)` sitting above
//  the system pad.
//

import SwiftUI

// MARK: - Session

/// Focus + buffer for the keypad currently on screen. One per logging screen,
/// published through the environment so `SetRow` and the rest divider can
/// highlight without the screen threading a binding through every row.
@MainActor
@Observable
final class NumberKeypadSession {
    var address: NumberKeypadAddress?
    private(set) var editing: NumberKeypadEditing?

    var isPresented: Bool { address != nil }

    func focus(_ address: NumberKeypadAddress, kind: NumberKeypadKind, display: String) {
        self.address = address
        self.editing = NumberKeypadEditing.focusing(kind: kind, display: display)
    }

    func apply(_ input: NumberKeypadInput) {
        guard var editing else { return }
        editing.apply(input)
        self.editing = editing
    }

    func dismiss() {
        address = nil
        editing = nil
    }
}

// MARK: - Keypad view

struct NumberKeypad: View {
    let kind: NumberKeypadKind
    var onInput: (NumberKeypadInput) -> Void
    var onNext: () -> Void
    var onDismiss: () -> Void

    private let extra: NumberKeypadInput?

    init(
        kind: NumberKeypadKind,
        onInput: @escaping (NumberKeypadInput) -> Void,
        onNext: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.kind = kind
        self.onInput = onInput
        self.onNext = onNext
        self.onDismiss = onDismiss
        self.extra = NumberKeypadEditing.focusing(kind: kind, display: "").extraKey
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.compact) {
            VStack(spacing: Spacing.compact) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: Spacing.compact) {
                        ForEach(1...3, id: \.self) { col in
                            digitKey(row * 3 + col)
                        }
                    }
                }
                HStack(spacing: Spacing.compact) {
                    extraKey
                    digitKey(0)
                    key(identifier: "keypad-delete", action: { onInput(.backspace) }) {
                        Image(systemName: "delete.left")
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .accessibilityLabel("Delete")
                }
            }

            VStack(spacing: Spacing.compact) {
                key(identifier: "keypad-dismiss", action: onDismiss) {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 18, weight: .semibold))
                }
                .accessibilityLabel("Hide Keyboard")

                plusMinusKey

                Button(action: onNext) {
                    Text("Next")
                        .font(Typography.button)
                        // `onSolid`, not `textPrimary`: this label sits on a
                        // saturated accent fill, and on a light palette the two
                        // want opposite values.
                        .foregroundStyle(Theme.onSolid)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.accent, in: .rect(cornerRadius: Radius.chip))
                }
                .buttonStyle(.plain)
                .frame(height: Self.keyHeight * 2 + Spacing.compact)
                .accessibilityIdentifier("keypad-next")
            }
            .frame(width: 88)
        }
        // `safeAreaInset` will otherwise offer the keypad the whole leftover
        // screen, and Next's old `maxHeight: .infinity` took it — which is why
        // the pad painted over the workout. Size to the keys, nothing more.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Spacing.compact)
        .padding(.top, Spacing.compact)
        .padding(.bottom, Spacing.comfortable)
        .background(Theme.fieldFill)
    }

    // MARK: - Keys

    private func digitKey(_ digit: Int) -> some View {
        key(identifier: "keypad-\(digit)", action: { onInput(.digit(digit)) }) {
            Text("\(digit)")
                .font(Typography.title)
        }
        .accessibilityLabel("\(digit)")
    }

    @ViewBuilder
    private var extraKey: some View {
        if let extra {
            switch extra {
            case .decimalPoint:
                key(identifier: "keypad-decimal", action: { onInput(.decimalPoint) }) {
                    Text(".")
                        .font(Typography.title)
                }
                .accessibilityLabel("Decimal")
            case .hyphen:
                key(identifier: "keypad-hyphen", action: { onInput(.hyphen) }) {
                    Text("-")
                        .font(Typography.title)
                }
                .accessibilityLabel("Range")
            default:
                blankKey
            }
        } else {
            blankKey
        }
    }

    private var plusMinusKey: some View {
        HStack(spacing: 1) {
            Button {
                onInput(.minus)
            } label: {
                Text("−")
                    .font(Typography.title)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("keypad-minus")
            .accessibilityLabel("Decrement")

            Button {
                onInput(.plus)
            } label: {
                Text("+")
                    .font(Typography.title)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("keypad-plus")
            .accessibilityLabel("Increment")
        }
        .background(Theme.keypadKey, in: .rect(cornerRadius: Radius.chip))
        .frame(height: Self.keyHeight)
    }

    private var blankKey: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: Self.keyHeight)
    }

    private func key<Label: View>(
        identifier: String,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: Self.keyHeight)
                .background(Theme.keypadKey, in: .rect(cornerRadius: Radius.chip))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private static let keyHeight: CGFloat = 48
}
