import { mkdir, open, writeFile } from "node:fs/promises";
import { randomBytes } from "node:crypto";
import { fileURLToPath } from "node:url";
import path from "node:path";

if (Number(process.versions.node.split(".")[0]) !== 24) {
  throw new Error("Activa Node.js 24 antes de preparar el entorno local.");
}
const root = fileURLToPath(new URL("../", import.meta.url));
const local = path.join(root, "work", "local");
await mkdir(local, { recursive: true });
let vars;
try {
  vars = await open(path.join(root, ".dev.vars"), "wx", 0o600);
  await vars.writeFile([
    "# Claves independientes de desarrollo local. No publicar ni compartir.",
    `PAYROLL_AUTH_KEY=${randomBytes(32).toString("base64url")}`,
    `PAYROLL_MAIL_KEY=${randomBytes(32).toString("base64url")}`,
    "",
  ].join("\n"));
  console.log("Claves locales creadas en .dev.vars; sus valores no se muestran.");
} catch (error) {
  if (error.code !== "EEXIST") throw error;
  console.log("Se conserva .dev.vars existente; revisa localmente que sean claves de desarrollo.");
} finally {
  await vars?.close();
}
const config = {
  name: "jac-local",
  main: path.join(root, "worker", "index.ts"),
  compatibility_date: "2026-09-21",
  compatibility_flags: ["nodejs_compat"],
  d1_databases: [{
    binding: "DB",
    database_name: "site-creator-d1",
    database_id: "00000000-0000-4000-8000-000000000000",
    migrations_dir: path.join(root, "drizzle"),
  }],
  r2_buckets: [{ binding: "BUCKET", bucket_name: "site-creator-r2" }],
};
await writeFile(path.join(local, "wrangler.json"), JSON.stringify(config, null, 2) + "\n", { mode: 0o600 });
console.log("Configuración local preparada en work/local/wrangler.json.");
console.log("Aplica migraciones con --local y arranca npm run dev -- --host 127.0.0.1.");
