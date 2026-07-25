import { readdir } from "node:fs/promises";
import path from "node:path";

const migrationDirectory = path.resolve("supabase", "migrations");
const files = (await readdir(migrationDirectory))
  .filter((file) => file.endsWith(".sql"))
  .sort();

// Historical migrations predate the repository's timestamp convention and
// include duplicate short versions. They remain immutable for compatibility.
// All migrations created after the repair cutoff must use a unique UTC
// YYYYMMDDHHMMSS prefix so the Supabase CLI can order them safely.
const cutoff = "20260720203000";
const modern = files.filter((file) => file.slice(0, 14) > cutoff);
const invalid = modern.filter((file) => !/^\d{14}_[a-z0-9_]+\.sql$/.test(file));
const versions = new Map();

for (const file of modern) {
  const version = file.slice(0, 14);
  versions.set(version, [...(versions.get(version) ?? []), file]);
}

const duplicates = [...versions.entries()].filter(([, names]) => names.length > 1);
if (invalid.length || duplicates.length) {
  if (invalid.length) {
    console.error(`Invalid migration names:\n${invalid.join("\n")}`);
  }
  if (duplicates.length) {
    console.error(
      `Duplicate migration versions:\n${duplicates
        .map(([version, names]) => `${version}: ${names.join(", ")}`)
        .join("\n")}`,
    );
  }
  process.exit(1);
}

console.log(`Checked ${modern.length} post-repair Supabase migrations.`);
