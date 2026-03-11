# REAPER MCP Adapter Guide

## Overview
- REAPER access in this workspace uses `python-reapy` plus a local MCP adapter.
- REAPER exposes its distant API through the REAPER web interface, typically on `127.0.0.1:2307`.
- Codex connects to the local MCP adapter at `http://127.0.0.1:9881/mcp`.

## Preflight
- Before doing REAPER work, confirm REAPER is running and `reapy` can reach it:
  `python -c "import reapy; print(reapy.get_reaper_version())"`
- If that command fails, run the one-time setup:
  `python -c "import reapy; reapy.configure_reaper()"`
- After `configure_reaper()`, restart REAPER before retrying the `reapy` version probe.

## Starting And Stopping
- If REAPER is running but the MCP adapter is not, start the adapter with:
  `powershell -ExecutionPolicy Bypass -File .\scripts\tools\reaper\start_reaper_mcp_adapter.ps1`
- To stop the adapter:
  `powershell -ExecutionPolicy Bypass -File .\scripts\tools\reaper\stop_reaper_mcp_adapter.ps1`
- The start and stop scripts are idempotent.
- If the adapter is restarted during the session and MCP calls begin timing out, restart the Codex session so it reconnects cleanly.

## Tool Order
1. `reaper_status` to confirm adapter and `reapy` connectivity.
2. `get_reaper_version` and `get_current_project` to identify the active session.
3. `list_tracks` and `get_track_info` for read-only inspection.
4. `add_track` and `run_action` for common structured edits.
5. `execute_reapy_code` for targeted Python operations when the higher-level tools are not enough.

## Working Rules
- Prefer concrete REAPER changes through MCP tools when possible.
- Prefer `reapy` and REAPER action IDs over raw Lua text where possible.
- When generating REAPER automation code, keep scripts modular, readable, and safe to rerun.
