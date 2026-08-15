//
//  MeasurementTypeDetailScreen.swift
//  MCPStrength
//
//  Per-type detail: the full history of entries for one type, newest first, with value, unit and
//  date. The main measurements screen shows only the latest value per type; this screen is where
//  the rest of the time series lives. Supports deleting an entry (swipe or the trash button);
//  editing is out of scope — delete and re-add.
//

import SwiftUI
import SwiftData

struct MeasurementTypeDetailScreen: View {
    @Environment(\.modelContext) private var context

    let type: MeasurementType

    @Query private var allEntries: [MeasurementEntry]

    private var entries: [MeasurementEntry] {
        allEntries
            .filter { $0.type?.id == type.id }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if entries.isEmpty {
                    Text("No measurements recorded")
                        .font(Typography.body)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.vertical, Spacing.spacious)
                } else {
                    ForEach(entries, id: \.id) { entry in
                        entryRow(entry)
                        rowDivider
                    }
                }
            }
            .padding(.vertical, Spacing.compact)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
        .navigationTitle(type.name)
        .navigationBarTitleDisplayMode(.large)
    }

    private func entryRow(_ entry: MeasurementEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(formatted(entry.value)) \(entry.unit)")
                    .font(Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(entry.recordedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(Typography.secondary)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            Button(role: .destructive) {
                delete(entry)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.destructive)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.vertical, Spacing.comfortable)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Theme.fieldFill)
            .frame(height: 1)
            .padding(.leading, Spacing.screenMargin)
    }

    private func delete(_ entry: MeasurementEntry) {
        context.delete(entry)
        try? context.save()
    }

    private func formatted(_ value: Double) -> String {
        let s = String(format: "%.2f", value)
        if s.contains(".") {
            return s.replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
        }
        return s
    }
}
