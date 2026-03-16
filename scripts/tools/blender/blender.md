# Blender MCP Adapter Guide

## Overview
- Blender access in this workspace uses a two-step bridge:
  1. The Blender addon runs inside Blender as a raw socket server on `127.0.0.1:9876`.
  2. Codex connects to the local MCP adapter at `http://127.0.0.1:9877/mcp`, which proxies MCP calls to the Blender addon.
- The adapter is configured for stateless JSON HTTP responses rather than SSE session streaming to reduce MCP client handshake issues across fresh agent sessions.

## Preflight
- Before doing Blender work, confirm the Blender addon server is running inside Blender and listening on port `9876`.
- In Blender, the BlenderMCP panel should show `Running on port 9876`.
- From Codex, call `blender_status` and confirm `blender_socket.reachable` is `true`.

## Starting And Stopping
- If the Blender addon is running but the MCP adapter is not, start the adapter with:
  `powershell -ExecutionPolicy Bypass -File .\scripts\tools\blender\start_blender_mcp_adapter.ps1`
- To stop the adapter:
  `powershell -ExecutionPolicy Bypass -File .\scripts\tools\blender\stop_blender_mcp_adapter.ps1`
- The start and stop scripts are idempotent.
- If the adapter is restarted during the session and MCP calls begin timing out, restart the Codex session so it reconnects cleanly.

## Tool Order
1. `blender_status` to confirm adapter and Blender socket connectivity.
2. `list_native_commands` to inspect the available raw Blender command surface when needed.
3. `get_scene_info` and `get_object_info` for read-only inspection.
4. `execute_bpy_code` for targeted `bpy` operations.
5. `call_blender_command` only when a needed addon command is not covered by the higher-level MCP tools.
   Use `params` as an optional object payload.
   Example: `call_blender_command(command_type=\"get_object_info\", params={\"name\": \"cockpit\"})`

## Working Rules
- Prefer making concrete Blender changes through MCP tools when possible.
- When generating Blender Python, keep scripts modular, readable, and safe to rerun.
