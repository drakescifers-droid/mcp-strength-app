//
//  RecordMeasurementSheet.swift
//  MCPStrength
//
//  A small sheet to record a single manual measurement. A numeric field, the type's unit shown
//  but not editable, and a date defaulting to now. Saving creates a `MeasurementEntry` with
//  `source = .manual`. Editing existing entries is deliberately out of scope — delete and re-add.
//

import SwiftUI
import SwiftData

struct RecordMeasurementSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let type: MeasurementType

    @State private var valueText: String = ""
    @State private var date: Date = Date()

    private var unit: String {
        MeasurementSeedImporter.defaultUnit(for: type.id) ?? ""
    }

    private var parsedValue: Double? {
        let trimmed = valueText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    private var canSave: Bool { parsedValue != nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.comfortable) {
                Spacer()

                HStack(spacing: Spacing.compact) {
                    TextField("Value", text: $valueText)
                        .font(Typography.chipValue)
                        .foregroundStyle(Theme.textPrimary)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 160)
                        .padding(.horizontal, Spacing.comfortable)
                        .padding(.vertical, Spacing.compact)
                        .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.chip))

                    Text(unit)
                        .font(Typography.body)
                        .foregroundStyle(Theme.textSecondary)
                }

                DatePicker("Date", selection: $date, displayedComponents: [.date])
                    .font(Typography.body)
                    .foregroundStyle(Theme.textPrimary)
                    .labelsHidden()
                    .padding(.horizontal, Spacing.comfortable)
                    .padding(.vertical, Spacing.compact)
                    .background(Theme.fieldFill, in: .rect(cornerRadius: Radius.chip))

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surface)
            .navigationTitle(type.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        guard let value = parsedValue else { return }
        let entry = MeasurementEntry(
            value: value,
            unit: unit,
            recordedAt: date,
            source: .manual,
            type: type
        )
        context.insert(entry)
        try? context.save()
        dismiss()
    }
}
