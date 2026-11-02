import { randomUUID } from "node:crypto";
import { spawnSync } from "node:child_process";
const result = spawnSync(process.execPath, ["node_modules/next/dist/bin/next", "build", "--webpack"], {
  stdio: "inherit",
  env: { ...process.env, NEXT_DEPLOYMENT_ID: process.env.NEXT_DEPLOYMENT_ID || `kodimali-${randomUUID()}` },
});
if (result.error) throw result.error;
process.exit(result.status ?? 1);
