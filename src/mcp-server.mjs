import { spawn } from "node:child_process";
import { appendFileSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const pluginRoot = dirname(here);
const stateRoot = join(process.env.LOCALAPPDATA || process.env.TEMP || ".", "CodexMonitorHUD");
mkdirSync(stateRoot, { recursive: true });
const hostsRoot = join(stateRoot, "hosts");
const notificationsRoot = join(stateRoot, "notifications");
const hostHeartbeat = join(hostsRoot, `${process.pid}.heartbeat`);
const debugPath = join(stateRoot, "mcp-debug.log");
mkdirSync(hostsRoot, { recursive: true });
mkdirSync(notificationsRoot, { recursive: true });

function notificationPermission() {
  try {
    const settings = JSON.parse(readFileSync(join(stateRoot, "settings.json"), "utf8").replace(/^\uFEFF/, ""));
    if (!settings?.agentNotifications?.enabled) return "off";
    return settings.agentNotifications.permission === "expressive" ? "expressive" : "text";
  } catch { return "off"; }
}

function notificationCapabilities() {
  const permission = notificationPermission();
  let activeTasks = [];
  try {
    const registry = JSON.parse(readFileSync(join(stateRoot, "task-registry.json"), "utf8").replace(/^\uFEFF/, ""));
    if (Array.isArray(registry?.tasks)) activeTasks = registry.tasks.slice(0, 64);
  } catch {}
  return {
    enabled: permission !== "off",
    permission,
    identity: "Every notice is visibly labeled CODEX NOTICE / CODEX 通知.",
    targeting: "Pass task_number whenever possible. Match the current workspace to active_tasks; if ambiguous, ask the user. Omitting it targets the most recently active task.",
    limits: { plain_text_characters: 160, animation_layers: 4, no_links_or_rich_text: true, no_executable_code: true },
    active_tasks: activeTasks,
  };
}

function cleanNoticeText(value) {
  return String(value ?? "").replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim().slice(0, 160);
}

function boundedAnimation(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const allowedLayers = new Set(["glow", "pulse", "breathe", "flow"]);
  const layers = Array.isArray(value.layers) ? [...new Set(value.layers.filter((x) => allowedLayers.has(x)))].slice(0, 4) : [];
  const color = /^#[0-9a-f]{8}$/i.test(String(value.color || "")) ? String(value.color) : undefined;
  const number = (v, min, max, fallback) => Number.isFinite(Number(v)) ? Math.max(min, Math.min(max, Number(v))) : fallback;
  return {
    layers,
    color,
    intensity: number(value.intensity, 0.2, 1, 0.7),
    tempo_ms: Math.round(number(value.tempo_ms, 240, 2500, 720)),
    cycles: Math.round(number(value.cycles, 1, 8, 3)),
    glow_radius: number(value.glow_radius, 8, 60, 30),
    scale: number(value.scale, 1, 1.08, 1.025),
    direction: value.direction === "right-to-left" ? "right-to-left" : "left-to-right",
  };
}

function touchHeartbeat() {
  try { writeFileSync(hostHeartbeat, new Date().toISOString(), "utf8"); } catch {}
}

function debug(message) {
  if (process.env.CODEX_MONITOR_HUD_DEBUG !== "1") return;
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
  if (process.env.CODEX_MONITOR_HUD_DEBUG === "1") args.push("-DebugLog");
  const debugHud = process.env.CODEX_MONITOR_HUD_DEBUG === "1";
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
    name: "monitor_hud_open_settings",
    description: "Open the local Codex Monitor HUD appearance and metric settings window.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "monitor_hud_show",
    description: "Show or restart the local Codex Monitor HUD.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "monitor_hud_hide",
    description: "Hide the local Codex Monitor HUD without changing its settings.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "monitor_hud_pause",
    description: "Pause live updates in the local Codex Monitor HUD.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "monitor_hud_disable_click_through",
    description: "Emergency recovery: disable mouse click-through so the local Codex Monitor HUD can be clicked again.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "monitor_hud_notification_capabilities",
    description: "Read the current opt-in Codex notice permission and privacy-safe active HUD task numbers. Call this before the first proactive notice in a task; do not rely on another conversation's memory.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "monitor_hud_notify",
    description: "Opt-in: show a short CODEX-labeled notice on one relevant HUD task. Check monitor_hud_notification_capabilities first and pass its matching task_number whenever possible. With expressive permission, compose a bounded live animation recipe; never include secrets or full logs.",
    inputSchema: {
      type: "object",
      required: ["message"],
      additionalProperties: false,
      properties: {
        message: { type: "string", minLength: 1, maxLength: 160, description: "One or two short plain-text sentences asking the user to return." },
        task_number: { type: "integer", minimum: 1, description: "Optional visible HUD task number; otherwise the most recently active task is selected." },
        animation: {
          type: "object",
          additionalProperties: false,
          properties: {
            layers: { type: "array", maxItems: 4, items: { type: "string", enum: ["glow", "pulse", "breathe", "flow"] } },
            color: { type: "string", pattern: "^#[0-9A-Fa-f]{8}$" },
            intensity: { type: "number", minimum: 0.2, maximum: 1 },
            tempo_ms: { type: "integer", minimum: 240, maximum: 2500 },
            cycles: { type: "integer", minimum: 1, maximum: 8 },
            glow_radius: { type: "number", minimum: 8, maximum: 60 },
            scale: { type: "number", minimum: 1, maximum: 1.08 },
            direction: { type: "string", enum: ["left-to-right", "right-to-left"] }
          }
        }
      }
    },
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
        serverInfo: { name: "codex-monitor-hud", version: "2.0.2-preview" },
      },
    };
  }
  if (method === "ping") return { jsonrpc: "2.0", id, result: {} };
  if (method === "tools/list") return { jsonrpc: "2.0", id, result: { tools } };
  if (method === "prompts/list") return { jsonrpc: "2.0", id, result: { prompts: [] } };
  if (method === "resources/list") return { jsonrpc: "2.0", id, result: { resources: [] } };
  if (method === "tools/call") {
    const name = params.name;
    if (name === "monitor_hud_open_settings") {
      startHud(true);
      signal("open-settings");
      return { jsonrpc: "2.0", id, result: textResult("Codex Monitor HUD settings opened locally.") };
    }
    if (name === "monitor_hud_show") {
      startHud(false);
      signal("show");
      return { jsonrpc: "2.0", id, result: textResult("Codex Monitor HUD is visible.") };
    }
    if (name === "monitor_hud_hide") {
      signal("hide");
      return { jsonrpc: "2.0", id, result: textResult("Codex Monitor HUD hidden.") };
    }
    if (name === "monitor_hud_pause") {
      signal("pause");
      return { jsonrpc: "2.0", id, result: textResult("Codex Monitor HUD pause toggled.") };
    }
    if (name === "monitor_hud_disable_click_through") {
      startHud(false);
      signal("passthrough-off");
      return { jsonrpc: "2.0", id, result: textResult("Codex Monitor HUD mouse click-through disabled.") };
    }
    if (name === "monitor_hud_notification_capabilities") {
      return { jsonrpc: "2.0", id, result: textResult(JSON.stringify(notificationCapabilities(), null, 2)) };
    }
    if (name === "monitor_hud_notify") {
      const permission = notificationPermission();
      if (permission === "off") return { jsonrpc: "2.0", id, result: textResult("Codex proactive notices are disabled in HUD settings.") };
      const message = cleanNoticeText(params.arguments?.message);
      if (!message) return { jsonrpc: "2.0", id, error: { code: -32602, message: "A non-empty plain-text message is required." } };
      const requestedAnimation = boundedAnimation(params.arguments?.animation);
      const payload = {
        version: 1,
        created_at: new Date().toISOString(),
        source: "codex-mcp",
        message,
        task_number: Number.isInteger(params.arguments?.task_number) ? params.arguments.task_number : null,
        animation: permission === "expressive" ? requestedAnimation : null,
      };
      writeFileSync(join(notificationsRoot, `notice-${Date.now()}-${process.pid}.json`), JSON.stringify(payload), "utf8");
      if (process.env.CODEX_MONITOR_HUD_DISABLE_AUTO_START !== "1") startHud(false);
      return { jsonrpc: "2.0", id, result: textResult(`Codex Monitor HUD notice queued (${permission} permission).`) };
    }
    return { jsonrpc: "2.0", id, error: { code: -32601, message: `Unknown tool: ${name}` } };
  }
  if (id === undefined) return null;
  return { jsonrpc: "2.0", id, error: { code: -32601, message: `Method not found: ${method}` } };
}

if (process.env.CODEX_MONITOR_HUD_DISABLE_AUTO_START !== "1") startHud(false);

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
