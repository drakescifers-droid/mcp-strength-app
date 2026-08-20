import type { SupabaseClient } from "npm:@supabase/supabase-js";

export type Row = Record<string, unknown>;

export class Query {
  private db: Record<string, Row[]>;
  private table: string;
  rows: Row[];
  private patch: Row | null = null;

  constructor(db: Record<string, Row[]>, table: string) {
    this.db = db;
    this.table = table;
    this.rows = (db[table] ?? []).slice();
  }
  select() {
    return this;
  }
  insert(payload: Row | Row[]) {
    const rows = Array.isArray(payload) ? payload : [payload];
    this.db[this.table] = [...(this.db[this.table] ?? []), ...rows];
    this.rows = rows;
    return this;
  }
  update(patch: Row) {
    this.patch = patch;
    return this;
  }
  is(column: string, value: unknown) {
    this.rows = this.rows.filter((row) => (row[column] ?? null) === value);
    return this;
  }
  eq(column: string, value: unknown) {
    this.rows = this.rows.filter((row) => row[column] === value);
    return this;
  }
  in(column: string, values: unknown[]) {
    const allowed = new Set(values);
    this.rows = this.rows.filter((row) => allowed.has(row[column]));
    return this;
  }
  gte(column: string, value: string) {
    this.rows = this.rows.filter((row) => String(row[column]) >= value);
    return this;
  }
  lte(column: string, value: string) {
    this.rows = this.rows.filter((row) => String(row[column]) <= value);
    return this;
  }
  not(column: string, operator: string, value: unknown) {
    if (operator === "is" && value === null) {
      this.rows = this.rows.filter((row) => (row[column] ?? null) !== null);
    }
    return this;
  }
  order(column: string, opts?: { ascending?: boolean }) {
    const ascending = opts?.ascending !== false;
    this.rows.sort((a, b) => {
      const av = String(a[column] ?? "");
      const bv = String(b[column] ?? "");
      if (av === bv) return 0;
      const cmp = av < bv ? -1 : 1;
      return ascending ? cmp : -cmp;
    });
    return this;
  }
  limit(n: number) {
    this.rows = this.rows.slice(0, n);
    return this;
  }
  single() {
    this.applyPatch();
    const row = this.rows[0] ?? null;
    return Promise.resolve({
      data: row,
      error: row === null ? { message: "not found" } : null,
    });
  }
  then(
    onFulfilled?: (value: { data: Row[]; error: null }) => unknown,
    onRejected?: (reason: unknown) => unknown,
  ) {
    this.applyPatch();
    return Promise.resolve({ data: this.rows, error: null }).then(
      onFulfilled,
      onRejected,
    );
  }
  private applyPatch() {
    if (this.patch === null) return;
    for (const row of this.rows) Object.assign(row, this.patch);
  }
}

export function clientWith(db: Record<string, Row[]>): SupabaseClient {
  return {
    from(table: string) {
      return new Query(db, table);
    },
  } as unknown as SupabaseClient;
}
