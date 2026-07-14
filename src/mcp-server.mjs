import { spawn } from "node:child_process";
import { appendFileSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const pluginRoot = dirname(here);
const stateRoot = join(process.env.LOCALAPPDATA || process.env.TEMP || ".", "CodexTokenHUD");
mkdirSync(stateRoot, { recursive: true });
const hostsRoot = join(stateRoot, "hosts");
const hostHeartbeat = join(hostsRoot, `${process.pid}.heartbeat`);
const debugPath = join(stateRoot, "mcp-debug.log");
mkdirSync(hostsRoot, { recursive: true });

function touchHeartbeat() {
  try { writeFileSync(hostHeartbeat, new Date().toISOString(), "utf8"); } catch {}
}

function debug(message) {
  if (process.env.TOKEN_HUD_DEBUG !== "1") return;
  try { appendFileSync(debugPath, `${new Date().toISOString()} pid=${process.pid} ${message}\n`, "utf8"); } catch {}
}

touchHeartbeat();
const heartbeatTimer = setInterval(touchHeartbeat, 2000);
heartbeatTimer.unref();

let hud = null;

function startHud(openSettings = false) {
  if (hud && hud.exitCode === null) return;
  const script = join(pluginRoot, "scripts", "start.ps1");
  const args = [
    "-NoProfile",
    "-WindowStyle", "Hidden",
    "-ExecutionPolicy", "Bypass",
    "-File", script,
    "-Managed",
  ];
  if (openSettings) args.push("-Settings");
  if (process.env.TOKEN_HUD_DEBUG === "1") args.push("-DebugLog");
  const debugHud = process.env.TOKEN_HUD_DEBUG === "1";
  hud = spawn("powershell.exe", args, {
    cwd: pluginRoot,
    windowsHide: true,
    stdio: debugHud ? ["ignore", "ignore", "pipe"] : "ignore",
  });
  debug(`spawned HUD pid=${hud.pid || "none"} openSettings=${openSettings}`);
  hud.on("error", (error) => { debug(`HUD spawn error: ${error.message || error}`); hud = null; });
  hud.on("exit", (code, signalName) => { debug(`HUD exit code=${code} signal=${signalName}`); hud = null; });
  if (debugHud && hud.stderr) hud.stderr.on("data", (chunk) => debug(`HUD stderr: ${String(chunk).trim()}`));
}

function signal(name) {
  writeFileSync(join(stateRoot, `${name}.signal`), new Date().toISOString(), "utf8");
}

function textResult(text) {
  return { content: [{ type: "text", text }] };
}

const tools = [
  {
    name: "token_hud_open_settings",
    description: "Open the local Codex Token HUD appearance and metric settings window.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "token_hud_show",
    description: "Show or restart the local Codex Token HUD.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "token_hud_hide",
    description: "Hide the local Codex Token HUD without changing its settings.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "token_hud_pause",
    description: "Pause live updates in the local Codex Token HUD.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "token_hud_disable_click_through",
    description: "Emergency recovery: disable mouse click-through so the local Codex Token HUD can be clicked again.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
];

function handle(request) {
  const { id, method, params = {} } = request;
  if (method === "initialize") {
    return {
      jsonrpc: "2.0",
      id,
      result: {
        protocolVersion: params.protocolVersion || "2025-06-18",
        capabilities: { tools: {} },
        serverInfo: { name: "codex-token-hud", version: "1.3.1" },
      },
    };
  }
  if (method === "ping") return { jsonrpc: "2.0", id, result: {} };
  if (method === "tools/list") return { jsonrpc: "2.0", id, result: { tools } };
  if (method === "prompts/list") return { jsonrpc: "2.0", id, result: { prompts: [] } };
  if (method === "resources/list") return { jsonrpc: "2.0", id, result: { resources: [] } };
  if (method === "tools/call") {
    const name = params.name;
    if (name === "token_hud_open_settings") {
      startHud(true);
      signal("open-settings");
      return { jsonrpc: "2.0", id, result: textResult("Codex Token HUD settings opened locally.") };
    }
    if (name === "token_hud_show") {
      startHud(false);
      signal("show");
      return { jsonrpc: "2.0", id, result: textResult("Codex Token HUD is visible.") };
    }
    if (name === "token_hud_hide") {
      signal("hide");
      return { jsonrpc: "2.0", id, result: textResult("Codex Token HUD hidden.") };
    }
    if (name === "token_hud_pause") {
      signal("pause");
      return { jsonrpc: "2.0", id, result: textResult("Codex Token HUD pause toggled.") };
    }
    if (name === "token_hud_disable_click_through") {
      startHud(false);
      signal("passthrough-off");
      return { jsonrpc: "2.0", id, result: textResult("Codex Token HUD mouse click-through disabled.") };
    }
    return { jsonrpc: "2.0", id, error: { code: -32601, message: `Unknown tool: ${name}` } };
  }
  if (id === undefined) return null;
  return { jsonrpc: "2.0", id, error: { code: -32601, message: `Method not found: ${method}` } };
}

if (process.env.TOKEN_HUD_DISABLE_AUTO_START !== "1") startHud(false);

let buffer = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  buffer += chunk;
  while (true) {
    const newline = buffer.indexOf("\n");
    if (newline < 0) break;
    const line = buffer.slice(0, newline).trim();
    buffer = buffer.slice(newline + 1);
    if (!line) continue;
    try {
      const response = handle(JSON.parse(line));
      if (response) process.stdout.write(`${JSON.stringify(response)}\n`);
    } catch (error) {
      process.stdout.write(`${JSON.stringify({ jsonrpc: "2.0", id: null, error: { code: -32700, message: String(error.message || error) } })}\n`);
    }
  }
});

function shutdown() {
  debug("host shutdown");
  clearInterval(heartbeatTimer);
  try { rmSync(hostHeartbeat, { force: true }); } catch {}
  // The HUD owns shared lifecycle coordination. It exits only after every
  // plugin-host heartbeat is gone, so one closing task cannot stop another.
  process.exit(0);
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
process.stdin.on("end", shutdown);
