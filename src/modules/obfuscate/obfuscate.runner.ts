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
export async function runObfuscation(prisma: PrismaClient): Promise<void> {
  console.log("=".repeat(60));
  console.log("Starting data obfuscation");
  console.log("=".repeat(60));

  const start = Date.now();

  const userEmails = await getUserEmails(prisma);
  console.log(`Loaded ${userEmails.size} user emails for skip logic`);

  // Wrap entire obfuscation in a single transaction for atomicity
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
            throw err; // Fail-fast: abort transaction on first error
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

  const rows = await delegate.findMany({
    select: selectObj,
  });

  if (!rows.length) {
    console.warn(`  No data in ${table}.${column} — skipping`);
    return;
  }

  // skip admin users
  const getRowKey = (row: Record<string, unknown>): string => {
    if (Array.isArray(primaryKey)) {
      return primaryKey.map(pk => String(row[pk])).join('|');
    }
    return String(row[primaryKey as string]);
  };

  const rowsToMask = rows.filter((r) => !skipIds.has(getRowKey(r)));
  const skipped = rows.length - rowsToMask.length;

  if (skipped > 0) {
    console.log(
      `  Skipped ${skipped} protected rows in ${table}.${column}`,
    );
  }

  if (!rowsToMask.length) {
    console.log(`  All rows protected — nothing to mask`);
    return;
  }

  const nullFreq = rule.nullFrequency ?? 0;
  const CHUNK_SIZE = 25;

  for (let i = 0; i < rowsToMask.length; i += CHUNK_SIZE) {
    const chunk = rowsToMask.slice(i, i + CHUNK_SIZE);

    const updates = chunk.map((row) => {
      const newValue =
        nullFreq > 0 && Math.random() < nullFreq
          ? null
          : rule.generator();

      // where clause for composite or simple key
      let whereClause: Record<string, unknown>;
      if (Array.isArray(primaryKey)) {
        // composite keys, Prisma uses: { key1_key2: { key1: val1, key2: val2 } }
        const compositeKeyName = pkFields.join('_');
        const compositeKeyValue: Record<string, unknown> = {};
        for (const pkField of pkFields) {
          compositeKeyValue[pkField] = row[pkField];
        }
        whereClause = { [compositeKeyName]: compositeKeyValue };
      } else {
        whereClause = { [primaryKey]: row[primaryKey] };
      }

      return delegate.update({
        where: whereClause,
        data: { [column]: newValue },
      });
    }) as unknown[];

    await Promise.all(updates);
  }

  console.log(`  Masked ${rowsToMask.length} rows in ${table}.${column}`);
}
