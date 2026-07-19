import { existsSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";

const [marketplacePath, operation = "install"] = process.argv.slice(2);
if (!marketplacePath || !["install", "uninstall"].includes(operation)) {
  console.error("usage: node scripts/update-marketplace.mjs <marketplace.json> <install|uninstall>");
  process.exit(2);
}

let marketplace = {
  name: "personal",
  interface: { displayName: "Personal" },
  plugins: [],
};
if (existsSync(marketplacePath)) {
  marketplace = JSON.parse(readFileSync(marketplacePath, "utf8").replace(/^\uFEFF/, ""));
}
if (!Array.isArray(marketplace.plugins)) marketplace.plugins = [];
marketplace.plugins = marketplace.plugins.filter((entry) => entry?.name !== "codex-monitor-hud");
if (operation === "install") {
  marketplace.plugins.push({
    name: "codex-monitor-hud",
    source: { source: "local", path: "./plugins/codex-monitor-hud" },
    policy: { installation: "AVAILABLE", authentication: "ON_INSTALL" },
    category: "Productivity",
  });
}
mkdirSync(dirname(marketplacePath), { recursive: true });
const temporary = `${marketplacePath}.tmp.${process.pid}.${Date.now()}`;
try {
  writeFileSync(temporary, JSON.stringify(marketplace, null, 2), "utf8");
  renameSync(temporary, marketplacePath);
} finally {
  try { rmSync(temporary, { force: true }); } catch {}
}
