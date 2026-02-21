import { PrismaClient } from "@prisma/client";
import dotenv from "dotenv";
import { runObfuscation } from "../src/modules/obfuscate/obfuscate.runner";

dotenv.config();

async function main() {
  const prisma = new PrismaClient();

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
