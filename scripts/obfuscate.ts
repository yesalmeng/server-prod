import { PrismaClient } from "@prisma/client";
import dotenv from "dotenv";
import { runObfuscation } from "../src/modules/obfuscate/obfuscate.runner";

dotenv.config();

async function main() {
  // Use DIRECT_URL to bypass PgBouncer (transaction mode) which breaks
  // Prisma prepared statements inside interactive transactions.
  const directUrl = process.env.DIRECT_URL || process.env.DATABASE_URL;
  const prisma = new PrismaClient({
    datasources: {
      db: { url: directUrl },
    },
  });

  try {
    await prisma.$connect();
    console.log("Connected to database");
    await runObfuscation(prisma);
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((err) => {
  console.error("Obfuscation failed:", err);
  process.exit(1);
});
