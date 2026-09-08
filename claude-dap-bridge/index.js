#!/usr/bin/env node
// MCP server that exposes a live nvim-dap session to Claude Code.
//
//   Claude Code --stdio--> this bridge --msgpack RPC--> Neovim --> nvim-dap
//
// It holds no debugger state of its own: every tool is a thin call into
// lua/claude-dap/api.lua, so the user stepping by hand and the agent stepping
// through a tool are the same session with one breakpoint list.

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { attach } from "neovim";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

// ---------------------------------------------------------------- discovery --

function cacheDir() {
  if (process.env.CLAUDE_DAP_CACHE) return process.env.CLAUDE_DAP_CACHE;
  if (process.env.XDG_CACHE_HOME) return path.join(process.env.XDG_CACHE_HOME, "nvim");
  if (process.platform === "win32") {
    return path.join(process.env.LOCALAPPDATA || os.tmpdir(), "nvim-data", "cache");
  }
  return path.join(os.homedir(), ".cache", "nvim");
}

const REGISTRY = path.join(cacheDir(), "claude-dap", "sessions.json");

function readRegistry() {
  try {
    return JSON.parse(fs.readFileSync(REGISTRY, "utf8"));
  } catch {
    return {};
  }
}

function isAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

/**
 * Pick the Neovim instance to talk to. Preference order:
 *   1. CLAUDE_DAP_SOCKET / NVIM (explicit)
 *   2. the instance whose cwd contains ours, deepest match first
 *   3. the most recently updated live instance
 */
function findSocket() {
  if (process.env.CLAUDE_DAP_SOCKET) return process.env.CLAUDE_DAP_SOCKET;

  const entries = Object.values(readRegistry()).filter(
    (e) => e && e.socket && (!e.pid || isAlive(e.pid))
  );
  if (entries.length === 0) return process.env.NVIM || null;

  const cwd = path.resolve(process.cwd());
  const containing = entries
    .filter((e) => cwd === e.cwd || cwd.startsWith(e.cwd + path.sep))
    .sort((a, b) => b.cwd.length - a.cwd.length);
  if (containing.length) return containing[0].socket;

  entries.sort((a, b) => (b.updated || 0) - (a.updated || 0));
  return entries[0].socket;
}

let nvim = null;
let socketPath = null;

async function connect() {
  if (nvim) {
    try {
      await nvim.call("nvim_get_mode", []);
      return nvim;
    } catch {
      nvim = null; // stale connection; fall through and reconnect
    }
  }
  socketPath = findSocket();
  if (!socketPath) {
    throw new Error(
      "No Neovim instance found. Start Neovim with the claude-dap plugin loaded " +
        `(registry: ${REGISTRY}), or set CLAUDE_DAP_SOCKET.`
    );
  }
  nvim = await attach({ socket: socketPath });
  return nvim;
}

/** Call a function in lua/claude-dap/api.lua and return its table. */
async function callApi(fn, args = {}) {
  const client = await connect();
  return client.lua(
    `local a = {...}
     local ok, res = pcall(function()
       return require("claude-dap.api")[a[1]](a[2])
     end)
     if ok then return res end
     return { ok = false, error = tostring(res) }`,
    [fn, args]
  );
}

// -------------------------------------------------------------------- tools --

const tools = [
  {
    name: "dap_context",
    description:
      "Read the CURRENT debugger state: whether a session is running, where it is paused " +
      "(file, line, function), the full call stack, local variables with values, source " +
      "lines around the stop point, every breakpoint, and where the user's cursor is. " +
      "ALWAYS call this first before answering any question about the running program — " +
      "the user may have stepped or moved since your last call, so never rely on remembered state.",
    inputSchema: {
      type: "object",
      properties: {
        source_context: {
          type: "number",
          description: "Lines of source to include either side of the stop point (default 12).",
        },
        max_children: {
          type: "number",
          description: "Cap on variables expanded, to keep the response small (default 60).",
        },
      },
    },
  },
  {
    name: "dap_breakpoints",
    description:
      "List every breakpoint in the session. The user sets these with <leader>db and you set " +
      "them with dap_set_breakpoint; both land in the same list, so this shows all of them.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "dap_set_breakpoint",
    description:
      "Place a breakpoint. Works before or during a session — mid-session breakpoints are sent " +
      "to the adapter immediately. The mark appears in the user's gutter.",
    inputSchema: {
      type: "object",
      properties: {
        file: { type: "string", description: "Absolute path to the source file." },
        line: { type: "number", description: "1-indexed line number." },
        condition: {
          type: "string",
          description: "Optional expression; the program only stops when it is true (e.g. \"i == 42\").",
        },
        hit_condition: { type: "string", description: "Optional hit count expression, e.g. \">5\"." },
        log_message: {
          type: "string",
          description:
            "Optional logpoint message; when set the program logs and continues instead of stopping. " +
            "Use {expr} to interpolate.",
        },
      },
      required: ["file", "line"],
    },
  },
  {
    name: "dap_remove_breakpoint",
    description: "Remove one breakpoint by file and line.",
    inputSchema: {
      type: "object",
      properties: { file: { type: "string" }, line: { type: "number" } },
      required: ["file", "line"],
    },
  },
  {
    name: "dap_clear_breakpoints",
    description: "Remove all breakpoints. Ask the user before doing this — some may be theirs.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "dap_eval",
    description:
      "Evaluate an expression in the paused frame and return its value, with children expanded " +
      "for structs/objects. Use this instead of guessing what a variable holds. Only works while paused.",
    inputSchema: {
      type: "object",
      properties: {
        expression: { type: "string", description: "Expression in the debuggee's language." },
        frame_id: {
          type: "number",
          description: "Stack frame to evaluate in; defaults to the current frame.",
        },
      },
      required: ["expression"],
    },
  },
  {
    name: "dap_control",
    description:
      "ADVANCE THE PROGRAM. This changes execution state, so only call it when the user asks to " +
      "move on ('next', 'continue', 'step into that'). To merely show the user some code without " +
      "running anything, use dap_goto instead. Returns the new context after the step.",
    inputSchema: {
      type: "object",
      properties: {
        action: {
          type: "string",
          enum: [
            "continue",
            "step_over",
            "step_into",
            "step_out",
            "step_back",
            "run_to_cursor",
            "pause",
            "terminate",
            "restart",
            "disconnect",
          ],
          description: "continue also starts a session if none is running.",
        },
      },
      required: ["action"],
    },
  },
  {
    name: "dap_launch",
    description:
      "Start a debug session from a named launch configuration (see dap_configurations). " +
      "Configurations that prompt interactively need their values passed in `overrides`.",
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string", description: "Configuration name, e.g. 'Launch executable'." },
        filetype: { type: "string", description: "Restrict the lookup to one filetype." },
        overrides: {
          type: "object",
          description: "Fields merged over the configuration, e.g. {\"program\": \"/path/to/binary\"}.",
        },
        config: {
          type: "object",
          description: "A complete raw DAP configuration, used instead of `name`.",
        },
      },
    },
  },
  {
    name: "dap_configurations",
    description: "List the available launch configurations per filetype.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "dap_goto",
    description:
      "Move the USER'S CURSOR to a file and line and centre it on screen, so they are looking at " +
      "the code you are explaining. Read-only: this never executes anything. Use it constantly " +
      "when walking someone through a codebase.",
    inputSchema: {
      type: "object",
      properties: {
        file: { type: "string" },
        line: { type: "number" },
        column: { type: "number" },
        focus: {
          type: "boolean",
          description: "Move keyboard focus to that window too (default true).",
        },
      },
      required: ["file"],
    },
  },
  {
    name: "dap_highlight",
    description:
      "Highlight a line range in the user's editor with an optional inline note, to point at the " +
      "exact code you are discussing. Call with clear=true to remove all highlights.",
    inputSchema: {
      type: "object",
      properties: {
        file: { type: "string" },
        start_line: { type: "number" },
        end_line: { type: "number", description: "Defaults to start_line." },
        note: { type: "string", description: "Short label shown at the end of the first line." },
        hl_group: { type: "string", description: "Highlight group (default DiffAdd)." },
        clear: { type: "boolean", description: "Clear all highlights instead of adding one." },
      },
    },
  },
  {
    name: "dap_source",
    description:
      "Read numbered source lines from a file as the editor sees them, including unsaved buffer " +
      "changes. Prefer this over the plain file read when discussing line numbers with the user.",
    inputSchema: {
      type: "object",
      properties: {
        file: { type: "string" },
        start_line: { type: "number" },
        end_line: { type: "number" },
      },
      required: ["file"],
    },
  },
  {
    name: "dap_select_frame",
    description:
      "Switch to a different stack frame (from dap_context's stack) so variables and evaluation " +
      "resolve there, and jump the user's cursor to it. Use this to walk back up a call chain.",
    inputSchema: {
      type: "object",
      properties: {
        frame_id: { type: "number", description: "Frame id from dap_context.stack." },
        index: { type: "number", description: "1-based position in the stack, as an alternative." },
      },
    },
  },
  {
    name: "dap_status",
    description: "Cheap health check: which Neovim, its cwd, whether a session is live and paused.",
    inputSchema: { type: "object", properties: {} },
  },
];

const HANDLERS = {
  dap_context: "context",
  dap_breakpoints: "breakpoints",
  dap_set_breakpoint: "set_breakpoint",
  dap_remove_breakpoint: "remove_breakpoint",
  dap_clear_breakpoints: "clear_breakpoints",
  dap_eval: "eval",
  dap_control: "control",
  dap_launch: "launch",
  dap_configurations: "configurations",
  dap_goto: "goto_location",
  dap_highlight: "highlight",
  dap_source: "source",
  dap_select_frame: "select_frame",
  dap_status: "status",
};

// ------------------------------------------------------------------- server --

// Sent to the client at connect. This is how the plugin ships its own agent
// instructions: they travel with the repo, so a new machine needs no
// CLAUDE.md and nothing copied into ~/.claude.
const INSTRUCTIONS = `These tools drive a live Neovim debugger (nvim-dap) that the user is
watching. You and the user share one session.

How to respond while these tools are available:
- Keep answers short and conversational. No preamble, no recap, no essays.
- A few sentences or a small table beats paragraphs.
- Don't survey options the user didn't ask for; recommend one and say why.
- Ask one question at a time, at the end.

How to use the debugger:
- Call dap_context before answering ANY question about the running program.
  Never answer from remembered state: the user may have stepped, switched
  frames, or moved the cursor since your last call. It is cheap; re-read it.
- Breakpoints are shared. The user sets them with <leader>db, you set them with
  dap_set_breakpoint, and both land in the same list. Never call
  dap_clear_breakpoints without asking - some are theirs.
- dap_goto moves the user's cursor without executing anything. Use it freely to
  show them the code you are talking about.
- dap_control ADVANCES the program. Only use it when the user asks to move on.
- dap_highlight marks the exact lines under discussion; clear them when done.
- At a stop point, say which frame you are in, which values actually matter,
  and why execution landed here. Don't restate source the user can already see.
- When teaching a flow, prefer walking the call stack with dap_select_frame and
  dap_goto over dumping an explanation of the whole file.`;

const server = new Server(
  { name: "claude-dap", version: "0.1.0" },
  { capabilities: { tools: {} }, instructions: INSTRUCTIONS }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools }));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const fn = HANDLERS[request.params.name];
  if (!fn) {
    return {
      isError: true,
      content: [{ type: "text", text: `Unknown tool: ${request.params.name}` }],
    };
  }
  try {
    const result = await callApi(fn, request.params.arguments || {});
    return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
  } catch (err) {
    return {
      isError: true,
      content: [
        {
          type: "text",
          text: `claude-dap bridge error (socket: ${socketPath || "none"}): ${err.message}`,
        },
      ],
    };
  }
});

await server.connect(new StdioServerTransport());
