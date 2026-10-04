// Runs the real upstream stdio MCP server, without pairing a remote device.
import assert from 'node:assert/strict';
import { Client } from '/opt/rdc/node_modules/@modelcontextprotocol/sdk/dist/esm/client/index.js';
import { StdioClientTransport } from '/opt/rdc/node_modules/@modelcontextprotocol/sdk/dist/esm/client/stdio.js';
const transport = new StdioClientTransport({
  command: '/opt/rdc/node_modules/.bin/desktop-commander',
  args: [], env: process.env, stderr: 'pipe',
});
const client = new Client({name: 'host-admin-smoke', version: '0.1.0'});
try {
  await client.connect(transport);
  transport.stderr?.on('data', () => {});
  const {tools} = await client.listTools();
  assert(tools.some(t => t.name === 'start_process'));
  assert(tools.some(t => t.name === 'read_file'));
  const result = await client.callTool({name: 'start_process', arguments: {
    command: 'hostsh id -u', timeout_ms: 1000,
  }});
  assert(!result.isError, JSON.stringify(result));
  const text = result.content.filter(c => c.type === 'text').map(c => c.text).join('\n');
  assert(/(?:^|\n)0(?:\n|$)/.test(text), 'Host root command did not return UID 0');
  console.log(`PASS: actual Desktop Commander MCP lists ${tools.length} tools and executes hostsh as host root`);
} finally {
  await client.close();
}
