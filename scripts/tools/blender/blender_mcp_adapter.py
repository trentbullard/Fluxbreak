from __future__ import annotations

import argparse
import json
import logging
import socket
from typing import Any

from mcp.server.fastmcp import FastMCP


LOGGER = logging.getLogger("blender_mcp_adapter")
DEFAULT_SOCKET_TIMEOUT = 10.0
DEFAULT_ADAPTER_HOST = "127.0.0.1"
DEFAULT_ADAPTER_PORT = 9877
DEFAULT_BLENDER_HOST = "127.0.0.1"
DEFAULT_BLENDER_PORT = 9876
DEFAULT_MOUNT_PATH = "/"
DEFAULT_STREAMABLE_HTTP_PATH = "/mcp"
NATIVE_COMMANDS = [
    "get_scene_info",
    "get_object_info",
    "get_viewport_screenshot",
    "execute_code",
    "get_polyhaven_status",
    "get_hyper3d_status",
    "get_sketchfab_status",
    "get_hunyuan3d_status",
    "get_polyhaven_categories",
    "search_polyhaven_assets",
    "download_polyhaven_asset",
    "set_texture",
    "create_rodin_job",
    "poll_rodin_job_status",
    "import_generated_asset",
    "search_sketchfab_models",
    "download_sketchfab_model",
    "create_hunyuan_job",
    "poll_hunyuan_job_status",
    "import_generated_asset_hunyuan",
]


class BlenderSocketClient:
    def __init__(self, host: str, port: int, timeout_seconds: float = DEFAULT_SOCKET_TIMEOUT) -> None:
        self._host = host
        self._port = port
        self._timeout_seconds = timeout_seconds

    def send_command(self, command_type: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        payload = {
            "type": command_type,
            "params": params or {},
        }
        payload_bytes = json.dumps(payload).encode("utf-8")
        decoder = json.JSONDecoder()
        buffer = ""

        with socket.create_connection((self._host, self._port), timeout=self._timeout_seconds) as client:
            client.settimeout(self._timeout_seconds)
            client.sendall(payload_bytes)

            while True:
                data = client.recv(8192)
                if not data:
                    break

                buffer += data.decode("utf-8")
                try:
                    response, _ = decoder.raw_decode(buffer)
                    if not isinstance(response, dict):
                        raise RuntimeError("Blender returned a non-dictionary response.")
                    return response
                except json.JSONDecodeError:
                    continue

        raise RuntimeError("Blender closed the socket before returning a complete JSON response.")


def parse_params_json(params_json: str | None) -> dict[str, Any]:
    if not params_json:
        return {}

    try:
        parsed = json.loads(params_json)
    except json.JSONDecodeError as exc:
        raise ValueError(f"params_json must be valid JSON: {exc}") from exc

    if not isinstance(parsed, dict):
        raise ValueError("params_json must decode to a JSON object.")

    return parsed


def build_server(
    adapter_host: str,
    adapter_port: int,
    blender_host: str,
    blender_port: int,
    socket_timeout_seconds: float,
    mount_path: str,
    streamable_http_path: str,
) -> FastMCP:
    client = BlenderSocketClient(
        host=blender_host,
        port=blender_port,
        timeout_seconds=socket_timeout_seconds,
    )
    server = FastMCP(
        name="blender",
        instructions=(
            "Proxy MCP server for a running BlenderMCP addon instance. "
            "Use the tools to inspect the current Blender session or execute bpy code."
        ),
        host=adapter_host,
        port=adapter_port,
        mount_path=mount_path,
        streamable_http_path=streamable_http_path,
        log_level="INFO",
    )

    def call_blender(command_type: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        LOGGER.info("Calling Blender command '%s'", command_type)
        response = client.send_command(command_type=command_type, params=params)
        status = response.get("status")
        if status == "error":
            message = response.get("message", "Unknown Blender error.")
            raise RuntimeError(message)
        return response

    def adapter_status_payload() -> dict[str, Any]:
        scene_summary: dict[str, Any] | None = None
        error_message: str | None = None

        try:
            scene_summary = call_blender("get_scene_info")
        except Exception as exc:
            error_message = str(exc)

        return {
            "adapter": {
                "host": adapter_host,
                "port": adapter_port,
                "mount_path": mount_path,
                "streamable_http_path": streamable_http_path,
            },
            "blender_socket": {
                "host": blender_host,
                "port": blender_port,
                "reachable": error_message is None,
                "error": error_message,
            },
            "native_commands": NATIVE_COMMANDS,
            "scene_probe": scene_summary,
        }

    @server.resource(
        "blender://status",
        name="blender_status",
        description="Adapter status and Blender socket connectivity.",
        mime_type="application/json",
    )
    def blender_status() -> str:
        return json.dumps(adapter_status_payload(), indent=2)

    @server.resource(
        "blender://scene",
        name="blender_scene",
        description="Current Blender scene summary from the running addon.",
        mime_type="application/json",
    )
    def blender_scene() -> str:
        return json.dumps(call_blender("get_scene_info"), indent=2)

    @server.tool(
        name="blender_status",
        description="Check whether the proxy can reach the running BlenderMCP addon.",
    )
    def blender_status_tool() -> dict[str, Any]:
        return adapter_status_payload()

    @server.tool(
        name="list_native_commands",
        description="List the raw BlenderMCP command types supported by the running addon.",
    )
    def list_native_commands() -> list[str]:
        return NATIVE_COMMANDS

    @server.tool(
        name="get_scene_info",
        description="Return summary information for the active Blender scene.",
    )
    def get_scene_info() -> dict[str, Any]:
        return call_blender("get_scene_info")

    @server.tool(
        name="get_object_info",
        description="Return detailed information for a Blender object by name.",
    )
    def get_object_info(name: str) -> dict[str, Any]:
        return call_blender("get_object_info", {"name": name})

    @server.tool(
        name="execute_bpy_code",
        description="Execute arbitrary Python code inside the running Blender session with bpy available.",
    )
    def execute_bpy_code(code: str) -> dict[str, Any]:
        return call_blender("execute_code", {"code": code})

    @server.tool(
        name="call_blender_command",
        description="Send a raw BlenderMCP command type with optional JSON object params.",
    )
    def call_blender_command(command_type: str, params_json: str | None = None) -> dict[str, Any]:
        return call_blender(command_type, parse_params_json(params_json))

    return server


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Expose a running BlenderMCP socket server as an MCP HTTP server.")
    parser.add_argument("--host", default=DEFAULT_ADAPTER_HOST, help="Host for the MCP HTTP proxy.")
    parser.add_argument("--port", type=int, default=DEFAULT_ADAPTER_PORT, help="Port for the MCP HTTP proxy.")
    parser.add_argument("--mount-path", default=DEFAULT_MOUNT_PATH, help="ASGI mount path for the MCP server.")
    parser.add_argument(
        "--streamable-http-path",
        default=DEFAULT_STREAMABLE_HTTP_PATH,
        help="Path used for streamable HTTP MCP requests.",
    )
    parser.add_argument("--blender-host", default=DEFAULT_BLENDER_HOST, help="Host for the BlenderMCP socket server.")
    parser.add_argument("--blender-port", type=int, default=DEFAULT_BLENDER_PORT, help="Port for the BlenderMCP socket server.")
    parser.add_argument(
        "--socket-timeout-seconds",
        type=float,
        default=DEFAULT_SOCKET_TIMEOUT,
        help="Socket timeout for Blender command round trips.",
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
        blender_host=args.blender_host,
        blender_port=args.blender_port,
        socket_timeout_seconds=args.socket_timeout_seconds,
        mount_path=args.mount_path,
        streamable_http_path=args.streamable_http_path,
    )
    LOGGER.info(
        "Starting Blender MCP adapter on http://%s:%s%s and proxying Blender socket %s:%s",
        args.host,
        args.port,
        args.streamable_http_path,
        args.blender_host,
        args.blender_port,
    )
    server.run(transport="streamable-http")


if __name__ == "__main__":
    main()
