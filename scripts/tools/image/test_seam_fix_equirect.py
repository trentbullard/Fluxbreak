from __future__ import annotations

import contextlib
import importlib.util
import io
import tempfile
import unittest
from pathlib import Path

from PIL import Image


MODULE_PATH = Path(__file__).with_name("seam_fix_equirect.py")
SPEC = importlib.util.spec_from_file_location("seam_fix_equirect", MODULE_PATH)
assert SPEC is not None
assert SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def make_pattern_image(width: int, height: int) -> Image.Image:
    image = Image.new("RGBA", (width, height))
    pixels = image.load()
    for y in range(height):
        for x in range(width):
            pixels[x, y] = (
                (x * 37 + y * 11) % 256,
                (x * 17 + y * 29) % 256,
                (x * 53 + y * 7) % 256,
                255,
            )
    return image


def changed_columns(before: Image.Image, after: Image.Image) -> set[int]:
    width, height = before.size
    columns: set[int] = set()
    for x in range(width):
        for y in range(height):
            if before.getpixel((x, y)) != after.getpixel((x, y)):
                columns.add(x)
                break
    return columns


def changed_rows(before: Image.Image, after: Image.Image) -> set[int]:
    width, height = before.size
    rows: set[int] = set()
    for y in range(height):
        for x in range(width):
            if before.getpixel((x, y)) != after.getpixel((x, y)):
                rows.add(y)
                break
    return rows


def color_distance(pixel_a: tuple[int, int, int, int], pixel_b: tuple[int, int, int, int]) -> int:
    return sum(abs(pixel_a[index] - pixel_b[index]) for index in range(4))


class SeamFixEquirectTests(unittest.TestCase):
    def test_process_valid_image_writes_output_and_keeps_source(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            input_path = temp_path / "source.png"
            output_path = temp_path / "result.png"
            image = make_pattern_image(20, 10)
            image.save(input_path, format="PNG")
            source_bytes_before = input_path.read_bytes()

            exit_code = MODULE.main(["--input", str(input_path), "--output", str(output_path)])

            self.assertEqual(exit_code, 0)
            self.assertEqual(source_bytes_before, input_path.read_bytes())
            with Image.open(output_path) as output_image:
                self.assertEqual(output_image.size, (20, 10))

    def test_default_pole_blend_pct_is_20_percent(self) -> None:
        self.assertEqual(MODULE.DEFAULT_POLE_BLEND_PCT, 20.0)

    def test_non_equirectangular_input_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            input_path = Path(temp_dir) / "bad.png"
            Image.new("RGBA", (21, 10), (10, 20, 30, 255)).save(input_path, format="PNG")
            stderr = io.StringIO()

            with contextlib.redirect_stderr(stderr):
                exit_code = MODULE.main(["--input", str(input_path)])

            self.assertEqual(exit_code, 1)
            self.assertIn("exactly 2:1", stderr.getvalue())

    def test_horizontal_pass_only_changes_expected_edge_columns(self) -> None:
        source = make_pattern_image(20, 10)
        processed = MODULE.run_horizontal_pass(source, 4, "deterministic", None)
        changed = changed_columns(source, processed)
        allowed: set[int] = set()
        for start, end in MODULE.horizontal_modified_column_ranges(source.size[0], 4):
            allowed.update(range(start, end))

        self.assertTrue(changed)
        self.assertTrue(changed.issubset(allowed))

    def test_polar_pass_only_changes_expected_top_and_bottom_rows(self) -> None:
        source = make_pattern_image(20, 10)
        processed = MODULE.run_polar_pass(source, 2)
        changed = changed_rows(source, processed)
        allowed: set[int] = set()
        for start, end in MODULE.pole_modified_row_ranges(source.size[1], 2):
            allowed.update(range(start, end))

        self.assertTrue(changed)
        self.assertTrue(changed.issubset(allowed))

    def test_small_exact_2_to_1_image_uses_rounded_band_sizes_without_errors(self) -> None:
        source = make_pattern_image(10, 5)
        processed = MODULE.process_image(source, 13.0, 11.0, "deterministic", None)
        self.assertEqual(processed.size, (10, 5))

    def test_horizontal_pass_blends_outer_wrap_edge_without_shifting_inner_columns(self) -> None:
        source = Image.new("RGBA", (8, 4), (0, 0, 0, 255))
        for x in range(4, 8):
            for y in range(4):
                source.putpixel((x, y), (255, 0, 0, 255))

        processed = MODULE.run_horizontal_pass(source, 4, "deterministic", None)

        self.assertEqual(processed.getpixel((0, 0)), processed.getpixel((7, 0)))
        self.assertEqual(processed.getpixel((1, 0)), source.getpixel((1, 0)))
        self.assertEqual(processed.getpixel((6, 0)), source.getpixel((6, 0)))

    def test_polar_pass_darkens_edge_more_than_inner_rows(self) -> None:
        source = Image.new("RGBA", (12, 10), (120, 150, 200, 255))
        processed = MODULE.run_polar_pass(source, 4)

        edge_delta = color_distance(source.getpixel((0, 0)), processed.getpixel((0, 0)))
        inner_delta = color_distance(source.getpixel((0, 3)), processed.getpixel((0, 3)))

        self.assertGreater(edge_delta, inner_delta)
        self.assertEqual(processed.getpixel((0, 4)), source.getpixel((0, 4)))

    def test_polar_pass_uses_shared_fixed_dark_target(self) -> None:
        source = Image.new("RGBA", (12, 10), (180, 200, 220, 255))
        processed = MODULE.run_polar_pass(source, 4)

        self.assertEqual(processed.getpixel((1, 0)), MODULE.POLE_FADE_TARGET)
        self.assertEqual(processed.getpixel((1, 9)), MODULE.POLE_FADE_TARGET)

    def test_polar_pass_fades_smoothly_without_hard_cap_line(self) -> None:
        source = Image.new("RGBA", (12, 10), (120, 150, 200, 255))
        processed = MODULE.run_polar_pass(source, 4)

        row0 = processed.getpixel((0, 0))
        row1 = processed.getpixel((0, 1))
        row2 = processed.getpixel((0, 2))
        row3 = processed.getpixel((0, 3))

        self.assertNotEqual(row0, row1)
        self.assertNotEqual(row1, row2)
        self.assertNotEqual(row2, row3)
        self.assertLess(color_distance(row3, source.getpixel((0, 3))), color_distance(row0, source.getpixel((0, 0))))

    def test_polar_pass_adds_sparse_deterministic_star_specks(self) -> None:
        source = Image.new("RGBA", (256, 64), (64, 72, 96, 255))
        processed = MODULE.run_polar_pass(source, 16)
        valid_star_colors = {(255, 252, 245, 255), (250, 250, 255, 255)}

        stars = 0
        for y in list(range(0, 16)) + list(range(48, 64)):
            for x in range(256):
                if processed.getpixel((x, y)) in valid_star_colors:
                    stars += 1

        self.assertGreater(stars, 0)
        self.assertLess(stars, 200)

    def test_polar_pass_is_deterministic_for_same_input(self) -> None:
        source = make_pattern_image(20, 10)
        first = MODULE.run_polar_pass(source, 4)
        second = MODULE.run_polar_pass(source, 4)

        for y in range(source.size[1]):
            for x in range(source.size[0]):
                self.assertEqual(first.getpixel((x, y)), second.getpixel((x, y)))

    def test_polar_pass_does_not_relocate_middle_rows(self) -> None:
        source = make_pattern_image(20, 10)
        processed = MODULE.run_polar_pass(source, 4)

        for y in range(4, 6):
            for x in range(20):
                self.assertEqual(processed.getpixel((x, y)), source.getpixel((x, y)))

    def test_default_output_path_uses_seamfixed_suffix(self) -> None:
        input_path = Path("assets/stellar_rupture6144x3072.png")
        self.assertEqual(
            MODULE.default_output_path(input_path),
            Path("assets/stellar_rupture6144x3072_seamfixed.png"),
        )

    def test_ai_mode_reports_missing_credentials(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            input_path = Path(temp_dir) / "source.png"
            make_pattern_image(20, 10).save(input_path, format="PNG")
            stderr = io.StringIO()

            with contextlib.redirect_stderr(stderr):
                exit_code = MODULE.main(["--input", str(input_path), "--mode", "ai", "--ai-model", "gpt-image-1"])

            self.assertEqual(exit_code, 1)
            self.assertIn("OPENAI_API_KEY", stderr.getvalue())

    def test_hybrid_mode_warns_and_keeps_deterministic_output_when_ai_is_not_configured(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            input_path = temp_path / "source.png"
            output_path = temp_path / "hybrid.png"
            make_pattern_image(20, 10).save(input_path, format="PNG")
            stderr = io.StringIO()

            with contextlib.redirect_stderr(stderr):
                exit_code = MODULE.main(
                    ["--input", str(input_path), "--output", str(output_path), "--mode", "hybrid", "--ai-model", "gpt-image-1"]
                )

            self.assertEqual(exit_code, 0)
            self.assertTrue(output_path.is_file())
            self.assertIn("Hybrid mode warning", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
