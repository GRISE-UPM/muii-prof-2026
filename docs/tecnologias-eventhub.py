#!/usr/bin/env python3
"""Figura con los logos de las tecnologías usadas en Event Hub.

Toma los SVG oficiales de Simple Icons, los compone en una rejilla con el color
de marca de cada tecnología y rasteriza el resultado con rsvg-convert.
"""

import re
import subprocess
import urllib.request
from pathlib import Path

CDN = "https://cdn.jsdelivr.net/npm/simple-icons@latest/icons/{slug}.svg"
SVG_OUTPUT = Path(__file__).with_name("tecnologias-eventhub.svg")
PNG_OUTPUT = Path(__file__).with_name("tecnologias-eventhub.png")

# (slug en Simple Icons, etiqueta, color de marca)
TECHS = [
    ("amazonwebservices", "AWS", "#FF9900"),
    ("apachemaven", "Maven", "#C71A36"),
    ("nodedotjs", "Node.js", "#5FA04E"),
    ("springboot", "Spring Boot", "#6DB33F"),
    ("react", "React", "#61DAFB"),
    ("vite", "Vite", "#646CFF"),
]

COLS = 3
ICON = 150          # lado del logo en px (los SVG vienen en viewBox 24x24)
CELL_W, CELL_H = 340, 260
MARGIN_TOP = 30
TEXT = "#212F3D"


def icon_path(slug: str) -> str:
    """Devuelve el atributo 'd' del trazado del logo."""
    with urllib.request.urlopen(CDN.format(slug=slug)) as response:
        svg = response.read().decode()
    return re.search(r'\sd="([^"]+)"', svg).group(1)


rows = -(-len(TECHS) // COLS)
width, height = COLS * CELL_W, MARGIN_TOP + rows * CELL_H

parts = [
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
    f'viewBox="0 0 {width} {height}">',
    f'<rect width="{width}" height="{height}" fill="white"/>',
]

for index, (slug, label, color) in enumerate(TECHS):
    col, row = index % COLS, index // COLS
    center_x = col * CELL_W + CELL_W / 2
    top_y = MARGIN_TOP + row * CELL_H + 20
    scale = ICON / 24

    parts.append(
        f'<g transform="translate({center_x - ICON / 2},{top_y}) scale({scale})">'
        f'<path d="{icon_path(slug)}" fill="{color}"/></g>'
    )
    parts.append(
        f'<text x="{center_x}" y="{top_y + ICON + 48}" text-anchor="middle" '
        f'font-family="Helvetica" font-size="34" fill="{TEXT}">{label}</text>'
    )

parts.append("</svg>")
SVG_OUTPUT.write_text("\n".join(parts))

subprocess.run(["rsvg-convert", "-o", PNG_OUTPUT, SVG_OUTPUT], check=True)
print(f"Escrito {PNG_OUTPUT}")
