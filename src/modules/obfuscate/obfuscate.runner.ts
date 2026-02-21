import { PrismaClient } from "@prisma/client";
import {
  type ColumnRule,
  maskingConfig,
  skipEmailMatchTables,
  OBFUSCATION_TIMEOUT_MS
} from "./obfuscate.config"

type PrismaDelegate = {
  findMany: (args: { select: Record<string, boolean> }) => Promise<Record<string, unknown>[]>;
  update: (args: { where: Record<string, unknown>; data: Record<string, unknown> }) => unknown;
};

type RawClient = {
  $executeRawUnsafe: (query: string, ...values: unknown[]) => Promise<number>;
};

type RowWithValue = {
  row: Record<string, unknown>;
  newValue: unknown;
};

// Tune this based on your DB's max parameter limits.
// PostgreSQL supports up to 65535 params; at (pkFields.length + 1) params per row,
// this gives comfortable headroom for most schemas.
const BATCH_SIZE = 500;

export async function runObfuscation(prisma: PrismaClient): Promise<void> {
  console.log("=".repeat(60));
  console.log("Starting data obfuscation");
  console.log("=".repeat(60));

  const start = Date.now();

  const userEmails = await getUserEmails(prisma);
  console.log(`Loaded ${userEmails.size} user emails for skip logic`);

  await prisma.$transaction(
    async (tx) => {
      let success = 0;
      const skipIdsCache = new Map<string, Set<string>>();

      for (const [table, tableConfig] of Object.entries(maskingConfig)) {
        const skipIds = await getSkipIds(tx, table, userEmails, skipIdsCache);
        const primaryKey = tableConfig.primaryKey || "id";
        for (const [column, rule] of Object.entries(tableConfig.columns)) {
          try {
            await maskColumn(tx, table, column, rule, skipIds, primaryKey);
            success++;
          } catch (err) {
            console.error(`Failed to mask ${table}.${column}:`, err);
            throw err;
          }
        }
      }

      const elapsed = ((Date.now() - start) / 1000).toFixed(2);
      console.log("=".repeat(60));
      console.log(
        `Obfuscation completed in ${elapsed}s — ${success} columns masked`,
      );
      console.log("=".repeat(60));
    },
    {
      timeout: OBFUSCATION_TIMEOUT_MS,
    }
  );
}

async function getUserEmails(prisma: PrismaClient): Promise<Set<string>> {
  const users = await prisma.user.findMany({
    select: { email: true },
  });
  return new Set(
    users
      .map((u) => u.email?.trim().toLowerCase())
      .filter((e): e is string => Boolean(e)),
  );
}

async function getSkipIds(
  client: PrismaClient | Omit<PrismaClient, "$connect" | "$disconnect" | "$on" | "$transaction" | "$extends">,
  table: string,
  userEmails: Set<string>,
  cache: Map<string, Set<string>>,
): Promise<Set<string>> {
  if (!skipEmailMatchTables.includes(table)) {
    return new Set();
  }

  const cached = cache.get(table);
  if (cached) return cached;

  const delegate = (client as unknown as Record<string, PrismaDelegate>)[table];
  const rows = await delegate.findMany({
    select: { id: true, email: true },
  });

  const skipIds = new Set<string>();
  for (const row of rows) {
    const email = (row.email as string | null)?.trim().toLowerCase();
    if (email && userEmails.has(email)) {
      console.log(`  Skipping protected row: ${table}.id=${row.id}`);
      skipIds.add(row.id as string);
    }
  }

  cache.set(table, skipIds);
  return skipIds;
}

async function maskColumn(
  client: PrismaClient | Omit<PrismaClient, "$connect" | "$disconnect" | "$on" | "$transaction" | "$extends">,
  table: string,
  column: string,
  rule: ColumnRule,
  skipIds: Set<string>,
  primaryKey: string | string[],
): Promise<void> {
  console.log(`Masking ${table}.${column}`);

  const delegate = (client as unknown as Record<string, PrismaDelegate>)[table];
  const pkFields = Array.isArray(primaryKey) ? primaryKey : [primaryKey];

  const selectObj: Record<string, boolean> = { [column]: true };
  for (const pkField of pkFields) {
    selectObj[pkField] = true;
  }

  const rows = await delegate.findMany({ select: selectObj });

  if (!rows.length) {
    console.warn(`  No data in ${table}.${column} — skipping`);
    return;
  }

  const getRowKey = (row: Record<string, unknown>): string => {
    if (Array.isArray(primaryKey)) {
      return primaryKey.map(pk => String(row[pk])).join('|');
    }
    return String(row[primaryKey as string]);
  };

  const rowsToMask = rows.filter(r => !skipIds.has(getRowKey(r)));
  const skipped = rows.length - rowsToMask.length;

  if (skipped > 0) {
    console.log(`  Skipped ${skipped} protected rows in ${table}.${column}`);
  }

  if (!rowsToMask.length) {
    console.log(`  All rows protected — nothing to mask`);
    return;
  }

  const nullFreq = rule.nullFrequency ?? 0;
  const rowsWithValues: RowWithValue[] = rowsToMask.map(row => ({
    row,
    newValue: nullFreq > 0 && Math.random() < nullFreq ? null : rule.generator(),
  }));

  // Execute bulk updates in batches to stay within DB parameter limits
  const rawClient = client as unknown as RawClient;
  for (let i = 0; i < rowsWithValues.length; i += BATCH_SIZE) {
    const batch = rowsWithValues.slice(i, i + BATCH_SIZE);
    await bulkUpdate(rawClient, table, column, pkFields, batch);
  }

  console.log(`  Masked ${rowsToMask.length} rows in ${table}.${column}`);
}

/**
 * Issues a single UPDATE per batch using a VALUES-list join, which avoids
 * per-row round trips and is more efficient than CASE WHEN for large batches:
 *
 *   UPDATE "table" AS t
 *   SET "column" = v.new_value
 *   FROM (VALUES ($1, $2), ($3, $4), ...) AS v(pk, new_value)
 *   WHERE t."pk" = v.pk
 *
 * For composite PKs the WHERE clause fans out across all key fields.
 * All identifiers (table/column names) are quoted to prevent SQL injection;
 * all values are passed as parameters.
 */
async function bulkUpdate(
  client: RawClient,
  table: string,
  column: string,
  pkFields: string[],
  batch: RowWithValue[],
): Promise<void> {
  const params: unknown[] = [];
  const valueRows: string[] = [];

  for (const { row, newValue } of batch) {
    const rowParams: string[] = [];

    for (const pkField of pkFields) {
      params.push(row[pkField]);
      rowParams.push(`$${params.length}`);
    }

    params.push(newValue);
    rowParams.push(`$${params.length}`);

    valueRows.push(`(${rowParams.join(", ")})`);
  }

  // Column aliases in the VALUES CTE: one per PK field + the new value
  const pkAliases = pkFields.map((_, i) => `pk_${i}`).join(", ");
  const valuesCte = `(VALUES ${valueRows.join(", ")}) AS v(${pkAliases}, new_value)`;

  // WHERE t."pkField"::text = v.pk_0::text AND ...
  // Cast both sides to text to avoid type mismatches (e.g. uuid = text).
  const whereClause = pkFields
    .map((pkField, i) => `t."${pkField}"::text = v.pk_${i}::text`)
    .join(" AND ");

  const sql = `
    UPDATE "${table}" AS t
    SET "${column}" = v.new_value
    FROM ${valuesCte}
    WHERE ${whereClause}
  `;

  await client.$executeRawUnsafe(sql, ...params);
}