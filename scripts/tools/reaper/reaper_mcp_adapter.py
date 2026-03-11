from __future__ import annotations

import argparse
import io
import json
import logging
from contextlib import redirect_stdout
from typing import Any

from mcp.server.fastmcp import FastMCP
import reapy
from reapy import reascript_api as RPR


LOGGER = logging.getLogger("reaper_mcp_adapter")
DEFAULT_ADAPTER_HOST = "127.0.0.1"
DEFAULT_ADAPTER_PORT = 9881
DEFAULT_REAPER_HOST = "127.0.0.1"
DEFAULT_WEB_INTERFACE_PORT = 2307
DEFAULT_REAPY_SERVER_PORT = 2306
DEFAULT_MOUNT_PATH = "/"
DEFAULT_STREAMABLE_HTTP_PATH = "/mcp"
NATIVE_CAPABILITIES = [
    "get_reaper_version",
    "get_current_project",
    "list_tracks",
    "get_track_info",
    "add_track",
    "run_action",
    "execute_reapy_code",
]


def get_project() -> reapy.Project:
    return reapy.Project()


def get_track_by_index(track_index: int) -> reapy.Track:
    project = get_project()
    if track_index < 0 or track_index >= project.n_tracks:
        raise ValueError(f"Track index {track_index} is out of range.")
    return project.tracks[track_index]


def summarize_track(track: reapy.Track) -> dict[str, Any]:
    with reapy.inside_reaper():
        return {
            "index": track.index,
            "name": track.name,
            "guid": track.GUID,
            "is_selected": track.is_selected,
            "is_muted": track.is_muted,
            "is_solo": track.is_solo,
            "n_items": track.n_items,
            "n_fxs": track.n_fxs,
            "fx_names": [fx.name for fx in track.fxs],
            "n_sends": track.n_sends,
            "n_receives": track.n_receives,
        }


def summarize_project() -> dict[str, Any]:
    project = get_project()
    with reapy.inside_reaper():
        return {
            "name": project.name,
            "path": project.path,
            "n_tracks": project.n_tracks,
            "cursor_position": project.cursor_position,
            "selected_track_names": [track.name for track in project.selected_tracks],
            "selected_item_count": len(project.selected_items),
        }


def perform_action(action_id: int | None = None, command_name: str | None = None) -> dict[str, Any]:
    if action_id is None and not command_name:
        raise ValueError("Provide either action_id or command_name.")

    resolved_action_id = action_id
    if resolved_action_id is None:
        resolved_action_id = reapy.get_command_id(command_name)
        if resolved_action_id is None:
            raise ValueError(f"Unable to resolve command name '{command_name}'.")

    reapy.perform_action(resolved_action_id)
    return {
        "action_id": resolved_action_id,
        "command_name": command_name,
        "performed": True,
    }


def execute_reapy_code(code: str) -> dict[str, Any]:
    namespace: dict[str, Any] = {
        "reapy": reapy,
        "RPR": RPR,
        "project": get_project(),
    }
    capture_buffer = io.StringIO()

    try:
        with redirect_stdout(capture_buffer):
            with reapy.inside_reaper():
                exec(code, namespace)
    except Exception as exc:
        raise RuntimeError(f"Code execution error: {exc}") from exc

    execution_result: dict[str, Any] = {
        "executed": True,
        "result": capture_buffer.getvalue(),
    }
    explicit_result = namespace.get("result")
    if explicit_result is not None:
        try:
            json.dumps(explicit_result)
            execution_result["value"] = explicit_result
        except TypeError:
            execution_result["value_repr"] = repr(explicit_result)
    return execution_result


def build_server(
    adapter_host: str,
    adapter_port: int,
    reaper_host: str,
    web_interface_port: int,
    reapy_server_port: int,
    mount_path: str,
    streamable_http_path: str,
) -> FastMCP:
    server = FastMCP(
        name="reaper",
        instructions=(
            "MCP server for a running REAPER session exposed through python-reapy. "
            "Use these tools to inspect the current project, manage tracks, run actions, or execute reapy code."
        ),
        host=adapter_host,
        port=adapter_port,
        mount_path=mount_path,
        streamable_http_path=streamable_http_path,
        log_level="INFO",
    )

    def adapter_status_payload() -> dict[str, Any]:
        project_summary: dict[str, Any] | None = None
        error_message: str | None = None
        version: str | None = None

        try:
            version = reapy.get_reaper_version()
            project_summary = summarize_project()
        except Exception as exc:
            error_message = str(exc)

        return {
            "adapter": {
                "host": adapter_host,
                "port": adapter_port,
                "mount_path": mount_path,
                "streamable_http_path": streamable_http_path,
            },
            "reaper": {
                "host": reaper_host,
                "web_interface_port": web_interface_port,
                "reapy_server_port": reapy_server_port,
                "reachable": error_message is None,
                "error": error_message,
                "version": version,
            },
            "native_capabilities": NATIVE_CAPABILITIES,
            "project_probe": project_summary,
        }

    @server.resource(
        "reaper://status",
        name="reaper_status",
        description="Adapter status and REAPER connectivity through reapy.",
        mime_type="application/json",
    )
    def reaper_status_resource() -> str:
        return json.dumps(adapter_status_payload(), indent=2)

    @server.resource(
        "reaper://project",
        name="reaper_project",
        description="Current REAPER project summary.",
        mime_type="application/json",
    )
    def reaper_project_resource() -> str:
        return json.dumps(summarize_project(), indent=2)

    @server.resource(
        "reaper://tracks",
        name="reaper_tracks",
        description="Track summaries for the current REAPER project.",
        mime_type="application/json",
    )
    def reaper_tracks_resource() -> str:
        project = get_project()
        with reapy.inside_reaper():
            tracks = [summarize_track(track) for track in project.tracks]
        return json.dumps(tracks, indent=2)

    @server.tool(
        name="reaper_status",
        description="Check whether the adapter can reach the running REAPER session via reapy.",
    )
    def reaper_status_tool() -> dict[str, Any]:
        return adapter_status_payload()

    @server.tool(
        name="list_native_capabilities",
        description="List the native capabilities exposed by this REAPER MCP adapter.",
    )
    def list_native_capabilities() -> list[str]:
        return NATIVE_CAPABILITIES

    @server.tool(
        name="get_reaper_version",
        description="Return the version of the running REAPER instance.",
    )
    def get_reaper_version_tool() -> dict[str, str]:
        return {"version": reapy.get_reaper_version()}

    @server.tool(
        name="get_current_project",
        description="Return summary information for the active REAPER project.",
    )
    def get_current_project() -> dict[str, Any]:
        return summarize_project()

    @server.tool(
        name="list_tracks",
        description="Return track summaries for the active REAPER project.",
    )
    def list_tracks() -> list[dict[str, Any]]:
        project = get_project()
        with reapy.inside_reaper():
            return [summarize_track(track) for track in project.tracks]

    @server.tool(
        name="get_track_info",
        description="Return detailed information for a REAPER track by zero-based index.",
    )
    def get_track_info(track_index: int) -> dict[str, Any]:
        return summarize_track(get_track_by_index(track_index))

    @server.tool(
        name="add_track",
        description="Insert a new track into the active REAPER project.",
    )
    def add_track(name: str = "", index: int | None = None) -> dict[str, Any]:
        project = get_project()
        with reapy.inside_reaper():
            insert_index = project.n_tracks if index is None else index
            track = project.add_track(index=insert_index, name=name)
            return summarize_track(track)

    @server.tool(
        name="run_action",
        description="Run a REAPER action by numeric action ID or command name.",
    )
    def run_action(action_id: int | None = None, command_name: str | None = None) -> dict[str, Any]:
        return perform_action(action_id=action_id, command_name=command_name)

    @server.tool(
        name="execute_reapy_code",
        description="Execute arbitrary Python code with reapy and RPR available against the running REAPER session.",
    )
    def execute_reapy_code_tool(code: str) -> dict[str, Any]:
        return execute_reapy_code(code)

    return server


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Expose a running REAPER session as an MCP HTTP server via python-reapy.")
    parser.add_argument("--host", default=DEFAULT_ADAPTER_HOST, help="Host for the MCP HTTP proxy.")
    parser.add_argument("--port", type=int, default=DEFAULT_ADAPTER_PORT, help="Port for the MCP HTTP proxy.")
    parser.add_argument("--mount-path", default=DEFAULT_MOUNT_PATH, help="ASGI mount path for the MCP server.")
    parser.add_argument(
        "--streamable-http-path",
        default=DEFAULT_STREAMABLE_HTTP_PATH,
        help="Path used for streamable HTTP MCP requests.",
    )
    parser.add_argument("--reaper-host", default=DEFAULT_REAPER_HOST, help="Host for the REAPER web interface.")
    parser.add_argument(
        "--web-interface-port",
        type=int,
        default=DEFAULT_WEB_INTERFACE_PORT,
        help="Port used by REAPER's web interface for reapy discovery.",
    )
    parser.add_argument(
        "--reapy-server-port",
        type=int,
        default=DEFAULT_REAPY_SERVER_PORT,
        help="Default port used by the reapy in-REAPER server.",
    )
    return parser.parse_args()


def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    args = parse_args()
    server = build_server(
        adapter_host=args.host,
        adapter_port=args.port,
        reaper_host=args.reaper_host,
        web_interface_port=args.web_interface_port,
        reapy_server_port=args.reapy_server_port,
        mount_path=args.mount_path,
        streamable_http_path=args.streamable_http_path,
    )
    LOGGER.info(
        "Starting REAPER MCP adapter on http://%s:%s%s and proxying REAPER via reapy on %s:%s",
        args.host,
        args.port,
        args.streamable_http_path,
        args.reaper_host,
        args.web_interface_port,
    )
    server.run(transport="streamable-http")


if __name__ == "__main__":
    main()
