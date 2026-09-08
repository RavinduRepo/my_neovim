import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
const CWD = "/home/ravindu/Documents/My_Projects/dap-sandbox/php";
const c = new Client({ name: "t", version: "0" }, { capabilities: {} });
await c.connect(new StdioClientTransport({
  command: "node", args: ["/home/ravindu/.config/nvim/claude-dap-bridge/index.js"], cwd: CWD,
}));
const call = async (name, args = {}) =>
  JSON.parse((await c.callTool({ name, arguments: args })).content[0].text);
const where = (d) => {
  const ctx = d.context || d;
  const f = ctx.frame;
  return f ? `${f.name} @ ${f.source_name}:${f.line}` : (ctx.message || JSON.stringify(d).slice(0, 80));
};

console.log("bp   ", (await call("dap_set_breakpoint", { file: `${CWD}/src/Pricing.php`, line: 27 })).ok);
console.log("start", where(await call("dap_launch", { name: "Sandbox: PHP run.php" })));
console.log("$subtotal =", (await call("dap_eval", { expression: "$subtotal" })).result);
console.log("$tier     =", (await call("dap_eval", { expression: "$tier" })).result);
console.log("step ", where(await call("dap_control", { action: "step_over" })));
console.log("step ", where(await call("dap_control", { action: "step_over" })));
console.log("out  ", where(await call("dap_control", { action: "step_out" })));
console.log("$rate     =", (await call("dap_eval", { expression: "$rate" })).result || "(out of scope)");
console.log("end  ", where(await call("dap_control", { action: "terminate" })));
await c.close(); process.exit(0);
