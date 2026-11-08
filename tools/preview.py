#!/usr/bin/env python3
"""Software preview renderer for the world spec — the visual review artefact.

Roblox Studio is not available in this environment, so this renders the exact
geometry/colour/material tables from tools/world.py and the lighting rig from
tools/theme.py with a small z-buffered rasteriser (numpy + Pillow, dev-only
dependencies, never part of the shipped game).

It is an approximation, not an engine screenshot: it communicates composition,
palette, hierarchy and readability. It is also the tool used to produce the
before/after "look" plates for docs/VISUAL_CHANGES.md.

    python3 tools/preview.py                     # arena, lobby, palms, overview
    python3 tools/preview.py --legacy            # pre-redesign look (for comparison)
    python3 tools/preview.py --only arena        # a single view
"""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import theme
from creatures import CREATURES, creature_for  # noqa: E402
from world import make_world  # noqa: E402

OUT = ROOT / "docs" / "previews"

# ---------------------------------------------------------------- pre-redesign
# Frozen copy of the old specification values, used only to render a comparison
# plate. The game no longer contains these colours or materials.
LEGACY = {
    "ink": [23, 24, 63], "rock": [67, 47, 119], "rock_light": [105, 71, 169],
    "grass": [99, 218, 154], "mint": [151, 247, 183], "path": [255, 221, 99],
    "cyan": [66, 228, 247], "purple": [155, 95, 255], "pink": [255, 94, 190],
    "white": [239, 250, 255], "gold": [255, 194, 61], "trunk": [149, 97, 75],
    "leaf": [47, 190, 141], "leaf_light": [158, 239, 91], "blue": [65, 139, 228],
}
LEGACY_LIGHT = {
    "sun": np.array([1.0, 0.94, 0.82]), "ambient": np.array([0.53, 0.48, 0.73]),
    "sky_top": np.array([0.35, 0.60, 0.95]), "sky_horizon": np.array([0.59, 0.84, 1.00]),
    "saturation": 1.0,
}


def legacy_palette():
    """Map the redesigned part names back onto the old colours, for comparison."""
    def pick(part):
        name = part["Name"]
        if "Fan" in name or "Top" in name and "SkyShard" in name:
            return [158, 239, 91] if name.endswith(("0", "2", "4")) else [47, 190, 141]
        if "Tip" in name:
            return [47, 190, 141]
        if "Trunk" in name:
            return [149, 97, 75]
        if "Bud" in name:
            return [255, 194, 61]
        if name.endswith("_Turf"):
            return [99, 218, 154]
        if name.endswith("_Trim"):
            return [155, 95, 255]
        if name.endswith(("_Rock", "_RockLower", "_RockTail")) or "_Facet_" in name:
            return [67, 47, 119] if not name.endswith(("1", "3", "5")) else [105, 71, 169]
        if "RailPost" in name:
            return [239, 250, 255]
        if name.startswith("Rail_"):
            return [155, 95, 255]
        if name.startswith(("Bridge_", "BridgeTrim", "Circuit_", "SpawnPad")):
            return [66, 228, 247] if name.endswith(("1", "3", "5", "7", "9")) else [255, 221, 99]
        if name.startswith(("Beacon_Step_1", "TitleBoard", "Queue_Arch", "Portal_Banner")):
            return [239, 250, 255]
        if "Brain" in name:
            return [255, 94, 190]
        if name.startswith("Beacon_Plinth"):
            return [23, 24, 63]
        return [155, 95, 255]
    return pick


# ------------------------------------------------------------------ rasteriser
def normalise(v):
    return v / np.linalg.norm(v, axis=-1, keepdims=True)


class Frame:
    """Simple look-at camera."""

    def __init__(self, eye, target, fov=60.0, width=960, height=560, up=(0, 1, 0)):
        self.eye = np.array(eye, dtype=float)
        self.target = np.array(target, dtype=float)
        self.width, self.height = width, height
        forward = normalise(self.target - self.eye)
        right = normalise(np.cross(forward, np.array(up, dtype=float)))
        upv = np.cross(right, forward)
        self.basis = np.stack([right, upv, forward])
        self.focal = (height / 2) / math.tan(math.radians(fov) / 2)

    def project(self, points):
        rel = points - self.eye
        cam = rel @ self.basis.T
        depth = cam[:, 2]
        with np.errstate(divide="ignore", invalid="ignore"):
            x = self.width / 2 + cam[:, 0] / depth * self.focal
            y = self.height / 2 - cam[:, 1] / depth * self.focal
        return np.stack([x, y], axis=1), depth


FIXED_INKS = {
    "eye": (32, 37, 43), "glint": (250, 250, 248),
    "accent_wood": (122, 92, 68), "accent_cream": (238, 230, 212),
}


def tint(base, role):
    """Mirror of src/client/Creatures.luau `tint`, so plates match the runtime."""
    if role in ("body", "neon"):
        return list(base)
    if role == "body_light":
        return [round(c + (255 - c) * .24) for c in base]
    if role == "body_dark":
        return [round(c + ((36, 41, 51)[i] - c) * .40) for i, c in enumerate(base)]
    return list(FIXED_INKS.get(role, base))


def creature_parts(name, x, y, z, base, *, yaw=0.0):
    """One creature instance from tools/creatures.py, placed at a pickup slot."""
    spec = CREATURES[name]
    out = []
    cos, sin = math.cos(yaw), math.sin(yaw)
    for item in spec["Parts"]:
        ox, oy, oz = item["Offset"]
        size = item["Size"]
        rot = item["Rotation"]
        if item["Shape"] == "Ball":
            # Spheres are rotation-invariant: cheap to skip the transform.
            pos = (x + ox, y + oy, z + oz)
            rot = (0, 0, 0)
        else:
            pos = (x + ox * cos - oz * sin, y + oy, z + ox * sin + oz * cos)
            rot = (rot[0], rot[1] + math.degrees(yaw), rot[2])
        out.append({
            "Name": f"{name}_{item['Name']}", "Position": list(pos), "Size": list(size),
            "Color": tint(base, item["Role"]), "Rotation": list(rot),
            "Material": "SmoothPlastic", "CastShadow": False, "Collide": False,
            "Shape": "Block" if item["Shape"] == "WedgePart" else item["Shape"],
            "Class": "WedgePart" if item["Shape"] == "WedgePart" else "Part",
            "Transparency": 0.0, "Role": "hero", "Layer": 4, "Island": "Arena",
        })
    return out


def add_cells(parts, pickup_positions, kinds=((255, 94, 190), (255, 213, 67), (83, 238, 255))):
    """Append the 48 Brain Cell silhouettes so previews show gameplay legibility."""
    out = list(parts)
    for index, slot in enumerate(pickup_positions):
        # 78 / 18 / 4 weighting, deterministic.
        bucket = index % 25
        kind = kinds[0] if bucket >= 5 else (kinds[1] if bucket >= 1 else kinds[2])
        x, y, z = slot["x"], slot["y"], slot["z"]
        value = 1 if kind == kinds[0] else (5 if kind == kinds[1] else 10)
        name = creature_for(index, value)
        # The runtime spins cells; bake a gentle per-slot yaw so plates read as 3D.
        yaw = math.radians((index * 37) % 360)
        out.extend(creature_parts(name, x, y, z, kind, yaw=yaw))
        out.append({
            "Name": "CellHalo", "Position": [x, y - .05, z], "Size": [.09, 1.62, 1.62],
            "Color": [255, 255, 255], "Rotation": [0, 0, 90], "Material": "SmoothPlastic",
            "CastShadow": False, "Collide": False, "Shape": "Cylinder", "Class": "Part",
            "Transparency": 0.0, "Role": "hero", "Layer": 4, "Island": "Arena",
        })
        if value == 5:      # gold: floating ring above the head
            out.append({
                "Name": "CellMark", "Position": [x, y + 1.12, z], "Size": [.10, .74, .74],
                "Color": list(kind), "Rotation": [0, 0, 90], "Material": "Neon",
                "CastShadow": False, "Collide": False, "Shape": "Cylinder", "Class": "Part",
                "Transparency": 0.0, "Role": "hero", "Layer": 4, "Island": "Arena",
            })
        elif value == 10:   # prism: two crossed arms in front of the chest
            for angle in (38, -38):
                out.append({
                    "Name": "CellMark", "Position": [x, y - .06, z + .62], "Size": [.12, .12, .92],
                    "Color": list(kind), "Rotation": [0, 0, angle], "Material": "Neon",
                    "CastShadow": False, "Collide": False, "Shape": "Block", "Class": "Part",
                    "Transparency": 0.0, "Role": "hero", "Layer": 4, "Island": "Arena",
                })
    return out


def cast_lineup(base=(0, 28.4, 0)):
    """The six-critter cast sheet: one row, deterministic yaws, halo + rarity marks."""
    out = []
    names = ["brain", "frog", "fish", "goose", "toast", "sock"]
    values = {"brain": 1, "frog": 1, "fish": 5, "goose": 5, "toast": 10, "sock": 10}
    kinds = {1: (255, 94, 190), 5: (255, 213, 67), 10: (83, 238, 255)}
    for index, name in enumerate(names):
        value = values[name]
        x = base[0] - 6.75 + index * 2.7
        y, z = base[1], base[2]
        # Faces are authored toward -Z; turn them to the camera for the sheet.
        out.extend(creature_parts(name, x, y, z, kinds[value], yaw=math.pi + math.radians(20)))
        out.append({
            "Name": "CellHalo", "Position": [x, y - .05, z], "Size": [.09, 1.62, 1.62],
            "Color": [255, 255, 255], "Rotation": [0, 0, 90], "Material": "SmoothPlastic",
            "CastShadow": False, "Collide": False, "Shape": "Cylinder", "Class": "Part",
            "Transparency": 0.0, "Role": "hero", "Layer": 4, "Island": "Arena",
        })
        if value == 5:
            out.append({
                "Name": "CellMark", "Position": [x, y + 1.12, z], "Size": [.10, .74, .74],
                "Color": list(kinds[value]), "Rotation": [0, 0, 90], "Material": "Neon",
                "CastShadow": False, "Collide": False, "Shape": "Cylinder", "Class": "Part",
                "Transparency": 0.0, "Role": "hero", "Layer": 4, "Island": "Arena",
            })
        elif value == 10:
            for angle in (38, -38):
                out.append({
                    "Name": "CellMark", "Position": [x, y - .06, z + .62], "Size": [.12, .12, .92],
                    "Color": list(kinds[value]), "Rotation": [0, 0, angle], "Material": "Neon",
                    "CastShadow": False, "Collide": False, "Shape": "Block", "Class": "Part",
                    "Transparency": 0.0, "Role": "hero", "Layer": 4, "Island": "Arena",
                })
    return out


def geometry(parts):
    """Triangles in world space with their flat colour and part metadata."""
    tris, colors, owners = [], [], []
    for index, part in enumerate(parts):
        size = np.array(part["Size"], dtype=float)
        rot = np.radians(part["Rotation"])
        px, py, pz = rot
        sx, sy, sz = math.sin(px), math.sin(py), math.sin(pz)
        cx, cy, cz = math.cos(px), math.cos(py), math.cos(pz)
        matrix = np.array([
            [cy * cz, -cy * sz, sy],
            [cx * sz + sx * sy * cz, cx * cz - sx * sy * sz, -sx * cy],
            [sx * sz - cx * sy * cz, sx * cz + cx * sy * sz, cx * cy],
        ])
        origin = np.array(part["Position"], dtype=float)
        shape = part["Shape"]
        if shape == "Ball":
            theta = np.linspace(0, math.pi, 7)
            phi = np.linspace(0, 2 * math.pi, 13)
            th, ph = np.meshgrid(theta, phi, indexing="ij")
            local = np.stack([
                np.sin(th) * np.cos(ph) * size[0] / 2,
                np.cos(th) * size[1] / 2,
                np.sin(th) * np.sin(ph) * size[2] / 2,
            ], axis=-1).reshape(-1, 3)
            grid = (len(theta), len(phi))
            quads = []
            for i in range(grid[0] - 1):
                for j in range(grid[1] - 1):
                    a = i * grid[1] + j
                    quads.append((a, a + 1, a + grid[1] + 1, a + grid[1]))
        elif shape == "Cylinder":
            # Roblox cylinders run along their local X axis: Size.X is the length,
            # Size.Y/Z the diameter. The world rotates them (0,0,90) to stand up.
            seg = 14 if max(size[1], size[2]) < 40 else 30
            ang = np.linspace(0, 2 * math.pi, seg, endpoint=False)
            left = np.stack([np.full(seg, -size[0] / 2), np.cos(ang) * size[1] / 2, np.sin(ang) * size[2] / 2], axis=-1)
            right = np.stack([np.full(seg, size[0] / 2), np.cos(ang) * size[1] / 2, np.sin(ang) * size[2] / 2], axis=-1)
            local = np.concatenate([left, right, [[-size[0] / 2, 0, 0], [size[0] / 2, 0, 0]]])
            quads = []
            for i in range(seg):
                j = (i + 1) % seg
                quads.append((i, j, j + seg, i + seg))
            low, high = 2 * seg, 2 * seg + 1
            for i in range(seg):
                j = (i + 1) % seg
                quads.append((low, i, j, j))
                quads.append((high, j + seg, i + seg, i + seg))
        else:
            if part["Class"] == "WedgePart":
                # Roblox wedge: a triangular prism, tall at -X? Use a clean prism.
                x, y, z = size / 2
                local = np.array([
                    [-x, -y, -z], [x, -y, -z], [x, -y, z], [-x, -y, z],   # bottom
                    [-x, y, -z], [x, y, -z], [-x, y, z],                   # top ridge
                ])
                quads = [(0, 1, 5, 4), (3, 6, 4, 0), (1, 2, 6, 5),
                         (0, 4, 6, 3), (1, 5, 6, 2), (2, 6, 3, 1), (0, 3, 2, 1)]
            else:
                x, y, z = size / 2
                local = np.array([
                    [-x, -y, -z], [x, -y, -z], [x, -y, z], [-x, -y, z],
                    [-x, y, -z], [x, y, -z], [x, y, z], [-x, y, z],
                ])
                quads = [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1),
                         (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
        world = local @ matrix.T + origin
        for quad in quads:
            for a, b, c in ((quad[0], quad[1], quad[2]), (quad[0], quad[2], quad[3])):
                tris.append(world[[a, b, c]])
                colors.append(part["Color"])
                owners.append(index)
    if not tris:
        return np.zeros((0, 3, 3)), np.zeros((0, 3)), np.zeros(0, dtype=int)
    return np.array(tris), np.array(colors, dtype=float), np.array(owners)


def board_quads(parts, signs, frame):
    """Screen-space quads for each sign panel, so real text can be drawn on them."""
    by_name = {p["Name"]: p for p in parts}
    out = []
    for sign in signs:
        part = by_name.get(sign["Part"])
        if not part:
            continue
        w, h = part["Size"][0] / 2, part["Size"][1] / 2
        rot = math.radians(part["Rotation"][1])
        # Face normal is the part's -Z after yaw; the board's front surface.
        depth = part["Size"][2] / 2 + 0.02
        normal = np.array([-math.sin(rot), 0, -math.cos(rot)])
        right = np.array([math.cos(rot), 0, -math.sin(rot)])
        centre = np.array(part["Position"], dtype=float) + normal * depth
        corners = np.array([
            centre - right * w + np.array([0, h, 0]),
            centre + right * w + np.array([0, h, 0]),
            centre + right * w - np.array([0, h, 0]),
            centre - right * w - np.array([0, h, 0]),
        ])
        screen, depth_z = frame.project(corners)
        if np.any(depth_z <= 0.2):
            continue
        if np.any(screen[:, 0] < -width_guard) or np.any(screen[:, 0] > frame.width + width_guard):
            continue
        to_camera = frame.eye - centre
        if float(np.dot(to_camera, normal)) <= 0:
            continue        # we are behind the board: its face is not visible
        out.append({"name": sign["Part"], "quad": screen, "lines": sign["Lines"],
                    "depth": float(depth_z.mean()), "size": (part["Size"][0], part["Size"][1])})
    return sorted(out, key=lambda item: -item["depth"])


width_guard = 240


def draw_sign_text(image, boards, zbuffer):
    """Approximate the exported SurfaceGui: stacked, centred, bold, warm cream."""
    draw = ImageDraw.Draw(image)
    for board in boards:
        quad = board["quad"]
        top = (quad[0] + quad[1]) / 2
        bottom = (quad[3] + quad[2]) / 2
        left = (quad[0] + quad[3]) / 2
        right = (quad[1] + quad[2]) / 2
        panel_w = float(np.linalg.norm(right - left))
        panel_h = float(np.linalg.norm(bottom - top))
        if panel_w < 78 or panel_h < 26:
            continue        # too small/oblique in frame: skip rather than smear text
        mid = tuple(int(v) for v in (top + bottom) / 2)
        if not (0 <= mid[1] < zbuffer.shape[0] and 0 <= mid[0] < zbuffer.shape[1]):
            continue
        if zbuffer[mid[1], mid[0]] > board["depth"] * 1.02:
            continue        # panel is hidden behind something else
        lines = board["lines"]
        total = sum(line["Fraction"] for line in lines)
        # perspective-correct horizontal scale at the panel centre
        y = 0.06
        for line in lines:
            share = line["Fraction"] / total
            cy = top + (bottom - top) * (y + share / 2)
            probe = (int(cy[0]), int(cy[1]))
            if not (0 <= probe[1] < zbuffer.shape[0] and 0 <= probe[0] < zbuffer.shape[1]):
                y += share
                continue
            if zbuffer[probe[1], probe[0]] > board["depth"] * 1.02:
                y += share
                continue
            font_size = max(6, int(min(panel_h * share * 0.62,
                                       panel_w / max(6, len(line["Text"])) * 1.25,
                                       panel_h * 0.7)))
            font = _font(font_size) if font_size > 9 else _small_font(font_size)
            text = line["Text"]
            width_px = draw.textlength(text, font=font)
            draw.text((float(cy[0]) - width_px / 2, float(cy[1]) - font_size * 0.62), text,
                      font=font, fill=tuple(line["Color"]))
            y += share


def render(parts, path, *, eye, target, fov=58, width=1000, height=580, light=None,
           saturation=1.0, background=None, title=None, transparent=False, signs=None):
    tris, colors, owners = geometry(parts)
    frame = Frame(eye, target, fov, width, height)
    pts, depth = frame.project(tris.reshape(-1, 3))
    pts = pts.reshape(-1, 3, 2)
    depth = depth.reshape(-1, 3)

    # backface culling in screen space
    area = ((pts[:, 1, 0] - pts[:, 0, 0]) * (pts[:, 2, 1] - pts[:, 0, 1])
            - (pts[:, 2, 0] - pts[:, 0, 0]) * (pts[:, 1, 1] - pts[:, 0, 1]))
    keep = (area < 0) & np.all(depth > 0.12, axis=1)
    order = np.argsort(-depth.mean(axis=1))
    keep_order = order[keep[order]]

    # lighting
    n = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    n = normalise(n + 1e-9)
    # outward-facing normals: flip toward the camera
    centres = tris.mean(axis=1)
    to_cam = normalise(frame.eye - centres)
    n = np.where((n * to_cam).sum(axis=1, keepdims=True) < 0, -n, n)

    light = light or {
        "dir": normalise(np.array([-0.55, 0.72, 0.42])),
        "sun": np.array([1.0, 0.94, 0.84]) * 1.05,
        "ambient": np.array([0.46, 0.52, 0.58]),
        "bounce": np.array([0.34, 0.31, 0.25]),
    }
    lambert = np.clip(n @ light["dir"], 0, 1)
    sky_up = np.clip(n[:, 1], 0, 1)
    shade = (light["ambient"] * (0.65 + 0.35 * sky_up)[:, None]
             + light["sun"] * lambert[:, None]
             + light["bounce"] * np.clip(-n[:, 1], 0, 1)[:, None])

    # simple height-based haze
    fog_color = np.array(theme.LIGHTING["FogColor"], dtype=float) / 255 if background is None else np.array(background, dtype=float) / 255
    fog = np.clip((depth.mean(axis=1) - 220) / 900, 0, 0.85)[:, None]

    base = colors / 255.0
    if saturation != 1.0:
        grey = base.mean(axis=1, keepdims=True)
        base = np.clip(grey + (base - grey) * saturation, 0, 1)
    lit = np.clip(base * shade, 0, 1)
    lit = np.where(np.array([p["Material"] == "Neon" for p in parts])[owners][:, None],
                   np.clip(base * 1.12, 0, 1), lit)
    alpha = (1.0 - np.array([p["Transparency"] for p in parts])[owners])[:, None]
    lit = lit * (1 - fog) + fog_color * fog

    img = Image.new("RGB", (width, height))
    zbuffer = np.full((height, width), np.inf)
    canvas = np.zeros((height, width, 3), dtype=np.float32)
    if not transparent:
        canvas[:] = _sky_gradient(width, height, background)
    draw = ImageDraw.Draw(img)

    # group triangles per colour for fewer polygon calls
    for index in keep_order:
        tri = pts[index]
        d = float(depth[index].mean())
        minx, miny = tri[:, 0].min(), tri[:, 1].min()
        maxx, maxy = tri[:, 0].max(), tri[:, 1].max()
        if maxx < 0 or maxy < 0 or minx >= width or miny >= height:
            continue
        iy0, iy1 = max(0, int(miny)), min(height - 1, int(math.ceil(maxy)))
        ix0, ix1 = max(0, int(minx)), min(width - 1, int(math.ceil(maxx)))
        if iy1 < iy0 or ix1 < ix0:
            continue
        xs = np.arange(ix0, ix1 + 1) + 0.5
        ys = np.arange(iy0, iy1 + 1) + 0.5
        gx, gy = np.meshgrid(xs, ys)
        (x0, y0), (x1, y1), (x2, y2) = tri
        denom = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
        if abs(denom) < 1e-9:
            continue
        a = ((y1 - y2) * (gx - x2) + (x2 - x1) * (gy - y2)) / denom
        b = ((y2 - y0) * (gx - x2) + (x0 - x2) * (gy - y2)) / denom
        c = 1 - a - b
        inside = (a >= -1e-6) & (b >= -1e-6) & (c >= -1e-6)
        if not inside.any():
            continue
        z = a * depth[index][0] + b * depth[index][1] + c * depth[index][2]
        sub = zbuffer[iy0:iy1 + 1, ix0:ix1 + 1]
        mask = inside & (z < sub)
        if not mask.any():
            continue
        sub[mask] = z[mask]
        window = canvas[iy0:iy1 + 1, ix0:ix1 + 1]
        a = float(alpha[index][0])
        if a >= 0.999:
            window[mask] = lit[index] * 255
        elif a > 0.02:
            window[mask] = (lit[index] * a + window[mask] * (1 - a)) * 255

    out = Image.fromarray(np.clip(canvas, 0, 255).astype(np.uint8))
    if signs:
        boards = board_quads(parts, signs, frame)
        draw_sign_text(out, boards, zbuffer)
    if title:
        draw = ImageDraw.Draw(out)
        font = _font(22)
        small = _font(13)
        draw.rectangle([0, out.height - 58, out.width, out.height], fill=(18, 24, 28))
        draw.text((18, out.height - 48), title, font=font, fill=(243, 247, 245))
        sub = "stylized preview render (not an engine screenshot)"
        draw.text((18, out.height - 22), sub, font=small, fill=(150, 168, 170))
    out.convert("RGB").save(path, quality=92)
    return out


def _sky_gradient(width, height, background=None):
    """Soft blue sky: warm pale haze at the horizon, cooler blue overhead."""
    if background is not None:
        return np.array(background, dtype=np.float32)[None, None, :] * np.ones((height, width, 3), dtype=np.float32)
    horizon = np.array([222, 232, 238], dtype=np.float32)
    zenith = np.array([150, 186, 224], dtype=np.float32)
    ramp = np.linspace(0, 1, height, dtype=np.float32)[:, None, None] ** 0.75
    column = horizon * (1 - ramp) + zenith * ramp
    return np.repeat(column, width, axis=1)


def _sky_color(background):
    if background is not None:
        return tuple(int(c) for c in background)
    horizon = theme.LIGHTING["FogColor"]
    return tuple(horizon)


def _small_font(size):
    return _font(max(8, size))


def _font(size):
    for candidate in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    ):
        if Path(candidate).exists():
            return ImageFont.truetype(candidate, size)
    return ImageFont.load_default()


# ------------------------------------------------------------------- view set
VIEWS = {
    "arena": dict(
        eye=(104, 74, 118), target=(-2, 22, -6), fov=50, width=1000, height=580,
        title="ARENA — sand court, stone circuit inlay, brain beacon",
    ),
    "lobby": dict(
        eye=(16, 41, 214), target=(2, 29, 157), fov=57, width=1000, height=580,
        title="LOBBY — garden terrace, entrance portal and framed signage",
    ),
    "palms": dict(
        eye=(96, 38, 40), target=(73, 22, 4), fov=52, width=1000, height=580,
        title="SATELLITE — tropical palms, boulders and a warm waypoint lantern",
    ),
    "play": dict(
        eye=(30, 33, 36), target=(-6, 24, -8), fov=70, width=1000, height=580,
        title="PLAYER EYE — Brain Cells read clearly over sand and stone",
    ),
    "cast": dict(
        eye=(0, 29.6, 11.6), target=(0, 27.6, 0), fov=46, width=1000, height=560,
        title="THE CAST — six original critters: brain/frog +1, fish/goose +5, toast/sock +10",
        lineup=True,
    ),
    "overview": dict(
        eye=(168, 158, 236), target=(0, 20, 46), fov=48, width=1180, height=620,
        title="OVERVIEW — arena, four satellites, garden lobby",
    ),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", action="append", choices=sorted(VIEWS))
    parser.add_argument("--legacy", action="store_true")
    parser.add_argument("--scale", type=float, default=1.0)
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    world = make_world()
    if args.legacy:
        pick = legacy_palette()
        recolored = [dict(p, Color=pick(p)) for p in world["Parts"]]
        parts = add_cells(recolored, world["PickupPositions"])
        light = {
            "dir": normalise(np.array([-0.35, 0.86, 0.36])),
            "sun": np.array([1.0, 0.98, 0.94]) * 1.08,
            "ambient": np.array([0.58, 0.52, 0.80]),
            "bounce": np.array([0.36, 0.30, 0.62]),
        }
        suffix = "-legacy"
    else:
        parts = add_cells(world["Parts"], world["PickupPositions"])
        light = None
        suffix = ""
    chosen = args.only or [name for name in VIEWS if name != "cast"]
    for name in chosen:
        view = dict(VIEWS[name])
        view["width"] = int(view["width"] * args.scale)
        view["height"] = int(view["height"] * args.scale)
        lineup = view.pop("lineup", False)
        path = OUT / f"{name}{suffix}.jpg"
        if lineup:
            # A neutral studio plinth so the cast is judged on its own silhouette.
            stage = [{
                "Name": "CastStage", "Position": [0, 26.2, 0], "Size": [26, .6, 14],
                "Color": [66, 82, 88], "Rotation": [0, 0, 0], "Material": "Slate",
                "CastShadow": False, "Collide": False, "Shape": "Block", "Class": "Part",
                "Transparency": 0.0, "Role": "hero", "Layer": 4, "Island": "Arena",
            }, {
                "Name": "CastBackdrop", "Position": [0, 30.0, -6.4], "Size": [26, 13, .6],
                "Color": [52, 66, 72], "Rotation": [0, 0, 0], "Material": "Slate",
                "CastShadow": False, "Collide": False, "Shape": "Block", "Class": "Part",
                "Transparency": 0.0, "Role": "hero", "Layer": 4, "Island": "Arena",
            }]
            studio = {"dir": normalise(np.array([-0.32, 0.80, 0.52])),
                      "sun": np.array([1.0, 0.98, 0.95]) * .94,
                      "ambient": np.array([0.44, 0.50, 0.56]),
                      "bounce": np.array([0.26, 0.30, 0.34])}
            render(stage + cast_lineup((0, 27.0, 0)), path, signs=[], light=studio, **view)
            continue
        render(parts, path, signs=world["Signs"], light=light, **view)
        print(f"wrote {path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
