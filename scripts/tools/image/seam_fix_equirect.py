#!/usr/bin/env python3
# Seam fix for 2:1 equirectangular panoramas with optional AI refinement.
# python scripts/tools/image/seam_fix_equirect.py --input assets/stellar_rupture6144x3072.png --output 'assets/stellar_rupture_seamless.png'

from __future__ import annotations

import argparse
import base64
import io
import json
import math
import os
import sys
import urllib.error
import urllib.request
import uuid
from pathlib import Path
from typing import Sequence

try:
    from PIL import Image, ImageDraw
except ModuleNotFoundError as exc:
    print(
        "Pillow is required for seam_fix_equirect.py. Install it with: python -m pip install Pillow",
        file=sys.stderr,
    )
    raise SystemExit(2) from exc


OPENAI_API_KEY_ENV = "OPENAI_API_KEY"
OPENAI_BASE_URL_ENV = "OPENAI_BASE_URL"
DEFAULT_OPENAI_BASE_URL = "https://api.openai.com"
DEFAULT_OPENAI_IMAGE_EDIT_PATH = "/v1/images/edits"
DEFAULT_CENTER_BLEND_PCT = 8.0
DEFAULT_POLE_BLEND_PCT = 40.0
POLE_FADE_TARGET = (8, 10, 14, 255)
POLE_STAR_CELL_SIZE = 12
POLE_STAR_MAX_PROBABILITY = 0.05


class SeamFixError(RuntimeError):
    pass


class AIRefinementError(SeamFixError):
    pass


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Reduce seams in a 2:1 equirectangular panorama with wrap blending and smooth dark pole fading."
    )
    parser.add_argument("--input", required=True, help="Source image path.")
    parser.add_argument("--output", help="Optional output path. Defaults to a sibling *_seamfixed.png file.")
    parser.add_argument(
        "--center-blend-pct",
        type=float,
        default=DEFAULT_CENTER_BLEND_PCT,
        help="Horizontal seam blend band as a percentage of image width.",
    )
    parser.add_argument(
        "--pole-blend-pct",
        type=float,
        default=DEFAULT_POLE_BLEND_PCT,
        help="Top and bottom pole fade depth as a percentage of image height. The poles fade smoothly into a dark color.",
    )
    parser.add_argument(
        "--mode",
        choices=("deterministic", "ai", "hybrid"),
        default="deterministic",
        help="deterministic=local only, ai=masked AI edits, hybrid=local blend plus optional AI refinement",
    )
    parser.add_argument("--ai-model", help="Model name for AI or hybrid mode.")
    parser.add_argument("--dry-run", action="store_true", help="Validate inputs and print the output path without writing.")
    return parser.parse_args(argv)


def validate_percentage(name: str, value: float) -> float:
    if value <= 0.0 or value > 50.0:
        raise SeamFixError(f"{name} must be greater than 0 and at most 50. Received {value}.")
    return value


def ensure_rgba(image: Image.Image) -> Image.Image:
    if image.mode != "RGBA":
        return image.convert("RGBA")
    return image.copy()


def ensure_equirectangular_size(image: Image.Image, source_path: Path) -> None:
    width, height = image.size
    if width != height * 2:
        raise SeamFixError(
            f"Input image must be exactly 2:1 for equirectangular use. Received {width}x{height} from {source_path}."
        )


def default_output_path(input_path: Path) -> Path:
    return input_path.with_name(f"{input_path.stem}_seamfixed.png")


def resolve_output_path(input_path: Path, output_arg: str | None) -> Path:
    if output_arg:
        return Path(output_arg)
    return default_output_path(input_path)


def compute_blend_span(length: int, percentage: float) -> int:
    return max(1, min(length, int(round(length * percentage / 100.0))))


def centered_band_bounds(length: int, seam_index: int, blend_span: int) -> tuple[int, int]:
    span: int = max(1, min(length, blend_span))
    start: int = seam_index - (span // 2)
    end: int = start + span
    if start < 0:
        end -= start
        start = 0
    if end > length:
        start -= end - length
        end = length
    return start, end


def smoothstep(value: float) -> float:
    clamped: float = min(1.0, max(0.0, value))
    return clamped * clamped * (3.0 - 2.0 * clamped)


SRGB_TO_LINEAR = [0.0] * 256
for channel in range(256):
    srgb: float = channel / 255.0
    if srgb <= 0.04045:
        SRGB_TO_LINEAR[channel] = srgb / 12.92
    else:
        SRGB_TO_LINEAR[channel] = ((srgb + 0.055) / 1.055) ** 2.4


def linear_to_srgb_8bit(value: float) -> int:
    clamped: float = min(1.0, max(0.0, value))
    if clamped <= 0.0031308:
        srgb = 12.92 * clamped
    else:
        srgb = 1.055 * (clamped ** (1.0 / 2.4)) - 0.055
    return int(round(min(1.0, max(0.0, srgb)) * 255.0))


def lerp(a: float, b: float, weight: float) -> float:
    return a + ((b - a) * weight)


def blend_rgba_pixels(pixel_a: tuple[int, int, int, int], pixel_b: tuple[int, int, int, int], weight: float) -> tuple[int, int, int, int]:
    alpha_a: float = pixel_a[3] / 255.0
    alpha_b: float = pixel_b[3] / 255.0
    out_alpha: float = lerp(alpha_a, alpha_b, weight)

    premul_a = [SRGB_TO_LINEAR[pixel_a[index]] * alpha_a for index in range(3)]
    premul_b = [SRGB_TO_LINEAR[pixel_b[index]] * alpha_b for index in range(3)]
    premul_out = [lerp(premul_a[index], premul_b[index], weight) for index in range(3)]

    if out_alpha > 0.0:
        rgb_linear = [channel / out_alpha for channel in premul_out]
    else:
        rgb_linear = [0.0, 0.0, 0.0]

    return (
        linear_to_srgb_8bit(rgb_linear[0]),
        linear_to_srgb_8bit(rgb_linear[1]),
        linear_to_srgb_8bit(rgb_linear[2]),
        int(round(out_alpha * 255.0)),
    )


def blend_vertical_seam(stage_image: Image.Image, seam_x: int, blend_span: int) -> Image.Image:
    width, height = stage_image.size
    start_x, end_x = centered_band_bounds(width, seam_x, blend_span)
    source = stage_image.copy()
    source_pixels = source.load()
    output = stage_image.copy()
    output_pixels = output.load()
    pair_count = min(seam_x - start_x, end_x - seam_x)

    for offset in range(pair_count):
        left_x: int = seam_x - 1 - offset
        right_x: int = seam_x + offset
        normalized_offset: float = 0.0 if pair_count == 1 else offset / (pair_count - 1)
        influence: float = 1.0 - smoothstep(normalized_offset)
        blend_weight: float = 0.5 * influence
        for y in range(height):
            left_pixel = source_pixels[left_x, y]
            right_pixel = source_pixels[right_x, y]
            output_pixels[left_x, y] = blend_rgba_pixels(left_pixel, right_pixel, blend_weight)
            output_pixels[right_x, y] = blend_rgba_pixels(right_pixel, left_pixel, blend_weight)

    return output


def build_horizontal_stage(image: Image.Image) -> tuple[Image.Image, int]:
    width, height = image.size
    half_width = width // 2
    stage = Image.new("RGBA", image.size)
    stage.paste(image.crop((half_width, 0, width, height)), (0, 0))
    stage.paste(image.crop((0, 0, half_width, height)), (half_width, 0))
    return stage, half_width


def restore_horizontal_stage(stage_image: Image.Image) -> Image.Image:
    width, height = stage_image.size
    half_width = width // 2
    restored = Image.new("RGBA", stage_image.size)
    restored.paste(stage_image.crop((half_width, 0, width, height)), (0, 0))
    restored.paste(stage_image.crop((0, 0, half_width, height)), (half_width, 0))
    return restored


def horizontal_modified_column_ranges(width: int, blend_span: int) -> list[tuple[int, int]]:
    half_width = width // 2
    start_x, end_x = centered_band_bounds(width, half_width, blend_span)
    return [
        (0, max(0, end_x - half_width)),
        (start_x + half_width, width),
    ]


def pole_modified_row_ranges(height: int, pole_rows: int) -> list[tuple[int, int]]:
    return [
        (0, pole_rows),
        (height - pole_rows, height),
    ]


def hash_noise(x: int, y: int, seed: int) -> float:
    value = (x * 374761393) + (y * 668265263) + (seed * 1442695041)
    value = (value ^ (value >> 13)) * 1274126177
    value = value ^ (value >> 16)
    return (value & 0xFFFFFFFF) / 4294967295.0


def value_noise(x: float, y: float, cell_size: int, seed: int) -> float:
    scaled_x: float = x / float(cell_size)
    scaled_y: float = y / float(cell_size)
    x0: int = int(math.floor(scaled_x))
    y0: int = int(math.floor(scaled_y))
    x1: int = x0 + 1
    y1: int = y0 + 1
    tx: float = smoothstep(scaled_x - x0)
    ty: float = smoothstep(scaled_y - y0)

    n00: float = hash_noise(x0, y0, seed)
    n10: float = hash_noise(x1, y0, seed)
    n01: float = hash_noise(x0, y1, seed)
    n11: float = hash_noise(x1, y1, seed)

    nx0: float = lerp(n00, n10, tx)
    nx1: float = lerp(n01, n11, tx)
    return lerp(nx0, nx1, ty)


def cloud_noise(x: int, y: int, width: int, region_height: int, seed: int) -> float:
    large_cell: int = max(16, min(width, region_height * 2, width // 12 if width >= 12 else width))
    detail_cell: int = max(8, large_cell // 2)
    low_freq: float = value_noise(float(x), float(y), large_cell, seed)
    detail_freq: float = value_noise(float(x), float(y), detail_cell, seed + 97)
    return (low_freq * 0.7) + (detail_freq * 0.3)


def pole_star_color(noise_value: float) -> tuple[int, int, int, int]:
    if noise_value > 0.9991:
        return (255, 252, 245, 255)
    return (250, 250, 255, 255)


def should_place_pole_star(x: int, y: int, width: int, start_y: int, end_y: int, seed: int, star_weight: float) -> bool:
    if star_weight <= 0.0:
        return False

    local_y: int = y - start_y
    cell_size: int = POLE_STAR_CELL_SIZE
    cell_x: int = x // cell_size
    cell_y: int = local_y // cell_size

    activation_probability: float = POLE_STAR_MAX_PROBABILITY * star_weight * star_weight
    activation_noise: float = hash_noise(cell_x, cell_y, seed + 101)
    if activation_noise >= activation_probability:
        return False

    region_height: int = end_y - start_y
    cell_origin_x: int = cell_x * cell_size
    cell_origin_y: int = cell_y * cell_size
    cell_width: int = min(cell_size, width - cell_origin_x)
    cell_height: int = min(cell_size, region_height - cell_origin_y)
    if cell_width <= 0 or cell_height <= 0:
        return False

    star_offset_x: int = min(cell_width - 1, int(hash_noise(cell_x, cell_y, seed + 211) * cell_width))
    star_offset_y: int = min(cell_height - 1, int(hash_noise(cell_x, cell_y, seed + 307) * cell_height))

    return x == (cell_origin_x + star_offset_x) and local_y == (cell_origin_y + star_offset_y)


def apply_pole_dark_fade(
    source: Image.Image,
    output: Image.Image,
    start_y: int,
    end_y: int,
    edge_y: int,
    seed: int,
) -> None:
    width, _height = source.size
    region_height: int = end_y - start_y
    if region_height <= 0:
        return

    source_pixels = source.load()
    output_pixels = output.load()
    target_color: tuple[int, int, int, int] = POLE_FADE_TARGET

    for y in range(start_y, end_y):
        edge_distance: int = abs(y - edge_y)
        normalized_distance: float = 0.0 if region_height == 1 else edge_distance / float(region_height - 1)
        fade_weight: float = 1.0 - smoothstep(normalized_distance)
        star_weight: float = fade_weight * fade_weight
        for x in range(width):
            faded_pixel = blend_rgba_pixels(source_pixels[x, y], target_color, fade_weight)
            if should_place_pole_star(x, y, width, start_y, end_y, seed, star_weight):
                noise_value: float = hash_noise(x, y, seed + 313)
                output_pixels[x, y] = pole_star_color(noise_value)
            else:
                output_pixels[x, y] = faded_pixel


def create_editable_mask(size: tuple[int, int], band_box: tuple[int, int, int, int]) -> tuple[Image.Image, Image.Image]:
    opaque_mask = Image.new("RGBA", size, (255, 255, 255, 255))
    draw = ImageDraw.Draw(opaque_mask)
    left, top, right, bottom = band_box
    inclusive_box = (left, top, max(left, right - 1), max(top, bottom - 1))
    draw.rectangle(inclusive_box, fill=(255, 255, 255, 0))

    editable_mask = Image.new("L", size, 0)
    draw_editable = ImageDraw.Draw(editable_mask)
    draw_editable.rectangle(inclusive_box, fill=255)
    return opaque_mask, editable_mask


def image_to_png_bytes(image: Image.Image) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def decode_image_from_response(response_payload: dict[str, object]) -> Image.Image:
    data = response_payload.get("data")
    if not isinstance(data, list) or not data:
        raise AIRefinementError("AI response did not include any image payloads.")

    first = data[0]
    if not isinstance(first, dict):
        raise AIRefinementError("AI response payload format was not recognized.")

    encoded = first.get("b64_json")
    if not isinstance(encoded, str):
        raise AIRefinementError("AI response did not include a base64 image.")

    raw_bytes = base64.b64decode(encoded)
    return ensure_rgba(Image.open(io.BytesIO(raw_bytes)))


def encode_multipart_form(fields: dict[str, str], files: dict[str, tuple[str, bytes, str]]) -> tuple[bytes, str]:
    boundary = f"----FluxbreakSeamFix{uuid.uuid4().hex}"
    parts: list[bytes] = []

    for name, value in fields.items():
        parts.append(f"--{boundary}\r\n".encode("utf-8"))
        parts.append(f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode("utf-8"))
        parts.append(value.encode("utf-8"))
        parts.append(b"\r\n")

    for name, (filename, payload, content_type) in files.items():
        parts.append(f"--{boundary}\r\n".encode("utf-8"))
        parts.append(
            f'Content-Disposition: form-data; name="{name}"; filename="{filename}"\r\n'.encode("utf-8")
        )
        parts.append(f"Content-Type: {content_type}\r\n\r\n".encode("utf-8"))
        parts.append(payload)
        parts.append(b"\r\n")

    parts.append(f"--{boundary}--\r\n".encode("utf-8"))
    return b"".join(parts), boundary


def call_openai_image_edit(stage_image: Image.Image, mask_image: Image.Image, prompt: str, model: str) -> Image.Image:
    api_key = os.environ.get(OPENAI_API_KEY_ENV)
    if not api_key:
        raise AIRefinementError(f"{OPENAI_API_KEY_ENV} is required for AI image editing.")

    base_url = os.environ.get(OPENAI_BASE_URL_ENV, DEFAULT_OPENAI_BASE_URL).rstrip("/")
    request_url = f"{base_url}{DEFAULT_OPENAI_IMAGE_EDIT_PATH}"

    fields = {
        "model": model,
        "prompt": prompt,
        "response_format": "b64_json",
    }
    files = {
        "image": ("stage.png", image_to_png_bytes(stage_image), "image/png"),
        "mask": ("mask.png", image_to_png_bytes(mask_image), "image/png"),
    }
    body, boundary = encode_multipart_form(fields, files)
    request = urllib.request.Request(
        request_url,
        data=body,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": f"multipart/form-data; boundary={boundary}",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        error_body = exc.read().decode("utf-8", errors="replace")
        raise AIRefinementError(f"AI image edit request failed with HTTP {exc.code}: {error_body}") from exc
    except urllib.error.URLError as exc:
        raise AIRefinementError(f"AI image edit request failed: {exc.reason}") from exc

    return decode_image_from_response(payload)


def band_box_for_vertical_seam(stage_size: tuple[int, int], seam_index: int, blend_span: int) -> tuple[int, int, int, int]:
    width, height = stage_size
    start_x, end_x = centered_band_bounds(width, seam_index, blend_span)
    return start_x, 0, end_x, height


def refine_stage_with_ai(
    stage_image: Image.Image,
    seam_index: int,
    blend_span: int,
    model: str,
    prompt_label: str,
) -> Image.Image:
    band_box = band_box_for_vertical_seam(stage_image.size, seam_index, blend_span)
    mask_image, editable_mask = create_editable_mask(stage_image.size, band_box)
    prompt = (
        f"Refine only the transparent masked seam area of this equirectangular sky panorama {prompt_label}. "
        "Preserve all unmasked pixels exactly. Make the seam continuous and natural while keeping the existing stars, "
        "nebula structures, contrast, and overall color palette."
    )
    edited = call_openai_image_edit(stage_image, mask_image, prompt, model)
    if edited.size != stage_image.size:
        raise AIRefinementError(
            f"AI response size {edited.size[0]}x{edited.size[1]} did not match the stage size "
            f"{stage_image.size[0]}x{stage_image.size[1]}."
        )
    return Image.composite(edited, stage_image, editable_mask)


def maybe_refine_stage(
    stage_image: Image.Image,
    mode: str,
    seam_index: int,
    blend_span: int,
    ai_model: str | None,
    prompt_label: str,
) -> Image.Image:
    if mode == "deterministic":
        return stage_image

    if not ai_model:
        raise AIRefinementError("--ai-model is required for ai mode.") if mode == "ai" else AIRefinementError(
            "Hybrid mode requested AI refinement but --ai-model was not provided."
        )

    return refine_stage_with_ai(stage_image, seam_index, blend_span, ai_model, prompt_label)


def run_horizontal_pass(image: Image.Image, blend_span: int, mode: str, ai_model: str | None) -> Image.Image:
    stage, seam_x = build_horizontal_stage(image)
    if mode in ("deterministic", "hybrid"):
        stage = blend_vertical_seam(stage, seam_x, blend_span)
    if mode in ("ai", "hybrid"):
        stage = maybe_refine_stage(stage, mode, seam_x, blend_span, ai_model, "at the horizontal wrap seam")
    return restore_horizontal_stage(stage)


def run_polar_pass(image: Image.Image, pole_rows: int) -> Image.Image:
    _width, height = image.size
    result = image.copy()
    apply_pole_dark_fade(image, result, 0, pole_rows, 0, 11)
    apply_pole_dark_fade(image, result, height - pole_rows, height, height - 1, 29)
    return result


def process_image(image: Image.Image, center_blend_pct: float, pole_blend_pct: float, mode: str, ai_model: str | None) -> Image.Image:
    working = ensure_rgba(image)
    width, height = working.size
    center_blend_span = compute_blend_span(width, center_blend_pct)
    pole_rows = compute_blend_span(height, pole_blend_pct)

    if mode == "hybrid":
        try:
            working = run_horizontal_pass(working, center_blend_span, mode, ai_model)
            return run_polar_pass(working, pole_rows)
        except AIRefinementError as exc:
            print(f"Hybrid mode warning: {exc}. Keeping deterministic result.", file=sys.stderr)
            working = ensure_rgba(image)
            working = run_horizontal_pass(working, center_blend_span, "deterministic", None)
            return run_polar_pass(working, pole_rows)

    working = run_horizontal_pass(working, center_blend_span, mode, ai_model)
    return run_polar_pass(working, pole_rows)


def run_cli(args: argparse.Namespace) -> int:
    input_path = Path(args.input)
    if not input_path.is_file():
        raise SeamFixError(f"Input file not found: {input_path}")

    validate_percentage("center-blend-pct", args.center_blend_pct)
    validate_percentage("pole-blend-pct", args.pole_blend_pct)

    output_path = resolve_output_path(input_path, args.output)
    with Image.open(input_path) as loaded:
        image = ensure_rgba(loaded)

    ensure_equirectangular_size(image, input_path)

    if args.dry_run:
        print(output_path)
        return 0

    output_path.parent.mkdir(parents=True, exist_ok=True)
    processed = process_image(image, args.center_blend_pct, args.pole_blend_pct, args.mode, args.ai_model)
    processed.save(output_path, format="PNG")
    print(output_path)
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    try:
        return run_cli(parse_args(argv))
    except SeamFixError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
