#!/usr/bin/env python3
"""Builds the app icons from the SVGs in this folder.

Needs rsvg-convert (librsvg) and Pillow. Writes:
  windows/Margin.App/Assets/Margin.ico   (16-256 px; small sizes use the simplified drawing)
  macos/Margin.icns                      (icon inset on a transparent canvas, the macOS convention)
  windows/Margin.App/Assets/Margin-96.png (shown in the app's sidebar)
  assets/icon-256.png                    (for the README)
"""
import io
import subprocess
from pathlib import Path

from PIL import Image

here = Path(__file__).resolve().parent
root = here.parent


def render(svg: str, size: int) -> Image.Image:
    png = subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), str(here / svg)],
                         check=True, capture_output=True).stdout
    return Image.open(io.BytesIO(png)).convert("RGBA")


# Windows
sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
frames = [render("icon-small.svg" if s <= 32 else "icon.svg", s) for s in sizes]
ico = root / "windows" / "Margin.App" / "Assets" / "Margin.ico"
ico.parent.mkdir(parents=True, exist_ok=True)
frames[-1].save(ico, format="ICO", sizes=[(s, s) for s in sizes], append_images=frames[:-1], bitmap_format="bmp")

# macOS: the artwork sits at about 80% of the canvas
canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
canvas.alpha_composite(render("icon.svg", 824), (100, 100))
canvas.save(root / "macos" / "Margin.icns", format="ICNS")

render("icon.svg", 256).save(here / "icon-256.png")
render("icon.svg", 96).save(ico.parent / "Margin-96.png")      # shown in the app's sidebar
print("wrote", ico.relative_to(root), "Margin-96.png", "macos/Margin.icns", "assets/icon-256.png")
