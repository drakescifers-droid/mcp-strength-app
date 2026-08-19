// Port of MCPStrength/Matching/ExerciseMatcher.swift.
// Three ranked signals, cheapest first — docs/01-data-model.md § Matching,
// docs/03-mcp-tools.md open question 3. Keep this file a pure function over
// data so the Swift tests can have a twin here.

import type { BodyPart, LibraryExercise } from "./types.ts";

export type Score = {
  base: number;
  total: number;
};

const nameExactScore = 1.0;
const aliasExactScore = 0.95;
const aliasContainsScore = 0.7;
const bodyPartBoost = 0.3;

export function rank(
  query: string,
  bodyPartHint: BodyPart | null,
  exercises: LibraryExercise[],
): LibraryExercise[] {
  if (normalizedTokens(query).size === 0) return [];

  const scored = exercises.map((exercise) => ({
    exercise,
    score: score(query, bodyPartHint, exercise),
  }));

  return scored
    .filter((row) => row.score.base > 0)
    .sort((a, b) => {
      if (a.score.total !== b.score.total) return b.score.total - a.score.total;
      if (a.exercise.name !== b.exercise.name) {
        return a.exercise.name < b.exercise.name ? -1 : 1;
      }
      return a.exercise.id < b.exercise.id ? -1 : 1;
    })
    .map((row) => row.exercise);
}

export function suggest(
  query: string,
  bodyPartHint: BodyPart | null,
  exercises: LibraryExercise[],
  limit = 5,
  confidenceThreshold = 0.5,
): LibraryExercise[] {
  if (normalizedTokens(query).size === 0) return [];

  const ranked = rank(query, bodyPartHint, exercises);
  return ranked
    .filter((exercise) =>
      score(query, bodyPartHint, exercise).base >= confidenceThreshold
    )
    .slice(0, limit);
}

export function score(
  query: string,
  bodyPartHint: BodyPart | null,
  exercise: LibraryExercise,
): Score {
  const q = normalize(query);
  const name = normalize(exercise.name);
  const nameExact = q === name && q.length > 0 ? nameExactScore : 0;
  const aliasScore = bestAliasScore(q, exercise.aliases);
  const spelling = diceCoefficient(
    normalizedTokens(query),
    normalizedTokens(exercise.name),
  );
  const base = Math.max(nameExact, aliasScore, spelling);
  const boost = bodyPartHint !== null && exercise.bodyPart === bodyPartHint
    ? bodyPartBoost
    : 0;
  return { base, total: base + boost };
}

function bestAliasScore(query: string, aliases: string[]): number {
  let best = 0;
  for (const alias of aliases) {
    const a = normalize(alias);
    if (a.length === 0) continue;
    if (query === a) return aliasExactScore;
    if (query.includes(a) || a.includes(query)) {
      best = Math.max(best, aliasContainsScore);
    }
  }
  return best;
}

export function normalize(string: string): string {
  const lowered = string.toLowerCase();
  let acc = "";
  for (const char of lowered) {
    if (/[a-z0-9]/.test(char)) {
      acc += char;
    } else if (acc.length > 0 && !acc.endsWith(" ")) {
      acc += " ";
    }
  }
  return acc.trim();
}

function normalizedTokens(string: string): Set<string> {
  const tokens = normalize(string).split(" ").filter((t) => t.length > 0);
  return new Set(tokens);
}

function diceCoefficient(
  queryTokens: Set<string>,
  nameTokens: Set<string>,
): number {
  const denominator = queryTokens.size + nameTokens.size;
  if (denominator === 0) return 0;
  let intersection = 0;
  for (const token of queryTokens) {
    if (nameTokens.has(token)) intersection += 1;
  }
  return (2 * intersection) / denominator;
}
