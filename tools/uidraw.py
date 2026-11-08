#!/usr/bin/env python3
"""Render the HUD exactly as specified in tools/ui.py — the UI review artefact.

Roblox Studio is not available here, so this draws the interface from the *same*
design data the runtime HUD uses (`tools/ui.py` -> generated `src/client/Theme.luau`).
Every colour, type size, radius and copy string below comes from that module, so a
plate cannot drift from the game without the art gate failing.

Layout is a faithful transcription of `src/client/Hud.luau:resize()` at the given
viewport, including the responsive rules: brand lockup hidden on phones, clock
shrinking before the RANKS chip, action bar lifted above the thumbstick zones.

    python3 tools/uidraw.py                      # desktop, laptop, phone, shop
    python3 tools/uidraw.py --only phone         # a single plate

It is a flat 2D mock, not an engine screenshot, and it says so on the plate.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import creatures  # noqa: E402
import preview  # noqa: E402
import ui  # noqa: E402

OUT = ROOT / "docs" / "previews"
C = ui.COLORS
A = ui.ALPHA
T = ui.TYPE
SP = ui.SPACE
COPY = ui.COPY


# --------------------------------------------------------------------------- #
# tiny drawing kit mirroring src/client/Kit.luau
# --------------------------------------------------------------------------- #
def font(size, bold=True):
    path = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold \
        else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
    return ImageFont.truetype(path, max(8, int(size)))


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def rgba(color, alpha):
    return (color[0], color[1], color[2], int(round(alpha * 255)))


class Canvas:
    """Accumulates RGBA layers so translucency composites like the engine does."""

    def __init__(self, width, height, background):
        self.width, self.height = width, height
        self.image = Image.new("RGBA", (width, height), tuple(background) + (255,))
        self.draw = ImageDraw.Draw(self.image)

    def panel(self, x, y, w, h, *, color="Navy", alpha=None, radius=None,
              edge="NavyEdge", edge_alpha=None, gradient=True):
        radius = ui.RADIUS if radius is None else radius
        # `alpha` is transparency, matching BackgroundTransparency in the engine.
        transparency = A["Panel"] if alpha is None else alpha
        opacity = 1.0 - transparency
        edge_alpha = A["Hairline"] if edge_alpha is None else edge_alpha
        base = C[color]
        layer = Image.new("RGBA", (self.width, self.height), (0, 0, 0, 0))
        draw = ImageDraw.Draw(layer)
        top = mix(base, C["NavyRaised"], 0.55) if gradient else base
        # vertical gradient inside a rounded mask
        mask = Image.new("L", (self.width, self.height), 0)
        ImageDraw.Draw(mask).rounded_rectangle([x, y, x + w - 1, y + h - 1], radius, fill=255)
        body = Image.new("RGBA", (self.width, self.height), (0, 0, 0, 0))
        body_draw = ImageDraw.Draw(body)
        for row in range(int(h)):
            t = row / max(1, h - 1)
            body_draw.line([(x, y + row), (x + w, y + row)], fill=rgba(mix(top, base, t), opacity))
        layer = Image.composite(body, layer, mask)
        self.image.alpha_composite(layer)
        self.draw = ImageDraw.Draw(self.image)
        self.draw.rounded_rectangle([x, y, x + w - 1, y + h - 1], radius,
                                    outline=rgba(C[edge], edge_alpha), width=1)
        return self

    def rect(self, x, y, w, h, color, alpha=1.0, radius=0):
        base = C[color] if isinstance(color, str) else color
        if radius:
            self.draw.rounded_rectangle([x, y, x + w - 1, y + h - 1], radius, fill=rgba(base, alpha))
        else:
            self.draw.rectangle([x, y, x + w - 1, y + h - 1], fill=rgba(base, alpha))
        return self

    def text(self, x, y, value, size, *, color="White", bold=True, anchor="la",
             alpha=1.0, width=None, spacing=1.0):
        f = font(size, bold)
        base = C[color] if isinstance(color, str) else color
        if width is not None:
            # emulate TextTruncate/TextWrapped by clipping to the given width
            while value and self.draw.textlength(value, font=f) > width:
                value = value[:-1]
        self.draw.text((x, y), value, font=f, fill=rgba(base, alpha), anchor=anchor)
        return self

    def text_height(self, size):
        ascent, descent = font(size).getmetrics()
        return ascent + descent


# --------------------------------------------------------------------------- #
# glyphs: frames and corners only, same construction as the runtime
# --------------------------------------------------------------------------- #
def glyph(canvas, x, y, kind, accent, size=20):
    u = size / 20.0
    a = C[accent]
    def piece(w, h, px, py, round_=None, alpha=1.0):
        if round_:
            canvas.rect(x + px * u, y + py * u, w * u, h * u, a, alpha, round_ * u)
        else:
            canvas.rect(x + px * u, y + py * u, w * u, h * u, a, alpha)
    if kind == "cell":
        piece(9, 9, 5.5, 2, 9)
        piece(8, 8, 2, 8, 8)
        piece(8, 8, 9, 8.5, 8)
        piece(3, 4, 8.5, 15, 2, 0.4)
    elif kind == "coin":
        piece(18, 18, 1, 1, 18)
        canvas.rect(x + 5.5 * u, y + 5.5 * u, 9 * u, 9 * u, C["Navy"], 1.0, 9 * u)
    elif kind == "clock":
        piece(18, 18, 1, 1, 18, 0.45)
        piece(2, 6, 9, 4, 1)
        piece(5, 2, 9, 9, 1)
    elif kind == "shop":
        piece(14, 12, 3, 6, 3)
        piece(8, 5, 6, 2, 5, 0.45)
    elif kind == "inventory":
        for row in range(2):
            for column in range(2):
                piece(7, 7, 3 + column * 8, 3 + row * 8, 2, 0.5 if (row == 0 and column == 1) else 1.0)
    elif kind == "settings":
        piece(12, 12, 4, 4, 12, 0.45)
        piece(6, 6, 7, 7, 6)
        import math
        for i in range(4):
            angle = i * math.pi / 2
            piece(3, 5, 8.5 + math.cos(angle) * 7, 8.5 + math.sin(angle) * 7, 1)
    elif kind == "rank":
        piece(8, 8, 3, 3, 2)
    elif kind == "specimen":
        # a pinned specimen: a disc on a stem
        piece(12, 12, 4, 2, 12, 0.55)
        piece(3, 9, 8.5, 11, 1)


# --------------------------------------------------------------------------- #
# the interface, transcribed from Hud.luau / Panels.luau
# --------------------------------------------------------------------------- #
def draw_hud(canvas, state):
    """state: dict with phase, clock, cells, coins, rows, modal, results, viewport."""
    width, height = canvas.width, canvas.height
    compact = width < 780
    short = height < 520
    pad = SP["md"]

    # ---- top HUD -------------------------------------------------------- #
    if not (compact or short):
        canvas.text(SP["xl"], SP["lg"], COPY["BrandTop"], T["Title"], color="White")
        canvas.rect(SP["xl"] + 1, SP["lg"] + 27, 34, 3, "Cyan", radius=2)
        canvas.text(SP["xl"] + 1, SP["lg"] + 32, COPY["BrandBottom"], T["Label"], color="Violet")
        canvas.text(SP["xl"] + 2, SP["lg"] + 47, COPY["BrandTag"], T["Micro"], color="Muted", bold=False)

    # brain cells
    cell_w = 128 if compact else 196
    cell_h = 44 if short else 52
    cell_x = pad if compact else SP["xl"]
    cell_y = pad if compact else 78
    canvas.panel(cell_x, cell_y, cell_w, cell_h)
    glyph(canvas, cell_x + pad, cell_y + pad + 2, "cell", "Cyan", 22)
    canvas.text(cell_x + 40, cell_y + 6, str(state["cells"]), 24 if compact else T["Title"],
                color="White")
    canvas.text(cell_x + 41, cell_y + 31, COPY["CellsLabel"], T["Micro"], color="Muted", bold=False)

    # round clock
    clock_width = max(132, min(width - 340, 212)) if not compact else max(96, min(width - 368, 190))
    clock_h = 62 if short else 76
    clock_x = (width - clock_width) // 2
    clock_y = SP["sm"] if short else SP["lg"]
    canvas.panel(clock_x, clock_y, clock_width, clock_h, color="NavyRaised")
    phase_color = {"Playing": "Cyan", "Results": "Amber"}.get(state["phase"], "Violet")
    canvas.text(clock_x + clock_width / 2, clock_y + 14, state["phaseLabel"], T["Label"],
                color=phase_color, anchor="mm")
    canvas.text(clock_x + clock_width / 2, clock_y + 40, state["clock"],
                26 if short else (30 if compact else T["Display"]), color="White", anchor="mm")
    if not short:
        canvas.rect(clock_x + 30, clock_y + 60, clock_width - 60, 1, "NavyEdge", A["Hairline"])
        round_label = "ROUND 04" if compact else state["roundLabel"]
        canvas.text(clock_x + clock_width / 2, clock_y + 69, round_label, T["Micro"],
                    color="Dim", bold=False, anchor="mm", width=clock_width - 20)

    # coins
    coin_w = 112 if compact else 152
    coin_h = 44 if short else 52
    coin_x = width - pad - coin_w
    coin_y = SP["sm"] if compact else SP["lg"]
    canvas.panel(coin_x, coin_y, coin_w, coin_h)
    glyph(canvas, coin_x + pad, coin_y + pad + 2, "coin", "Amber", 22)
    canvas.text(coin_x + 40, coin_y + 6, str(state["coins"]), 18 if compact else T["Title"],
                color="Amber")
    canvas.text(coin_x + 41, coin_y + 31, COPY["CoinsLabel"], T["Micro"], color="Muted", bold=False)

    # ---- leaderboard (right) -------------------------------------------- #
    # Mirrors Hud:resize — the board is hidden on phone-width viewports until the
    # player taps RANKS, so it never covers the centre messaging.
    board_visible = state.get("board", True) and not (compact and not state.get("ranksTouched"))
    board_w = 196 if compact else 232
    board_h = int(np.clip(height - (190 if compact else 230), 150, 320))
    board_x = width - pad - board_w
    board_y = 118 if compact else 162
    if board_visible:
        canvas.panel(board_x, board_y, board_w, board_h)
        canvas.text(board_x + pad, board_y + pad, COPY["BoardTitle"], T["Heading"], color="White")
        canvas.text(board_x + pad, board_y + pad + 19, COPY["BoardSub"], T["Micro"], color="Dim",
                    bold=False)
        canvas.rect(board_x + pad, board_y + pad + 35, board_w - pad * 2, 1, "NavyEdge", A["Hairline"])
        roster_y = board_y + pad + 42
        for index, row in enumerate(state["rows"][:6]):
            row_y = roster_y + index * 34
            mine = row.get("mine")
            canvas.panel(board_x + pad - 2, row_y, board_w - pad * 2 + 4, 30,
                         color="NavyRaised", alpha=A["PanelRaised"] if mine else 0.5, radius=9,
                         edge_alpha=0.0, gradient=False)
            accent = "Amber" if index == 0 else ("Cyan" if mine else "NavyEdge")
            canvas.rect(board_x + pad - 2, row_y + 6, 3, 18, accent,
                        1.0 if (index == 0 or mine) else 0.5, radius=2)
            canvas.text(board_x + pad + 6, row_y + 15, f"{index + 1:02d}", T["Micro"],
                        color="Amber" if index == 0 else "Dim", bold=False, anchor="lm")
            canvas.text(board_x + pad + 30, row_y + 15, row["name"] + ("  • you" if mine else ""),
                        T["Label"], color="White", anchor="lm", width=board_w - pad * 2 - 78)
            canvas.text(board_x + board_w - pad - 6, row_y + 15, str(row["score"]), T["Body"],
                        color="Amber" if index == 0 else "Cyan", anchor="rm")
    if compact or short:
        # RANKS chip, right-aligned under the coin counter
        chip_w, chip_h = (68 if compact else 84), 32
        chip_x = width - pad - chip_w
        chip_y = 40 if short else (74 if compact else 128)
        canvas.panel(chip_x, chip_y, chip_w, chip_h, color="NavyRaised", radius=12)
        canvas.text(chip_x + chip_w / 2, chip_y + chip_h / 2, "RANKS", T["Micro"], color="Violet",
                    anchor="mm")

    # SPECIMENS chip: the way into the collection log, under the coin counter.
    # Mirrors Panels.topHud: Cyan until all six are logged, then Amber.
    spec_w, spec_h = (112 if short else 116), 30
    spec_x = width - pad - spec_w
    spec_y = coin_y + coin_h + SP["xs"]
    caught = state.get("specimens", 0)
    spec_color = "Amber" if caught >= 6 else "Cyan"
    canvas.panel(spec_x, spec_y, spec_w, spec_h, color="NavyRaised", radius=11)
    glyph(canvas, spec_x + 9, spec_y + 6, "specimen", spec_color, 16)
    canvas.text(spec_x + 30, spec_y + spec_h / 2 + 1,
                f"SPECIMENS {caught} / 6", T["Micro"], color=spec_color, anchor="lm",
                width=spec_w - 38)

    # help chip
    help_x = pad if compact else SP["xl"]
    help_y = 74 if compact else 136
    canvas.panel(help_x, help_y, 36, 36, color="NavyRaised", radius=12)
    canvas.text(help_x + 18, help_y + 18, "?", T["Body"], color="Cyan", anchor="mm")

    # ---- centre messaging ----------------------------------------------- #
    if state.get("lobby") is not None:
        lobby_w = min(width - 32, 420)
        lobby_x = (width - lobby_w) // 2
        lobby_y = 186 if short else 236
        canvas.panel(lobby_x, lobby_y, lobby_w, 92)
        canvas.text(lobby_x + lobby_w / 2, lobby_y + SP["md"] + 10, COPY["LobbyWelcome"], T["Heading"],
                    color="White", anchor="mm")
        canvas.text(lobby_x + lobby_w / 2, lobby_y + SP["md"] + 22 + 7, COPY["LobbySub"], T["Micro"],
                    color="Muted", bold=False, anchor="mm")
        canvas.text(lobby_x + lobby_w / 2, lobby_y + SP["md"] + 44 + 8, state["phaseLabel"],
                    T["Label"], color="Amber" if state["phase"] == "Results" else "Cyan", anchor="mm")
        canvas.text(lobby_x + lobby_w / 2, lobby_y + SP["md"] + 64 + 7, state["lobbyCountdown"],
                    T["Micro"], color="Dim", bold=False, anchor="mm")
    if state.get("event"):
        event_w = min(width - 40, 320)
        event_x = (width - event_w) // 2
        event_y = 146 if short else 174
        canvas.panel(event_x, event_y, event_w, 34, color="NavyRaised")
        canvas.rect(event_x + SP["md"], event_y + 13, 8, 8, "Cyan", radius=8)
        canvas.text(event_x + 30, event_y + 17, state["event"], T["Label"], color="Cyan", anchor="lm")
    if state.get("toast"):
        toast_w = min(width - 32, 432)
        toast_x = (width - toast_w) // 2
        toast_y = 84 if short else 112
        canvas.panel(toast_x, toast_y, toast_w, 56)
        canvas.rect(toast_x + SP["md"], toast_y + 10, 4, 36, "Cyan", radius=2)
        canvas.text(toast_x + 32, toast_y + 28, state["toast"], T["Body"], color="White", anchor="lm",
                    width=toast_w - 52)

    # ---- results card --------------------------------------------------- #
    if state.get("results"):
        card_w, card_h = min(width - 32, 468), min(height - 32, 268)
        card_x, card_y = (width - card_w) // 2, int(height * 0.44 - card_h / 2)
        canvas.panel(card_x, card_y, card_w, card_h)
        cx = card_x + card_w / 2
        canvas.text(cx, card_y + SP["xl"] + 8, COPY["ResultsStatus"], T["Label"], color="Cyan", anchor="mm")
        canvas.text(cx, card_y + SP["xl"] + 44, COPY["WinBanner"], T["Display"], color="Amber", anchor="mm")
        canvas.text(cx, card_y + SP["xl"] + 96, state["winner"], T["Heading"], color="White", anchor="mm")
        canvas.text(cx, card_y + SP["xl"] + 131, state["cast"], T["Micro"], color="Dim", bold=False,
                    anchor="mm", width=card_w - 48)
        canvas.rect(card_x + SP["xl"], card_y + 146, card_w - SP["xl"] * 2, 1, "NavyEdge", A["Hairline"])
        canvas.text(cx, card_y + 173, state["reward"], T["Title"], color="Amber", anchor="mm")
        canvas.text(cx, card_y + 211, state["next"], T["Micro"], color="Muted", bold=False, anchor="mm")

    # ---- rarity key + action bar ---------------------------------------- #
    bar_lift = 118 if compact else SP["lg"]
    bar_w = 252 if compact else 268
    bar_x = (width - bar_w) // 2
    bar_y = height - bar_lift - 52
    if not (compact or short):
        legend_w = 368
        legend_x = (width - legend_w) // 2
        legend_y = height - bar_lift - 52 - 32
        canvas.panel(legend_x, legend_y, legend_w, 26, alpha=0.3, radius=10)
        for index, (label, accent) in enumerate((("+1  BRAIN / FROG", "Cyan"),
                                                 ("+5  FISH / GOOSE", "Amber"),
                                                 ("+10  TOAST / SOCK", "Violet"))):
            slot_x = legend_x + 6 + index * 120
            glyph(canvas, slot_x + 3, legend_y + 5, "cell", accent, 16)
            canvas.text(slot_x + 24, legend_y + 13, label, T["Micro"], color=accent, bold=False,
                        anchor="lm", width=100)

    for index, (kind, label, accent) in enumerate((("shop", COPY["ShopBar"], "Amber"),
                                                   ("inventory", COPY["InventoryBar"], "Cyan"),
                                                   ("settings", COPY["SettingsBar"], "Violet"))):
        button_w = 76 if compact else 84
        step = 84 if compact else 92
        button_x = bar_x + index * step
        canvas.panel(button_x, bar_y, button_w, 52, color="NavyRaised", radius=12)
        canvas.rect(button_x, bar_y + 5, 3, 42, accent, 1.0, radius=2)
        glyph(canvas, button_x + button_w / 2 - 10, bar_y + 10, kind, accent, 20)
        canvas.text(button_x + button_w / 2, bar_y + 38, label.strip(), T["Micro"], color="Muted",
                    bold=False, anchor="mm", width=button_w - 8)

    # plate caption: this is a mock, and it says so
    canvas.rect(0, height - 22, width, 22, "Void", 0.75)
    canvas.text(10, height - 11, f"{width}x{height}  •  HUD mock rendered from tools/ui.py "
                "(not an engine screenshot)", 10, color="Muted", bold=False, anchor="lm")


def _backdrop(width, height):
    """Cover-crop the arena preview render so the mock sits on the real scene."""
    source = OUT / "arena.jpg"
    if not source.is_file():
        return None
    image = Image.open(source).convert("RGBA")
    # drop the renderer's own caption strip so the plate has no stale text on it
    image = image.crop((0, 0, image.width, image.height - 58))
    scale = max(width / image.width, height / image.height)
    resized = image.resize((int(image.width * scale + 0.5), int(image.height * scale + 0.5)),
                           Image.LANCZOS)
    left = (resized.width - width) // 2
    top = int((resized.height - height) * 0.45)
    return resized.crop((left, top, left + width, top + height))


def scrim(canvas, x, height, top=True):
    """Soft navy gradient at the screen edge, matching Kit.scrim."""
    x, height = int(x), int(height)
    strength = 0.62
    layer = Image.new("RGBA", (canvas.width, canvas.height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    y0 = 0 if top else canvas.height - height
    for row in range(height):
        t = row / max(1, height - 1)
        edge = strength * 0.9 if top else strength * 0.9
        alpha = (strength * 0.9) + (1 - strength * 0.9) * t if top else \
            (strength * 0.9) + (1 - strength * 0.9) * (1 - t)
        # approximate the NumberSequence curve (0 -> .9, .55 -> .35, 1 -> 1)
        # mirrors Kit.scrim: 0.8 at the edge, easing to nothing at the inner end
        strength = 0.8
        edge_t = (1 - t) if top else t
        alpha = strength * (0.55 + 0.45 * edge_t ** 1.6)
        draw.line([(0, y0 + row), (canvas.width, y0 + row)],
                  fill=(C["Void"][0], C["Void"][1], C["Void"][2], int(255 * alpha)))
    canvas.image.alpha_composite(layer)
    canvas.draw = ImageDraw.Draw(canvas.image)


def modal_card(canvas, width, height, compact, short, modal):
    overlay = Image.new("RGBA", (width, height), rgba(C["Void"], 0.35))
    canvas.image.alpha_composite(overlay)
    canvas.draw = ImageDraw.Draw(canvas.image)
    card_w, card_h = min(width - 28, 468), min(height - 24, 348)
    card_x, card_y = (width - card_w) // 2, (height - card_h) // 2
    canvas.panel(card_x, card_y, card_w, card_h, alpha=0.04)
    inset = SP["xl"]
    canvas.text(card_x + inset, card_y + inset, modal["title"], 18 if compact else T["Title"],
                color=modal["accent"])
    y = card_y + inset + 34
    line_h = 19
    for line in modal["body"].split("\n"):
        canvas.text(card_x + inset, y, line, 12 if short else (13 if compact else T["Body"]),
                    color="White", bold=False, width=card_w - inset * 2)
        y += line_h
    if modal.get("primary"):
        primary_y = card_y + card_h - inset - 44
        canvas.panel(card_x + inset, primary_y, card_w - inset * 2, 44, color="NavyRaised", radius=12)
        canvas.rect(card_x + inset, primary_y + 5, 3, 34, modal["accent"], radius=2)
        canvas.text(card_x + card_w / 2, primary_y + 22, modal["primary"], T["Label"],
                    color="White", anchor="mm")
        chips_y = primary_y - 44
    else:
        chips_y = card_y + card_h - inset - 34
    for offset, (chip, accent) in enumerate((("SFX ON", "Cyan"), ("MOTION: FULL", "Violet"))):
        chip_w = 110 if offset == 0 else 132
        chip_x = card_x + inset + (0 if offset == 0 else 118)
        canvas.panel(chip_x, chips_y, chip_w, 34, color="NavyRaised", radius=12)
        canvas.text(chip_x + chip_w / 2, chips_y + 17, chip, T["Micro"], color="White", anchor="mm")
    close = 36
    canvas.panel(card_x + card_w - inset - close, card_y + inset - 4, close, close,
                 color="NavyRaised", radius=12)
    canvas.text(card_x + card_w - inset - close / 2, card_y + inset + 14, "X", T["Body"],
                color="Muted", anchor="mm")


_THUMBS = {}


def specimen_thumb(name, width, height):
    """One character rendered by the arena's own renderer, on a dark card stage.

    Same part table, same tint and same camera maths as the in-game viewport, so a
    card on this plate cannot show a different creature from the one in the arena.
    """
    key = (name, width, height)
    if key in _THUMBS:
        return _THUMBS[key]
    value = creatures.CREATURES[name]["Value"]
    base = preview.kinds_by_value[value]
    parts = preview.creature_parts(name, 0, 0, 0, base, yaw=0.0)
    plinth_w, plinth_h, _ = creatures.EXHIBIT["Plinth"]
    bottom = creatures.bottom_of(name)
    parts.append({
        "Name": "ThumbPlinth", "Position": [0, bottom - .10, 0],
        "Size": [plinth_w, .12, plinth_w], "Color": [22, 30, 48],
        "Rotation": [0, 0, 0], "Material": "SmoothPlastic", "CastShadow": False,
        "Collide": False, "Shape": "Block", "Class": "Part", "Transparency": 0.0,
        "Role": "hero", "Layer": 3, "Island": "Lobby",
    })
    studio = {"dir": preview.normalise(np.array([-0.30, 0.78, 0.55])),
              "sun": np.array([1.0, 0.97, 0.92]) * 1.02,
              "ambient": np.array([0.42, 0.46, 0.54]),
              "bounce": np.array([0.24, 0.26, 0.30])}
    path = OUT / "_thumb.jpg"
    OUT.mkdir(parents=True, exist_ok=True)
    centre = (creatures.top_of(name) + bottom) / 2
    image = preview.render(
        parts, path, eye=(0, centre + .26, 4.1), target=(0, centre, 0), fov=30,
        width=width, height=height, light=studio, background=(14, 20, 34),
        transparent=True,
    )
    path.unlink(missing_ok=True)
    _THUMBS[key] = image
    return image


def draw_collection(canvas, state):
    """The specimen log, transcribed from src/client/Collection.luau:resize().

    Six cards, three across on desktop and two on phones; each card is a viewport
    with the real model on a plinth, its name, rarity, reward and whether it has
    been caught. Uncaught cards are dimmed silhouettes that read NOT SEEN YET.
    """
    width, height = canvas.width, canvas.height
    compact = width < 780
    pad = SP["md"]
    entries = state["specimens_entries"]
    caught_names = set(state.get("caught") or ())

    canvas.rect(0, 0, width, height, "Void", .18)
    px, py = (12 if compact else 24), (12 if compact else 24)
    pw, ph = width - px * 2, height - py * 2
    canvas.panel(px, py, pw, ph, color="Navy", radius=18)

    canvas.text(px + SP["xl"], py + SP["xl"], COPY["CollectionTitle"],
                18 if compact else T["Title"], color="White")
    if not compact:
        canvas.text(px + SP["xl"], py + SP["xl"] + 28,
                    "%d / 6 CHARACTERS LOGGED  •  %d CELLS CAUGHT THIS SESSION  •  %d COINS"
                    % (len(caught_names), state.get("cells", 0), state.get("coins", 0)),
                    T["Label"], color="Muted", bold=False)
        canvas.text(px + SP["xl"], py + SP["xl"] + 46, COPY["CollectionHint"],
                    T["Micro"], color="Dim", bold=False)
    canvas.text(px + pw - 36 - SP["md"], py + SP["xl"] + 2,
                "%d / 6" % len(caught_names), T["Title"],
                color="Amber" if len(caught_names) == 6 else "Cyan", anchor="ra")
    canvas.panel(px + pw - 36, py + SP["xl"], 36, 36, color="NavyRaised", radius=12)
    canvas.text(px + pw - 18, py + SP["xl"] + 18, "X", T["Body"], color="Muted", anchor="mm")

    columns = 2 if compact else 3
    grid_x = px + SP["xl"]
    grid_y = py + SP["xl"] + 64
    grid_w = pw - SP["xl"] * 2
    grid_h = py + ph - SP["xl"] - grid_y
    cell_w = (grid_w - (columns - 1) * 10) // columns
    cell_h = min(196 if not compact else 178, (grid_h - 10) // 2)
    rows = (len(entries) + columns - 1) // columns
    # Centre the block vertically: the log is a full screen, not a top-left list.
    grid_y += max(0, (grid_h - (rows * (cell_h + 10) - 10)) // 2)
    for index, entry in enumerate(entries):
        caught = entry["name"] in caught_names
        rarity = entry["rarity"]
        accent = {"Common": "Cyan", "Rare": "Amber", "Legendary": "Violet"}[rarity]
        cx = grid_x + (index % columns) * (cell_w + 10)
        cy = grid_y + (index // columns) * (cell_h + 10)
        canvas.panel(cx, cy, cell_w, cell_h, color="NavyRaised", radius=12,
                     alpha=0.5, edge=accent, edge_alpha=A["Hairline"] if not caught else 0.55)
        # viewport: dim silhouette when uncaught, full colour when caught
        view_h = cell_h - 88
        canvas.rect(cx + 2, cy + 2, cell_w - 4, view_h, "Navy", 1.0, 10)
        thumb = specimen_thumb(entry["name"], 260, max(48, int(260 * view_h / (cell_w - 4))))
        thumb = thumb.resize((int(cell_w - 4), int(view_h)), Image.LANCZOS)
        if not caught:
            # Silhouette: same shape, no colour — you can see what you are missing.
            grey = thumb.convert("L").convert("RGB")
            grey = Image.eval(grey, lambda v: int(v * 0.30))
            thumb = Image.blend(thumb, grey, 0.88)
            thumb = Image.eval(thumb, lambda v: int(v * 0.55))
        canvas.image.alpha_composite(thumb.convert("RGBA"), (int(cx + 2), int(cy + 2)))
        canvas.draw = ImageDraw.Draw(canvas.image)
        canvas.rect(cx + 10, cy + cell_h - 72, 10, 10, accent if caught else "Dim", 1.0, 10)
        canvas.text(cx + 24, cy + cell_h - 84, entry["label"], T["Label"],
                    color="White" if caught else "Dim", width=cell_w - 34)
        canvas.text(cx + 24, cy + cell_h - 66,
                    "%s  +%d" % (rarity.upper(), entry["value"]), T["Micro"],
                    color=accent, alpha=1.0 if caught else 0.45, width=cell_w - 34)
        canvas.text(cx + 9, cy + cell_h - 50,
                    COPY["CollectionCount"] + "  ×" + str(entry["caught"]) if caught
                    else COPY["CollectionMissing"],
                    T["Body"], color="Muted" if caught else "Dim", width=cell_w - 16)
        canvas.text(cx + 9, cy + cell_h - 30, entry["blurb"], T["Micro"],
                    color="Dim", bold=False, width=cell_w - 16)


def mock(kind, width, height, **overrides):
    state = {
        "phase": "Intermission",
        "phaseLabel": COPY["IntermissionStatus"],
        "clock": "00:09",
        "cells": 0,
        "coins": 0,
        "rows": [
            {"name": "MintBrain", "score": 0},
            {"name": "Orbital", "score": 0},
        ],
        "roundLabel": "ROUND 04  •  BRAINROT ARENA",
        "lobby": True,
        "lobbyCountdown": "ARENA OPENS IN 00:09",
        "event": None,
        "toast": None,
        "results": False,
        "modal": None,
        "board": True,
    }
    if kind == "play":
        state.update({
            "phase": "Playing", "phaseLabel": COPY["PlayingStatus"], "clock": "02:41",
            "cells": 27, "coins": 55, "lobby": None,
            "rows": [
                {"name": "MintBrain", "score": 34, "mine": True},
                {"name": "Orbital", "score": 27},
                {"name": "WetSock", "score": 22},
                {"name": "Toaster", "score": 18},
                {"name": "GooseCab", "score": 11},
            ],
            "event": "LOW GRAVITY  •  00:18",
            "toast": "Orbital claimed the Toast Sock  •  +10",
            "roundLabel": "ROUND 04  •  BRAINROT ARENA",
        })
    elif kind == "results":
        state.update({
            "phase": "Results", "phaseLabel": COPY["ResultsStatus"], "clock": "00:06",
            "cells": 34, "coins": 97, "lobby": True,
            "lobbyCountdown": "NEXT ROUND IN 00:06",
            "rows": [
                {"name": "MintBrain", "score": 34, "mine": True},
                {"name": "Orbital", "score": 27},
                {"name": "WetSock", "score": 22},
            ],
            "results": True,
            "winner": "MintBrain wins!\n34 brain cells",
            "cast": "Toast  •  burnt, beloved, worth ten",
            "reward": "+97 COINS",
            "next": "INTERMISSION IN 00:06",
        })
    elif kind == "shop":
        state.update({
            "phase": "Playing", "phaseLabel": COPY["PlayingStatus"], "clock": "02:41",
            "cells": 27, "coins": 55, "lobby": None,
            "rows": [
                {"name": "MintBrain", "score": 34, "mine": True},
                {"name": "Orbital", "score": 27},
                {"name": "WetSock", "score": 22},
            ],
            "modal": {
                "title": COPY["ShopTitle"], "accent": "Amber",
                "body": COPY["ShopBody"] + "\n\nPULSE HALO — 100 session coins.\n\nBalance: 55 coins.",
                "primary": "UNLOCK  •  100",
            },
        })
    elif kind == "inventory":
        state.update({
            "phase": "Playing", "phaseLabel": COPY["PlayingStatus"], "clock": "02:41",
            "cells": 27, "coins": 97, "lobby": None,
            "rows": [
                {"name": "MintBrain", "score": 34, "mine": True},
                {"name": "Orbital", "score": 27},
            ],
            "modal": {
                "title": COPY["InventoryTitle"], "accent": "Cyan",
                "body": "ROUND SCORE      34\nROUNDS WON      2\nCELLS CLAIMED   31\nSESSION COINS   97\n\nPULSE HALO      EQUIPPED",
                "primary": "UNEQUIP",
            },
        })
    elif kind == "settings":
        state.update({
            "modal": {
                "title": COPY["SettingsTitle"], "accent": "Violet",
                "body": "Sound effects: ON\nMotion: FULL\n\nREDUCED MOTION turns off camera-shaking "
                        "effects, halo breathing and\npanel transitions. It never changes gameplay.",
                "primary": None,
            },
        })
    elif kind.startswith("collection"):
        caught = {"brain", "frog", "fish"} if kind != "collection-full" else None
        entries = []
        for index, order in enumerate([n for value in (1, 5, 10) for n in creatures.FAMILY[value]]):
            spec = creatures.CREATURES[order]
            entries.append({
                "name": order, "label": spec["Label"], "rarity": spec["Rarity"],
                "value": spec["Value"], "blurb": spec["Blurb"].upper(),
                "caught": 3 + index,
            })
        state.update({
            "phase": "Playing", "phaseLabel": COPY["PlayingStatus"], "clock": "02:41",
            "cells": 27, "coins": 55, "lobby": None, "specimens": 3,
            "rows": [
                {"name": "MintBrain", "score": 34, "mine": True},
                {"name": "Orbital", "score": 27},
                {"name": "WetSock", "score": 22},
            ],
            "specimens_entries": entries,
            "caught": (caught if caught is not None else [e["name"] for e in entries]),
        })
    state.update(overrides)
    canvas = Canvas(width, height, C["Void"])
    backdrop = _backdrop(width, height)
    if backdrop is not None:
        canvas.image.alpha_composite(backdrop)
        canvas.draw = ImageDraw.Draw(canvas.image)
    else:
        for i in range(height):
            t = i / height
            canvas.rect(0, i, width, 1, mix((92, 128, 140), (34, 52, 62), t), 1.0)
        canvas.rect(0, int(height * 0.55), width, int(height * 0.45), (28, 40, 46), 1.0)
    scrim(canvas, 0, min(190, max(120, height * 0.26)), top=True)
    scrim(canvas, height - min(150, max(100, height * 0.2)),
          min(150, max(100, height * 0.2)), top=False)
    draw_hud(canvas, state)
    if state.get("specimens_entries"):
        draw_collection(canvas, state)
        return canvas
    if state.get("modal"):
        # The modal layer sits above everything, including the action bar.
        modal_card(canvas, width, height, width < 780, height < 520, state["modal"])
    return canvas


PLATES = {
    "ui-desktop": ("play", 1280, 720),
    "ui-laptop": ("play", 1024, 640),
    "ui-phone": ("play", 390, 800),
    "ui-phone-landscape": ("play", 844, 354),
    "ui-lobby": ("lobby", 1280, 720),
    "ui-results": ("results", 1280, 720),
    "ui-shop": ("shop", 1280, 720),
    "ui-inventory": ("inventory", 1280, 720),
    "ui-settings": ("settings", 1280, 720),
    "ui-phone-shop": ("shop", 390, 800),
    "ui-collection": ("collection", 1280, 720),
    "ui-collection-full": ("collection-full", 1280, 720),
    "ui-phone-collection": ("collection", 390, 800),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", action="append", choices=sorted(PLATES))
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    chosen = args.only or sorted(PLATES)
    for name in chosen:
        kind, width, height = PLATES[name]
        canvas = mock(kind, width, height)
        path = OUT / f"{name}.jpg"
        canvas.image.convert("RGB").save(path, quality=92)
        print(f"{name}: {width}x{height} -> {path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
