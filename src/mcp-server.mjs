import { spawn } from "node:child_process";
import { appendFileSync, existsSync, mkdirSync, readFileSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { homedir } from "node:os";
import { fileURLToPath } from "node:url";

const SERVER_VERSION = "3.2.0";
const SUPPORTED_PROTOCOL_VERSIONS = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"];
const SERVER_INSTRUCTIONS = "Codex Monitor HUD is a local, closed-world HUD control server. Before a proactive notice, call monitor_hud_notification_capabilities and match task_number plus client/provider to the current task. When the user enables a capacity guard, call monitor_hud_quota_guard at natural checkpoints and before expensive work; a low result means write a recoverable handoff, not that the HUD can interrupt a running turn. Never include secrets, credentials, prompts, replies, or full logs. Notices require user opt-in and are limited to 160 plain-text characters. Control tools affect only the local HUD.";

const here = dirname(fileURLToPath(import.meta.url));
const pluginRoot = dirname(here);
const stateRoot = process.env.CODEX_MONITOR_HUD_STATE_ROOT || (process.platform === "darwin"
  ? join(homedir(), "Library", "Application Support", "CodexMonitorHUD")
  : join(process.env.LOCALAPPDATA || process.env.TEMP || ".", "CodexMonitorHUD"));
mkdirSync(stateRoot, { recursive: true });
const hostsRoot = join(stateRoot, "hosts");
const notificationsRoot = join(stateRoot, "notifications");
const hostHeartbeat = join(hostsRoot, `${process.pid}.heartbeat`);
const hudHeartbeat = join(stateRoot, "hud.heartbeat");
const manualExitMarker = join(stateRoot, "manual-exit.signal");
const debugPath = join(stateRoot, "mcp-debug.log");
mkdirSync(hostsRoot, { recursive: true });
mkdirSync(notificationsRoot, { recursive: true });

function readSettings() {
  try {
    return JSON.parse(readFileSync(join(stateRoot, "settings.json"), "utf8").replace(/^\uFEFF/, ""));
  } catch {
    return {};
  }
}

function notificationPermission() {
  const settings = readSettings();
  if (!settings?.agentNotifications?.enabled) return "off";
  return settings.agentNotifications.permission === "expressive" ? "expressive" : "text";
}

function cleanField(value, maximum = 80) {
  return String(value ?? "").replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim().slice(0, maximum);
}

function readTaskRegistry() {
  try {
    const registry = JSON.parse(readFileSync(join(stateRoot, "task-registry.json"), "utf8").replace(/^\uFEFF/, ""));
    const tasks = Array.isArray(registry?.tasks) ? registry.tasks.slice(0, 64).flatMap((task) => {
      const taskNumber = Number(task?.task_number);
      if (!Number.isInteger(taskNumber) || taskNumber < 1) return [];
      return [{
        task_number: taskNumber,
        workspace: cleanField(task?.workspace),
        status: cleanField(task?.status, 24),
        client: cleanField(task?.client || "unknown", 24),
        provider: cleanField(task?.provider, 40),
        profile: cleanField(task?.profile || "codex", 24),
        updated_at: cleanField(task?.updated_at, 48),
      }];
    }) : [];
    const rawQuota = registry?.quota_guard && typeof registry.quota_guard === "object" ? registry.quota_guard : {};
    const percent = (value) => Number.isFinite(Number(value)) ? Math.max(0, Math.min(100, Number(value))) : null;
    const state = ["disabled", "unavailable", "clear", "prepare_handoff", "handoff_now"].includes(rawQuota?.state)
      ? rawQuota.state
      : "unavailable";
    const event = ["disabled", "unavailable", "clear", "entered_prepare", "entered_handoff", "escalated_handoff", "deescalated", "recovered", "steady"].includes(rawQuota?.event)
      ? rawQuota.event
      : "unavailable";
    const quota_guard = {
      state,
      event,
      should_alert: rawQuota?.should_alert === true,
      five_hour_remaining_percent: percent(rawQuota?.five_hour_remaining_percent),
      weekly_remaining_percent: percent(rawQuota?.weekly_remaining_percent),
      observed_at: cleanField(rawQuota?.observed_at, 48),
      instruction: cleanField(rawQuota?.instruction, 1200),
    };
    return { version: Number(registry?.version) || 1, generated_at: cleanField(registry?.generated_at, 48), tasks, quota_guard };
  } catch {
    return {
      version: 0,
      generated_at: "",
      tasks: [],
      quota_guard: {
        state: "unavailable",
        event: "unavailable",
        should_alert: false,
        five_hour_remaining_percent: null,
        weekly_remaining_percent: null,
        observed_at: "",
        instruction: "No locally observed Codex allowance is available. Do not guess a limit or interrupt work.",
      },
    };
  }
}

function notificationCapabilities() {
  const permission = notificationPermission();
  const registry = readTaskRegistry();
  return {
    enabled: permission !== "off",
    permission,
    identity: "Every notice is visibly labeled CODEX NOTICE / CODEX 通知.",
    targeting: "Match the current task to active_tasks by workspace, client, provider and profile, then pass task_number. If ambiguous, ask the user. Do not rely on another conversation's memory.",
    limits: {
      plain_text_characters: 160,
      animation_layers: 4,
      no_links_or_rich_text: true,
      no_executable_code: true,
    },
    active_tasks: registry.tasks,
    quota_guard: registry.quota_guard,
  };
}

function hudStatus() {
  const settings = readSettings();
  const registry = readTaskRegistry();
  let heartbeatAgeSeconds = null;
  try { heartbeatAgeSeconds = Math.max(0, (Date.now() - statSync(hudHeartbeat).mtimeMs) / 1000); } catch {}
  const heartbeatFresh = heartbeatAgeSeconds !== null && heartbeatAgeSeconds <= 8;
  return {
    ok: true,
    hud_state: heartbeatFresh ? "running" : "not_detected",
    heartbeat_fresh: heartbeatFresh,
    heartbeat_age_seconds: heartbeatAgeSeconds === null ? null : Math.round(heartbeatAgeSeconds * 10) / 10,
    monitoring_sources: {
      desktop_openai: settings?.sessionSources?.desktop !== false,
      vscode_openai: settings?.sessionSources?.vscode !== false,
      default_cli: settings?.sessionSources?.defaultCli !== false,
      deepseek_cli: settings?.sessionSources?.deepSeekCli !== false,
    },
    registry_version: registry.version,
    registry_generated_at: registry.generated_at,
    active_task_count: registry.tasks.length,
    active_tasks: registry.tasks,
    quota_guard: registry.quota_guard,
  };
}

function quotaGuard() {
  return readTaskRegistry().quota_guard;
}

function cleanNoticeText(value) {
  return cleanField(value, 160);
}

function boundedAnimation(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const allowedLayers = new Set(["glow", "pulse", "breathe", "flow"]);
  const layers = Array.isArray(value.layers) ? [...new Set(value.layers.filter((x) => allowedLayers.has(x)))].slice(0, 4) : [];
  const color = /^#[0-9a-f]{8}$/i.test(String(value.color || "")) ? String(value.color) : undefined;
  const number = (candidate, minimum, maximum, fallback) => Number.isFinite(Number(candidate))
    ? Math.max(minimum, Math.min(maximum, Number(candidate)))
    : fallback;
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
  try {
    if (existsSync(debugPath) && statSync(debugPath).size > 1024 * 1024) writeFileSync(debugPath, "", "utf8");
    appendFileSync(debugPath, `${new Date().toISOString()} pid=${process.pid} ${message}\n`, "utf8");
  } catch {}
}

touchHeartbeat();
const heartbeatTimer = setInterval(touchHeartbeat, 2000);
heartbeatTimer.unref();

let hud = null;
let lastHudStartAttempt = 0;
let nextHudRestartAt = 0;
const hudRestartAttempts = [];
let noticeSequence = 0;

function startHud(openSettings = false) {
  if (hud && hud.exitCode === null) return;
  try { rmSync(manualExitMarker, { force: true }); } catch {}
  lastHudStartAttempt = Date.now();
  const isMac = process.platform === "darwin";
  const command = isMac
    ? process.env.CODEX_MONITOR_HUD_MAC_APP || join(homedir(), "Applications", "CodexMonitorHUD.app", "Contents", "MacOS", "CodexMonitorHud")
    : "powershell.exe";
  const args = isMac
    ? ["--plugin-root", pluginRoot, "--managed", "--parent-pid", String(process.pid)]
    : ["-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", join(pluginRoot, "scripts", "start.ps1"), "-Managed"];
  if (openSettings) args.push(isMac ? "--open-settings" : "-Settings");
  if (!isMac && process.env.CODEX_MONITOR_HUD_DEBUG === "1") args.push("-DebugLog");
  const debugHud = process.env.CODEX_MONITOR_HUD_DEBUG === "1";
  hud = spawn(command, args, {
    cwd: pluginRoot,
    windowsHide: true,
    stdio: debugHud ? ["ignore", "ignore", "pipe"] : "ignore",
  });
  debug(`spawned HUD pid=${hud.pid || "none"} openSettings=${openSettings}`);
  hud.on("error", (error) => { debug(`HUD spawn error: ${error.message || error}`); hud = null; });
  hud.on("exit", (code, signalName) => { debug(`HUD exit code=${code} signal=${signalName}`); hud = null; });
  if (debugHud && hud.stderr) hud.stderr.on("data", (chunk) => debug(`HUD stderr: ${String(chunk).trim()}`));
}

function hudHeartbeatIsFresh(now = Date.now()) {
  try { return now - statSync(hudHeartbeat).mtimeMs <= 8000; } catch { return false; }
}

function maintainHud() {
  if (process.env.CODEX_MONITOR_HUD_DISABLE_AUTO_START === "1" || existsSync(manualExitMarker)) return;
  const now = Date.now();
  if (hudHeartbeatIsFresh(now)) {
    hudRestartAttempts.length = 0;
    nextHudRestartAt = 0;
    return;
  }
  if (now - lastHudStartAttempt < 10000 || now < nextHudRestartAt) return;
  while (hudRestartAttempts.length && now - hudRestartAttempts[0] > 5 * 60 * 1000) hudRestartAttempts.shift();
  if (hudRestartAttempts.length >= 3) return;
  hudRestartAttempts.push(now);
  const backoffMs = Math.min(30000, 2000 * (2 ** (hudRestartAttempts.length - 1)));
  nextHudRestartAt = now + backoffMs;
  debug(`HUD heartbeat missing; bounded restart ${hudRestartAttempts.length}/3 backoff=${backoffMs}ms`);
  startHud(false);
}

function signal(name) {
  writeFileSync(join(stateRoot, `${name}.signal`), new Date().toISOString(), "utf8");
}

function toolResult(structuredContent, text) {
  return { content: [{ type: "text", text }], structuredContent };
}

function toolError(structuredContent, text) {
  return { ...toolResult(structuredContent, text), isError: true };
}

const taskSchema = {
  type: "object",
  additionalProperties: false,
  required: ["task_number", "workspace", "status", "client", "provider", "profile", "updated_at"],
  properties: {
    task_number: { type: "integer", minimum: 1 },
    workspace: { type: "string" },
    status: { type: "string" },
    client: { type: "string" },
    provider: { type: "string" },
    profile: { type: "string" },
    updated_at: { type: "string" },
  },
};

const emptyInputSchema = { type: "object", properties: {}, additionalProperties: false };
const quotaGuardOutputSchema = {
  type: "object",
  additionalProperties: false,
  required: ["state", "event", "should_alert", "five_hour_remaining_percent", "weekly_remaining_percent", "observed_at", "instruction"],
  properties: {
    state: { type: "string", enum: ["disabled", "unavailable", "clear", "prepare_handoff", "handoff_now"] },
    event: { type: "string", enum: ["disabled", "unavailable", "clear", "entered_prepare", "entered_handoff", "escalated_handoff", "deescalated", "recovered", "steady"] },
    should_alert: { type: "boolean" },
    five_hour_remaining_percent: { anyOf: [{ type: "number", minimum: 0, maximum: 100 }, { type: "null" }] },
    weekly_remaining_percent: { anyOf: [{ type: "number", minimum: 0, maximum: 100 }, { type: "null" }] },
    observed_at: { type: "string" },
    instruction: { type: "string" },
  },
};
const controlOutputSchema = {
  type: "object",
  additionalProperties: false,
  required: ["ok", "action", "message"],
  properties: { ok: { type: "boolean" }, action: { type: "string" }, message: { type: "string" } },
};

function controlTool(name, title, description, action, idempotent = true) {
  return {
    name,
    title,
    description,
    inputSchema: emptyInputSchema,
    outputSchema: controlOutputSchema,
    annotations: { title, readOnlyHint: false, destructiveHint: false, idempotentHint: idempotent, openWorldHint: false },
    execution: { taskSupport: "forbidden" },
    _action: action,
  };
}

const toolDefinitions = [
  controlTool("monitor_hud_open_settings", "Open HUD settings", "Open the local Codex Monitor HUD settings window.", "open_settings"),
  controlTool("monitor_hud_show", "Show Monitor HUD", "Show or restart the local Codex Monitor HUD.", "show"),
  controlTool("monitor_hud_hide", "Hide Monitor HUD", "Hide the local Codex Monitor HUD without changing settings.", "hide"),
  controlTool("monitor_hud_pause", "Toggle HUD pause", "Toggle live-update pause in the local Codex Monitor HUD.", "pause", false),
  controlTool("monitor_hud_disable_click_through", "Disable HUD click-through", "Emergency recovery: disable mouse click-through so the HUD can be clicked again.", "disable_click_through"),
  {
    name: "monitor_hud_status",
    title: "Read Monitor HUD status",
    description: "Read privacy-safe HUD health, enabled monitoring sources, and active task routing metadata. No credentials, prompts, replies, logs, or profile paths are returned.",
    inputSchema: emptyInputSchema,
    outputSchema: {
      type: "object",
      additionalProperties: false,
      required: ["ok", "hud_state", "heartbeat_fresh", "heartbeat_age_seconds", "monitoring_sources", "registry_version", "registry_generated_at", "active_task_count", "active_tasks"],
      properties: {
        ok: { type: "boolean" },
        hud_state: { type: "string", enum: ["running", "not_detected"] },
        heartbeat_fresh: { type: "boolean" },
        heartbeat_age_seconds: { anyOf: [{ type: "number", minimum: 0 }, { type: "null" }] },
        monitoring_sources: {
          type: "object", additionalProperties: false,
          required: ["desktop_openai", "default_cli", "deepseek_cli"],
          properties: { desktop_openai: { type: "boolean" }, default_cli: { type: "boolean" }, deepseek_cli: { type: "boolean" } },
        },
        registry_version: { type: "integer", minimum: 0 },
        registry_generated_at: { type: "string" },
        active_task_count: { type: "integer", minimum: 0 },
        active_tasks: { type: "array", maxItems: 64, items: taskSchema },
      },
    },
    annotations: { title: "Read Monitor HUD status", readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    execution: { taskSupport: "forbidden" },
  },
  {
    name: "monitor_hud_quota_guard",
    title: "Read Codex allowance handoff guard",
    description: "Read privacy-safe locally observed 5-hour and weekly Codex allowance plus a conservative handoff advisory. Call at natural checkpoints and before expensive work when the user wants capacity protection. This tool cannot interrupt a running turn; if it returns prepare_handoff or handoff_now, create a recoverable handoff before expanding work.",
    inputSchema: emptyInputSchema,
    outputSchema: quotaGuardOutputSchema,
    annotations: { title: "Read Codex allowance handoff guard", readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    execution: { taskSupport: "forbidden" },
  },
  {
    name: "monitor_hud_notification_capabilities",
    title: "Read HUD notice permission",
    description: "Read the current opt-in notice permission and privacy-safe task numbers. Call before the first proactive notice in every task; do not rely on another conversation's memory.",
    inputSchema: emptyInputSchema,
    outputSchema: {
      type: "object", additionalProperties: false,
      required: ["enabled", "permission", "identity", "targeting", "limits", "active_tasks"],
      properties: {
        enabled: { type: "boolean" },
        permission: { type: "string", enum: ["off", "text", "expressive"] },
        identity: { type: "string" }, targeting: { type: "string" },
        limits: {
          type: "object", additionalProperties: false,
          required: ["plain_text_characters", "animation_layers", "no_links_or_rich_text", "no_executable_code"],
          properties: {
            plain_text_characters: { type: "integer" }, animation_layers: { type: "integer" },
            no_links_or_rich_text: { type: "boolean" }, no_executable_code: { type: "boolean" },
          },
        },
        active_tasks: { type: "array", maxItems: 64, items: taskSchema },
      },
    },
    annotations: { title: "Read HUD notice permission", readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    execution: { taskSupport: "forbidden" },
  },
  {
    name: "monitor_hud_notify",
    title: "Send a targeted HUD notice",
    description: "Opt-in: show a short CODEX-labeled notice on one matching HUD task. Check capabilities first and match task_number, client, provider and profile. Expressive permission allows a bounded animation recipe.",
    inputSchema: {
      type: "object", required: ["message"], additionalProperties: false,
      properties: {
        message: { type: "string", minLength: 1, maxLength: 160, description: "One or two short plain-text sentences asking the user to return." },
        task_number: { type: "integer", minimum: 1, description: "Visible HUD task number from monitor_hud_notification_capabilities." },
        animation: {
          type: "object", additionalProperties: false,
          properties: {
            layers: { type: "array", maxItems: 4, items: { type: "string", enum: ["glow", "pulse", "breathe", "flow"] } },
            color: { type: "string", pattern: "^#[0-9A-Fa-f]{8}$" },
            intensity: { type: "number", minimum: 0.2, maximum: 1 },
            tempo_ms: { type: "integer", minimum: 240, maximum: 2500 },
            cycles: { type: "integer", minimum: 1, maximum: 8 },
            glow_radius: { type: "number", minimum: 8, maximum: 60 },
            scale: { type: "number", minimum: 1, maximum: 1.08 },
            direction: { type: "string", enum: ["left-to-right", "right-to-left"] },
          },
        },
      },
    },
    outputSchema: {
      type: "object", additionalProperties: false,
      required: ["ok", "queued", "permission", "target_task_number", "message"],
      properties: {
        ok: { type: "boolean" }, queued: { type: "boolean" }, permission: { type: "string", enum: ["off", "text", "expressive"] },
        target_task_number: { anyOf: [{ type: "integer", minimum: 1 }, { type: "null" }] }, message: { type: "string" },
      },
    },
    annotations: { title: "Send a targeted HUD notice", readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
    execution: { taskSupport: "forbidden" },
  },
];

const tools = toolDefinitions.map(({ _action, ...tool }) => tool);
const controlActions = new Map(toolDefinitions.filter((tool) => tool._action).map((tool) => [tool.name, tool._action]));

function controlResult(action, message) {
  return toolResult({ ok: true, action, message }, message);
}

function negotiateProtocol(requested) {
  return SUPPORTED_PROTOCOL_VERSIONS.includes(requested) ? requested : SUPPORTED_PROTOCOL_VERSIONS[0];
}

function handleToolCall(id, params) {
  const name = params?.name;
  const args = params?.arguments && typeof params.arguments === "object" && !Array.isArray(params.arguments) ? params.arguments : {};
  if (controlActions.has(name)) {
    const action = controlActions.get(name);
    if (action === "open_settings") {
      startHud(true); signal("open-settings");
      return { jsonrpc: "2.0", id, result: controlResult(action, "Codex Monitor HUD settings opened locally.") };
    }
    if (action === "show") {
      startHud(false); signal("show");
      return { jsonrpc: "2.0", id, result: controlResult(action, "Codex Monitor HUD is visible.") };
    }
    if (action === "hide") {
      signal("hide");
      return { jsonrpc: "2.0", id, result: controlResult(action, "Codex Monitor HUD hidden.") };
    }
    if (action === "pause") {
      signal("pause");
      return { jsonrpc: "2.0", id, result: controlResult(action, "Codex Monitor HUD pause toggled.") };
    }
    startHud(false); signal("passthrough-off");
    return { jsonrpc: "2.0", id, result: controlResult(action, "Codex Monitor HUD mouse click-through disabled.") };
  }
  if (name === "monitor_hud_status") {
    const status = hudStatus();
    return { jsonrpc: "2.0", id, result: toolResult(status, JSON.stringify(status, null, 2)) };
  }
  if (name === "monitor_hud_quota_guard") {
    const guard = quotaGuard();
    return { jsonrpc: "2.0", id, result: toolResult(guard, JSON.stringify(guard, null, 2)) };
  }
  if (name === "monitor_hud_notification_capabilities") {
    const capabilities = notificationCapabilities();
    return { jsonrpc: "2.0", id, result: toolResult(capabilities, JSON.stringify(capabilities, null, 2)) };
  }
  if (name === "monitor_hud_notify") {
    const permission = notificationPermission();
    const taskNumber = Number.isInteger(args.task_number) ? args.task_number : null;
    if (permission === "off") {
      const result = { ok: false, queued: false, permission, target_task_number: taskNumber, message: "Codex proactive notices are disabled in HUD settings." };
      return { jsonrpc: "2.0", id, result: toolError(result, result.message) };
    }
    const message = cleanNoticeText(args.message);
    if (!message) {
      const result = { ok: false, queued: false, permission, target_task_number: taskNumber, message: "A non-empty plain-text message is required." };
      return { jsonrpc: "2.0", id, result: toolError(result, result.message) };
    }
    const registry = readTaskRegistry();
    if (registry.tasks.length === 0) {
      const result = { ok: false, queued: false, permission, target_task_number: taskNumber, message: "No visible HUD task is available for this notice." };
      return { jsonrpc: "2.0", id, result: toolError(result, result.message) };
    }
    if (taskNumber !== null && !registry.tasks.some((task) => task.task_number === taskNumber)) {
      const result = { ok: false, queued: false, permission, target_task_number: taskNumber, message: `HUD task #${taskNumber} is not currently visible; refresh capabilities before notifying.` };
      return { jsonrpc: "2.0", id, result: toolError(result, result.message) };
    }
    const payload = {
      version: 2,
      created_at: new Date().toISOString(),
      source: "codex-mcp",
      message,
      task_number: taskNumber,
      animation: permission === "expressive" ? boundedAnimation(args.animation) : null,
    };
    const noticeName = `notice-${Date.now()}-${process.pid}-${++noticeSequence}.json`;
    const noticePath = join(notificationsRoot, noticeName);
    const temporaryNoticePath = `${noticePath}.tmp`;
    try {
      writeFileSync(temporaryNoticePath, JSON.stringify(payload), "utf8");
      renameSync(temporaryNoticePath, noticePath);
    } finally {
      try { rmSync(temporaryNoticePath, { force: true }); } catch {}
    }
    if (process.env.CODEX_MONITOR_HUD_DISABLE_AUTO_START !== "1") startHud(false);
    const result = { ok: true, queued: true, permission, target_task_number: taskNumber, message: "Codex Monitor HUD notice queued." };
    return { jsonrpc: "2.0", id, result: toolResult(result, result.message) };
  }
  return { jsonrpc: "2.0", id, error: { code: -32602, message: `Unknown tool: ${name}` } };
}

function handle(request) {
  const { id, method, params = {} } = request;
  if (method === "initialize") {
    return {
      jsonrpc: "2.0",
      id,
      result: {
        protocolVersion: negotiateProtocol(params.protocolVersion),
        capabilities: { tools: { listChanged: false } },
        serverInfo: {
          name: "codex-monitor-hud",
          title: "Codex Monitor HUD",
          version: SERVER_VERSION,
          description: "Local real-time monitoring and opt-in task notices for Codex Desktop and CLI.",
          websiteUrl: "https://github.com/LH-03/codex-monitor-hud",
        },
        instructions: SERVER_INSTRUCTIONS,
      },
    };
  }
  if (method === "notifications/initialized" || method === "notifications/cancelled") return null;
  if (method === "ping") return { jsonrpc: "2.0", id, result: {} };
  if (method === "tools/list") return { jsonrpc: "2.0", id, result: { tools } };
  if (method === "prompts/list") return { jsonrpc: "2.0", id, result: { prompts: [] } };
  if (method === "resources/list") return { jsonrpc: "2.0", id, result: { resources: [] } };
  if (method === "tools/call") return handleToolCall(id, params);
  if (id === undefined) return null;
  return { jsonrpc: "2.0", id, error: { code: -32601, message: `Method not found: ${method}` } };
}

if (process.env.CODEX_MONITOR_HUD_DISABLE_AUTO_START !== "1") startHud(false);
const hudMonitorTimer = setInterval(maintainHud, 5000);
hudMonitorTimer.unref();

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
  clearInterval(hudMonitorTimer);
  try { rmSync(hostHeartbeat, { force: true }); } catch {}
  process.exit(0);
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
process.stdin.on("end", shutdown);
