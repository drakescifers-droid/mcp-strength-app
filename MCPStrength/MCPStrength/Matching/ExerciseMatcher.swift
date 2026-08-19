//
//  ExerciseMatcher.swift
//  MCPStrength
//

import Foundation

/// Ranks library exercises against a free-text query using three signals, cheapest first:
///
/// 1. **Aliases** — `Exercise.aliases` carries common alternate names (e.g. "pec deck").
///    Matched case-insensitively. Aliases are deliberately NOT unique across exercises; a
///    collision is ambiguity (multiple candidates), not a bug.
/// 2. **Body-part hint** — an optional `BodyPart` supplied by the caller (an AI client or the
///    app UI) that already knows, say, a JM press is triceps work. **The hint RANKS, it never
///    FILTERS**: candidates that `trains(hint)` — primary OR secondary body part — are boosted,
///    but the rest are still returned below them. Filtering on a slightly-wrong hint would hide
///    the right answer — Deadlift's primary is `.back`, and a `.legs` hint only reaches it
///    because `secondaryBodyParts` now carries `.legs` too; an exercise that turns out to have
///    NEITHER as a hint would otherwise vanish from a filtered list.
/// 3. **Spelling similarity** — a token-based Dice coefficient over the exercise name, for
///    word-order and phrasing variants, e.g. "Dumbbell Lateral Raise" -> `Lateral Raise (Dumbbell)`.
///
/// This is a pure function over data: no `ModelContext`, no I/O, no singletons. Pass in-memory
/// `[Exercise]` values and read the result. Nothing is mutated.
struct ExerciseMatcher {

    // MARK: - Public API

    /// Rank every exercise against `query`, best first. Never filters — the body-part hint only
    /// reorders. An empty result means nothing in the library scored above zero, which is an
    /// honest "no match at all".
    ///
    /// Ties are broken deterministically by name (ascending), then by id, so tests are stable.
    static func rank(
        query: String,
        bodyPartHint: BodyPart?,
        in exercises: [Exercise]
    ) -> [Exercise] {
        guard !normalizedTokens(query).isEmpty else { return [] }

        let scored = exercises.map { exercise in
            (exercise, score(query: query, bodyPartHint: bodyPartHint, exercise: exercise))
        }

        return scored
            .filter { $0.1.base > 0 }          // drop exercises with no signal whatsoever
            .sorted {
                if $0.1.total != $1.1.total { return $0.1.total > $1.1.total }
                if $0.0.name != $1.0.name { return $0.0.name < $1.0.name }
                return $0.0.id.uuidString < $1.0.id.uuidString
            }
            .map(\.0)
    }

    /// A convenience for callers that want a bounded, confidence-bounded suggestion list.
    /// Returns at most `limit` exercises whose base signal (alias or spelling, BEFORE the
    /// body-part boost) meets `confidenceThreshold`. An empty array is a legitimate, honest
    /// "no confident match" — better to return nothing than to point at `Leg Press` for `"JM Press"`.
    ///
    /// The threshold is applied to the *base* score so a body-part boost alone can never manufacture
    /// a confident match out of a name that shares nothing with the query.
    static func suggest(
        query: String,
        bodyPartHint: BodyPart?,
        in exercises: [Exercise],
        limit: Int = 5,
        confidenceThreshold: Double = 0.5
    ) -> [Exercise] {
        guard !normalizedTokens(query).isEmpty else { return [] }

        let ranked = rank(query: query, bodyPartHint: bodyPartHint, in: exercises)
        return ranked.prefix(limit).filter { exercise in
            score(query: query, bodyPartHint: bodyPartHint, exercise: exercise).base >= confidenceThreshold
        }
    }

    // MARK: - Scoring

    /// A scored exercise. `base` is the strength of the alias/spelling signal alone; `total`
    /// adds the body-part boost so hinted candidates rank above otherwise-equal ones.
    private struct Score {
        let base: Double
        let total: Double
    }

    // Weights. Deliberately flat and boring — three ranked signals over strings is the whole
    // design. The only judgment calls the docs do not settle:
    //   * An exact name match (1.0) edges out an exact alias match (0.95): if the user typed the
    //     real name, that is the most direct hit.
    //   * The body-part boost (0.3) is large enough to lift a weak-but-plausible hinted candidate
    //     past a stronger-but-wrong non-hinted one (the JM Press / Leg Press case), but small
    //     enough that a confident synonym/spelling match is never overturned by the hint alone.
    private static let nameExactScore: Double = 1.0
    private static let aliasExactScore: Double = 0.95
    private static let aliasContainsScore: Double = 0.7
    private static let bodyPartBoost: Double = 0.3

    private static func score(
        query: String,
        bodyPartHint: BodyPart?,
        exercise: Exercise
    ) -> Score {
        let q = normalize(query)
        let name = normalize(exercise.name)

        let nameExact = (q == name && !q.isEmpty) ? nameExactScore : 0.0

        let aliasScore = bestAliasScore(query: q, aliases: exercise.aliases)

        let spelling = diceCoefficient(queryTokens: normalizedTokens(query),
                                       nameTokens: normalizedTokens(exercise.name))

        let base = max(nameExact, aliasScore, spelling)

        let boost = (bodyPartHint.map(exercise.trains) ?? false) ? bodyPartBoost : 0.0
        return Score(base: base, total: base + boost)
    }

    /// Strongest alias signal for this query. Exact (case-insensitive) alias match wins; a
    /// substring relationship in either direction is a weaker but real hit.
    private static func bestAliasScore(query: String, aliases: [String]) -> Double {
        var best: Double = 0.0
        for alias in aliases {
            let a = normalize(alias)
            guard !a.isEmpty else { continue }
            if query == a {
                return aliasExactScore          // can't beat exact; short-circuit
            } else if query.contains(a) || a.contains(query) {
                best = max(best, aliasContainsScore)
            }
        }
        return best
    }

    // MARK: - String utilities

    /// Lowercases, trims, collapses non-alphanumeric runs to single spaces. "Pec Deck" -> "pec deck";
    /// "Lateral Raise (Dumbbell)" -> "lateral raise dumbbell".
    private static func normalize(_ string: String) -> String {
        let lowered = string.lowercased()
        let collapsed = lowered.unicodeScalars.reduce(into: "") { acc, scalar in
            if CharacterSet.alphanumerics.contains(scalar) {
                acc.unicodeScalars.append(scalar)
            } else {
                if !acc.isEmpty && acc.last != " " { acc.append(" ") }
            }
        }.trimmingCharacters(in: .whitespaces)
        return collapsed
    }

    /// Tokenized, de-duplicated, order-independent view of a string for similarity scoring.
    private static func normalizedTokens(_ string: String) -> Set<String> {
        let tokens = normalize(string)
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        return Set(tokens)
    }

    /// Dice coefficient (Sørensen–Dice) over token sets: `2 * |A ∩ B| / (|A| + |B|)`.
    /// Symmetric and order-independent, which is exactly what makes "Dumbbell Lateral Raise"
    /// match `Lateral Raise (Dumbbell)` at full strength. Returns 0 when both sets are empty.
    private static func diceCoefficient(queryTokens: Set<String>, nameTokens: Set<String>) -> Double {
        let denominator = Double(queryTokens.count + nameTokens.count)
        guard denominator > 0 else { return 0.0 }
        let intersection = Double(queryTokens.intersection(nameTokens).count)
        return (2.0 * intersection) / denominator
    }
}
