import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const BRIDGE = "/home/ravindu/.config/nvim/claude-dap-bridge/index.js";
const CWD = "/home/ravindu/Documents/My_Projects/dap-sandbox/cpp";

const client = new Client({ name: "test", version: "0" }, { capabilities: {} });
await client.connect(new StdioClientTransport({ command: "node", args: [BRIDGE], cwd: CWD }));

const { tools } = await client.listTools();
console.log("TOOLS:", tools.map((t) => t.name).join(", "), "\n");

async function call(name, args = {}) {
  const r = await client.callTool({ name, arguments: args });
  const text = r.content[0].text;
  let parsed;
  try { parsed = JSON.parse(text); } catch { parsed = text; }
  console.log(`### ${name}(${JSON.stringify(args)})`);
  console.log(typeof parsed === "string" ? parsed : JSON.stringify(parsed).slice(0, 900));
  console.log();
  return parsed;
}

await call("dap_status");
await call("dap_set_breakpoint", { file: `${CWD}/src/pricing.cpp`, line: 19 });
await call("dap_launch", { name: "Sandbox: C++ pricing" });
const ctx = await call("dap_context", { source_context: 3 });
await call("dap_eval", { expression: "subtotal_amount" });
await call("dap_eval", { expression: "tier" });
await call("dap_control", { action: "step_over" });
await call("dap_goto", { file: `${CWD}/src/main.cpp`, line: 14 });
await call("dap_highlight", { file: `${CWD}/src/pricing.cpp`, start_line: 19, end_line: 21, note: "volume bonus" });
await call("dap_control", { action: "terminate" });
await client.close();
process.exit(0);
