import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
const CWD = "/home/ravindu/Documents/My_Projects/dap-sandbox/react";
const c = new Client({ name: "t", version: "0" }, { capabilities: {} });
await c.connect(new StdioClientTransport({
  command: "node", args: ["/home/ravindu/.config/nvim/claude-dap-bridge/index.js"], cwd: CWD,
}));
const call = async (n, a = {}) => JSON.parse((await c.callTool({ name: n, arguments: a })).content[0].text);
const where = (d) => { const ctx = d.context || d; const f = ctx.frame;
  return f ? `${f.name || "(anon)"} @ ${f.source_name}:${f.line}` : (ctx.message || JSON.stringify(d).slice(0,200)); };

console.log("bp   ", (await call("dap_set_breakpoint", { file: `${CWD}/src/pricing.js`, line: 18 })).ok);
console.log("start", where(await call("dap_launch", {
  name: "Sandbox: React dev server",
  overrides: { runtimeArgs: ["--headless=new", "--no-sandbox", "--disable-gpu"] },
  wait_ms: 25000,
})));
console.log("tier      =", (await call("dap_eval", { expression: "tier" })).result);
console.log("subtotal  =", (await call("dap_eval", { expression: "subtotalAmount" })).result);
console.log("step ", where(await call("dap_control", { action: "step_over" })));
const ctx = await call("dap_context", { source_context: 2 });
console.log("stack:", (ctx.stack || []).slice(0, 4).map((f) => `${f.name || "(anon)"}@${f.source_name}:${f.line}`).join("  <-  "));
await call("dap_control", { action: "terminate" });
await c.close(); process.exit(0);
