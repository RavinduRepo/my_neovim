# nvim-claude-dap

Lets a Claude Code session read and drive a live `nvim-dap` debugging session,
so you can pause inside your own code and ask questions with the agent seeing
exactly the frame you are sitting in.

```
Claude Code CLI ──MCP (stdio)──▶ bridge/index.js ──msgpack RPC──▶ Neovim ──▶ nvim-dap ──▶ adapter
```

The bridge holds no state. Every tool is a call into `lua/claude-dap/api.lua`,
which reads nvim-dap directly — so a breakpoint you set with `<leader>db` and
one the agent sets with a tool are the same breakpoint in the same list, and
either of you can step without confusing the other.

## What the agent can do

| Tool | Effect |
| --- | --- |
| `dap_context` | Where the program is paused, call stack, locals with values, source around the stop point, all breakpoints, your cursor |
| `dap_breakpoints` / `dap_set_breakpoint` / `dap_remove_breakpoint` / `dap_clear_breakpoints` | Read and edit the breakpoint list, including mid-session |
| `dap_eval` | Evaluate an expression in the paused frame |
| `dap_control` | continue / step over / into / out / run to cursor / pause / terminate / restart |
| `dap_launch` / `dap_configurations` | Start a session from a launch configuration |
| `dap_goto` | Move **your cursor** to a file and line — never executes anything |
| `dap_highlight` | Highlight a line range in your editor with an inline note |
| `dap_source` | Read numbered lines as the editor sees them, including unsaved changes |
| `dap_select_frame` | Walk up the call stack; variables and evaluation follow |
| `dap_status` | Health check |

`dap_goto` and `dap_control` are deliberately separate: asking to *look at*
some code can never advance the program.

## Install

Everything lives in this config repo, so cloning it on a new machine brings the
plugin, the bridge, and the agent instructions with it.

On a new device, everything is one command:

    :ClaudeDapInstall

It installs the bridge dependencies (`npm install`), queues the debug adapters
through Mason (codelldb, js-debug-adapter, php-debug-adapter), and registers
the MCP server with the `claude` CLI at user scope. Safe to re-run; it reports
what each step did. Restart any running `claude` session afterwards.

Needs `node`/`npm` and the `claude` CLI on PATH.

`lua/claude-dap/` is on the runtimepath automatically; `lua/plugins/dap.lua`
calls `require("claude-dap").setup()` from nvim-dap's `init`, so the bridge
socket exists from startup while nvim-dap itself stays lazy.

## Agent instructions

The bridge sends its own instructions to Claude Code at connect (the
`INSTRUCTIONS` constant in `claude-dap-bridge/index.js`) covering response
style and the debugger rules. They travel with this repo — no `CLAUDE.md` to
copy onto each machine, nothing in `~/.claude`.

Edit that constant to change how the agent behaves. Per-tool rules belong in
the tool `description` fields instead.

## How Neovim and the bridge find each other

On `setup()` the plugin opens a second RPC socket at
`stdpath("cache")/claude-dap/<hash of cwd>.sock` and records it in
`sessions.json` next to it. The bridge picks the instance whose cwd contains
its own, falling back to the most recently updated live one. Dead entries are
pruned on both sides.

Override with `CLAUDE_DAP_SOCKET` when you want a specific instance. Named
pipes are used on Windows, Unix sockets elsewhere; nothing else is
platform-specific.

## Smoke test

With Neovim open in `~/Documents/My_Projects/dap-sandbox/cpp`:

```sh
cd ~/.config/nvim/claude-dap-bridge && node smoke-test.mjs
```

`php-test.mjs` and `react-test.mjs` do the same for the other two sandboxes;
the React one needs `npm run dev` running in `dap-sandbox/react` first.

Sets a breakpoint, launches the C++ sandbox, evaluates locals, steps, moves the
cursor, and terminates.

## Troubleshooting

- **"No Neovim instance found"** — the plugin has not run `setup()` in the
  Neovim you expect. Check `:ClaudeDapInfo` and `~/.cache/nvim/claude-dap/sessions.json`.
- **Empty variables** — the binary was built without `-g`, or with optimisation
  on. The sandbox `CMakeLists.txt` forces `-g -O0`.
- **PHP never stops** — Xdebug is not loaded (`php -m | grep xdebug`) or its
  `client_port` does not match the configuration's `port` (9003). On Arch the
  `xdebug` package ships `/etc/php/conf.d/xdebug.ini` fully commented out; the
  sandbox config detects that and passes `-dzend_extension=xdebug` itself, so
  no root edit is needed. It skips the flag when Xdebug is already global,
  which would otherwise warn "Cannot load Xdebug - it was already loaded".
- **PHP `step_out` appears to do nothing** on a `return` line — that is Xdebug,
  not the bridge. Use `dap_control` `step_over` or set a breakpoint in the caller.
- **React stops in bundled code** — source maps are off; `vite` dev has them by
  default, production builds need `build.sourcemap = true`.
- **React never launches a browser** — vscode-js-debug looks for Google Chrome
  by name. On a machine with only Chromium or Brave, set `runtimeExecutable` to
  its absolute path (the sandbox config detects this).
