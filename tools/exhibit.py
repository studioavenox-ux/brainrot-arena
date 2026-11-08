"""Inject the six character Models into the place export.

The cast is authored once, in tools/creatures.py, and consumed three ways:
runtime (cells + collection cards), review plates, and this baked exhibit. The
exhibit is what makes the six characters *assets in the place file*: open the
.rbxlx in Studio, expand Workspace → BrainrotCharacters, and there they are — named
Models, each on its own plinth, each carrying its own floating name and rarity card.
"""
from __future__ import annotations

import math

import creatures

# Same rarity colours the server owns (Config.Kinds). Kept as a literal here so the
# export never depends on reading a Luau file at build time.
KIND_COLORS = {1: (255, 94, 190), 5: (255, 213, 67), 10: (83, 238, 255)}

# Where the exhibit stands: a row on the lobby terrace, in front of the spawn pad,
# clear of the palms (x = ±16.5, z = 208.6), the shrubs (z >= 204) and the gate.
# ORIGIN is the *floor* the row stands on — the top face of Lobby_Terrace_Step_0
# (centre 21.3, height .6, spans z 194.9 .. 200.1, x ±17). Depth is set so
# each 1.9-deep plinth sits wholly on that step.
ORIGIN = (0.0, 21.6, 199.0)
SPACING = 3.1
YAW = 180.0     # faces turn toward the spawn pad

# Plinth: a stone block that stands *on* the terrace, so no part of the exhibit is
# buried in the map and the characters' feet sit on its top face.
PLINTH_SIZE = (1.9, .34, 1.9)
# A shade warmer and darker than the terrace stone, so the plinths read as their own
# objects against the floor instead of disappearing into it.
PLINTH_COLOR = (168, 174, 170)
PLINTH_TOP = ORIGIN[1] + PLINTH_SIZE[1]

SHAPE_TOKEN = {"box": 1, "ball": 0, "cyl": 2}


def tint(base, role):
    """Mirror of src/client/Creatures.luau."""
    if role in ("body", "neon"):
        return list(base)
    if role == "body_light":
        return [round(c + (255 - c) * .26) for c in base]
    if role == "body_dark":
        return [round(c + ((34, 40, 50)[i] - c) * .42) for i, c in enumerate(base)]
    if role == "blush":
        return [round(c + ((255, 150, 190)[i] - c) * .55) for i, c in enumerate(base)]
    return list(creatures.FIXED_COLORS.get(role, base))


def layout():
    """(name, x, y, z) for the six characters, ordered Common → Rare → Legendary.

    `y` is each character's model origin: feet exactly on the plinth's top face, so
    nobody floats or sinks even though the six are not all the same height.
    """
    order = [name for value in (1, 5, 10) for name in creatures.FAMILY[value]]
    out = []
    for index, name in enumerate(order):
        x = ORIGIN[0] + (index - (len(order) - 1) / 2) * SPACING
        out.append((name, x, PLINTH_TOP - creatures.bottom_of(name), ORIGIN[2]))
    return out


def plinth_y():
    """Centre height of every plinth (they all share one)."""
    return ORIGIN[1] + PLINTH_SIZE[1] / 2


def parts_for(name, origin):
    """World-space parts for one character, in the plinth's local frame."""
    return creatures.mount_parts(name, origin, math.radians(YAW))


def model_names():
    return [creatures.CREATURES[name]["Label"] for name, *_ in layout()]
