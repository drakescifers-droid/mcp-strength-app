//
//  MeasurementsScreen.swift
//  MCPStrength
//
//  The body-measurements screen. Two sections — CORE and BODY PART — one row per seeded type.
//  Each row shows the type name on the left and, on the right, the LATEST recorded value with
//  its unit (or nothing if that type has never been recorded), plus a compact accent-tinted +
//  button to record a new value. Tapping a row pushes the per-type detail (full history,
//  newest-first). Tapping + presents a small sheet: a numeric field, the type's unit shown but
//  not editable, and a date defaulting to now.
//
//  The underlying data is a time series; this list is a summary of it. The summary computation
//  is the pure `MeasurementLatest.latestByTypeID` — not a sort in a view body — so it is tested
//  independently in `MeasurementLatestTests`.
//

import SwiftUI
import SwiftData

// MARK: - MeasurementGroup display

private extension MeasurementGroup {
    /// Uppercased section header for the two groups, matching the reference ("CORE", "BODY PART").
    var sectionTitle: String {
        switch self {
        case .core:     "CORE"
        case .bodyPart:  "BODY PART"
        }
    }
}

// MARK: - MeasurementsScreen

struct MeasurementsScreen: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<MeasurementType> { $0.deletedAt == nil })
    private var types: [MeasurementType]
    @Query(filter: #Predicate<MeasurementEntry> { $0.deletedAt == nil })
    private var entries: [MeasurementEntry]

    @State private var recordingType: MeasurementType?

    private var latestByType: [UUID: MeasurementEntry] {
        MeasurementLatest.latestByTypeID(entries)
    }

    private var coreTypes: [MeasurementType] {
        types.filter { $0.group == .core }.sorted(by: Self.bySortOrder)
    }

    private var bodyPartTypes: [MeasurementType] {
        types.filter { $0.group == .bodyPart }.sorted(by: Self.bySortOrder)
    }

    /// Seeded anatomical/priority order; name is only a tiebreak so a missing or
    /// colliding sortOrder does not scramble the list into hash order.
    private static func bySortOrder(_ lhs: MeasurementType, _ rhs: MeasurementType) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return lhs.name < rhs.name
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                section(for: coreTypes, group: .core)
                section(for: bodyPartTypes, group: .bodyPart)
            }
            .padding(.vertical, Spacing.compact)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
        .navigationTitle("Measurements")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $recordingType) { type in
            RecordMeasurementSheet(type: type)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func section(for groupTypes: [MeasurementType], group: MeasurementGroup) -> some View {
        if !groupTypes.isEmpty {
            sectionHeader(group.sectionTitle)
            ForEach(groupTypes, id: \.id) { type in
                MeasurementTypeRow(
                    type: type,
                    latest: latestByType[type.id],
                    onRecord: { recordingType = type }
                )
                rowDivider
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Typography.secondary.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.comfortable)
            .padding(.bottom, Spacing.compact)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Theme.fieldFill)
            .frame(height: 1)
            .padding(.leading, Spacing.screenMargin)
    }
}

// MARK: - MeasurementTypeRow

/// A single type row: name on the left, latest value + unit on the right (or nothing if never
/// recorded), then a compact accent-tinted + button to record a new value. The name+latest area
/// is a NavigationLink to the per-type detail; the + button is a sibling outside the link so the
/// two tap targets stay distinct.
private struct MeasurementTypeRow: View {
    let type: MeasurementType
    let latest: MeasurementEntry?
    let onRecord: () -> Void

    var body: some View {
        HStack(spacing: Spacing.comfortable) {
            NavigationLink {
                MeasurementTypeDetailScreen(type: type)
            } label: {
                HStack(spacing: Spacing.comfortable) {
                    Text(type.name)
                        .font(Typography.body)
                        .foregroundStyle(Theme.textPrimary)

                    Spacer(minLength: 0)

                    if let latest {
                        Text("\(formatted(latest.value)) \(latest.unit)")
                            .font(Typography.body)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)

            plusButton
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.vertical, Spacing.comfortable)
    }

    /// Two decimals, trimming trailing zeros so "186.95" stays "186.95" and "43.0" reads "43".
    private func formatted(_ value: Double) -> String {
        let s = String(format: "%.2f", value)
        if s.contains(".") {
            return s.replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
        }
        return s
    }

    private var plusButton: some View {
        Button(action: onRecord) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .background(Theme.accentFill, in: .circle)
        }
        .buttonStyle(.plain)
    }
}
