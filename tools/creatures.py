"""Original collectible creatures — the "brainrot" cast.

Why this module exists
----------------------
Every collectible was a literal brain in Phase 1. Phase 2 gives the arena a cast of
original, silly low-poly critters while keeping the *gameplay* contract untouched:

  rarity (server-owned)      pink +1        gold +5         prism +10
  creature family            small critter  sea/land bird   weird relic
  body colour (server-owned) pink           gold            prism
  extra silhouette mark      none           crown spike     crossed arms

Colour and shape therefore agree with each other and the rarity is still readable
from three redundant cues (hue, family, mark). Which variant a slot shows is decided
deterministically from the slot id, purely on the client: the server never learns
what a cell looks like, so scoring / claiming / respawn logic cannot be affected.

The specification is plain data. `tools/build_place.py` generates
`src/client/CreatureData.luau` from it, `src/client/Creatures.luau` instantiates the
primitives, and `tools/preview.py` renders the very same tables, so the visual cannot
drift between the exports, the runtime and the review plates.

Budget: every creature is 6-8 primitives plus the shared 1-part hover ring, and the
hover ring is the only part kept for every cell.
"""
from __future__ import annotations

import math

# Roles -> how `src/client/Creatures.luau` colours a primitive at runtime.
#   body / body_light / body_dark : tints of the CELL's rarity colour
#   eye / glint                   : fixed neutral (faces read as faces, not rarity)
#   accent_wood / accent_cream    : fixed warm neutrals (beaks, fins, toes, stripes)
#   neon                          : rarity colour, Neon material (rare highlights)
ROLES = ("body", "body_light", "body_dark", "eye", "glint", "accent_wood", "accent_cream", "neon")

# Neutral inks shared with the HUD so faces never introduce a new saturated hue.
FIXED_COLORS = {
    "eye": (32, 37, 43),
    "glint": (250, 250, 248),
    "accent_wood": (122, 92, 68),
    "accent_cream": (238, 230, 212),
}


def _p(name, size, offset, *, shape="Block", role="body", rotation=(0, 0, 0),
       material="SmoothPlastic"):
    return {"Name": name, "Size": list(size), "Offset": list(offset),
            "Shape": shape, "Rotation": list(rotation), "Role": role,
            "Material": material}


# ---------------------------------------------------------------------------
# The cast. All dimensions are studs, authored around a 1.5-stud cell.
# ---------------------------------------------------------------------------
CREATURES = {
    # A. The original Brain Cell. Recognisable, and still the mascot.
    "brain": {
        "Label": "BRAIN CELL",
        "Blurb": "Overworked. Underpaid. Extremely collectable.",
        "Parts": [
            _p("Lobe", (1.02, 1.14, 0.94), (-0.38, 0.06, -0.46), shape="Ball"),
            _p("Lobe", (1.02, 1.14, 0.94), (-0.38, 0.06, 0.46), shape="Ball"),
            _p("Lobe", (1.02, 1.14, 0.94), (-0.38, 0.24, 0.00), shape="Ball"),
            _p("Lobe", (1.02, 1.14, 0.94), (0.38, 0.06, -0.46), shape="Ball"),
            _p("Lobe", (1.02, 1.14, 0.94), (0.38, 0.06, 0.46), shape="Ball"),
            _p("Lobe", (1.02, 1.14, 0.94), (0.38, 0.24, 0.00), shape="Ball"),
            _p("Seam", (0.10, 1.06, 1.42), (0.00, 0.10, 0.00), role="body_dark", material="Neon"),
            _p("Stem", (0.52, 0.42, 0.52), (0.00, -0.62, 0.00), shape="Ball", role="body_dark"),
        ],
    },
    # B. Frog with opinions. Flat, wide, two eye domes: readable at any distance.
    "frog": {
        "Label": "BRICK FROG",
        "Blurb": "Sits on the router for warmth.",
        "Parts": [
            _p("Body", (1.62, 0.94, 1.42), (0.00, -0.14, 0.00), shape="Ball"),
            _p("Back", (1.16, 0.62, 1.00), (0.00, 0.20, 0.16), shape="Ball", role="body_light"),
            _p("EyeDome", (0.54, 0.52, 0.52), (-0.46, 0.40, -0.52), shape="Ball", role="body_light"),
            _p("EyeDome", (0.54, 0.52, 0.52), (0.46, 0.40, -0.52), shape="Ball", role="body_light"),
            _p("Pupil", (0.22, 0.22, 0.13), (-0.46, 0.42, -0.76), shape="Ball", role="eye"),
            _p("Pupil", (0.22, 0.22, 0.13), (0.46, 0.42, -0.76), shape="Ball", role="eye"),
            _p("Mouth", (0.70, 0.09, 0.12), (0.00, -0.04, -0.70), role="body_dark"),
            _p("Toe", (0.34, 0.18, 0.54), (-0.56, -0.54, -0.28), role="accent_cream"),
            _p("Toe", (0.34, 0.18, 0.54), (0.56, -0.54, -0.28), role="accent_cream"),
        ],
    },
    # C. Wobble fish. Round body, fan tail, permanently surprised.
    "fish": {
        "Label": "WOBBLE FISH",
        "Blurb": "Legally a fish. Cannot swim. Will not discuss it.",
        "Parts": [
            _p("Body", (1.38, 1.18, 1.02), (-0.12, 0.00, 0.00), shape="Ball"),
            _p("Belly", (0.92, 0.62, 0.86), (-0.10, -0.34, 0.00), shape="Ball", role="body_light"),
            _p("Tail", (0.40, 0.98, 0.14), (-0.92, 0.02, 0.00), shape="Ball", role="body_light"),
            _p("Dorsal", (0.56, 0.44, 0.14), (-0.10, 0.66, 0.00), shape="Ball", role="body_light"),
            _p("Fin", (0.26, 0.14, 0.54), (0.20, -0.22, -0.52), role="accent_cream"),
            _p("Fin", (0.26, 0.14, 0.54), (0.20, -0.22, 0.52), role="accent_cream"),
            _p("Eye", (0.26, 0.26, 0.15), (0.30, 0.30, -0.54), shape="Ball", role="eye"),
            _p("Eye", (0.26, 0.26, 0.15), (0.30, 0.30, 0.54), shape="Ball", role="eye"),
            _p("Snout", (0.34, 0.30, 0.30), (0.62, -0.06, 0.00), shape="Ball", role="body_dark"),
        ],
    },
    # D. Silly goose. Long neck, forward beak: unmistakable in silhouette.
    "goose": {
        "Label": "SILLY GOOSE",
        "Blurb": "Has never paid rent. Has never been asked to.",
        "Parts": [
            _p("Body", (1.34, 0.96, 1.06), (-0.20, -0.22, 0.00), shape="Ball"),
            _p("Neck", (0.34, 0.96, 0.34), (0.14, 0.26, 0.00), role="body"),
            _p("Head", (0.64, 0.60, 0.60), (0.28, 0.72, 0.00), shape="Ball", role="body_light"),
            _p("Beak", (0.42, 0.18, 0.24), (0.62, 0.66, 0.00), role="accent_cream"),
            _p("Eye", (0.17, 0.17, 0.11), (0.32, 0.80, -0.32), shape="Ball", role="eye"),
            _p("Eye", (0.17, 0.17, 0.11), (0.32, 0.80, 0.32), shape="Ball", role="eye"),
            _p("Tail", (0.44, 0.34, 0.20), (-0.86, 0.10, 0.00), shape="Ball", role="body_light"),
            _p("Toe", (0.22, 0.14, 0.44), (-0.10, -0.66, -0.18), role="accent_cream"),
            _p("Toe", (0.22, 0.14, 0.44), (-0.10, -0.66, 0.18), role="accent_cream"),
        ],
    },
    # E. Toaster cat. The rarest thing on the island and it knows it.
    "toast": {
        "Label": "TOASTER CAT",
        "Blurb": "Breakfast appliance. House cat. Pick one.",
        "Parts": [
            _p("Body", (1.40, 1.14, 0.84), (0.00, -0.06, 0.00)),
            _p("Plate", (1.16, 0.60, 0.12), (0.00, 0.02, -0.44), role="body_light"),
            _p("Ear", (0.30, 0.30, 0.20), (-0.42, 0.58, 0.00), rotation=(0, 0, 45), role="body_light"),
            _p("Ear", (0.30, 0.30, 0.20), (0.42, 0.58, 0.00), rotation=(0, 0, 45), role="body_light"),
            _p("Slot", (0.74, 0.10, 0.18), (0.00, 0.50, 0.03), role="body_dark"),
            _p("Eye", (0.22, 0.22, 0.13), (-0.28, 0.16, -0.58), shape="Ball", role="eye"),
            _p("Eye", (0.22, 0.22, 0.13), (0.28, 0.16, -0.58), shape="Ball", role="eye"),
            _p("Toast", (0.62, 0.46, 0.14), (0.00, 0.72, 0.04), role="accent_cream"),
        ],
    },
    # F. The humble sock that achieved sentience. Legendary-tier weirdness.
    "sock": {
        "Label": "SENTIENT SOCK",
        "Blurb": "Escaped the laundry basket. It remembers everything.",
        "Parts": [
            _p("Foot", (0.92, 0.54, 1.36), (0.00, -0.36, 0.04)),
            _p("Leg", (0.74, 1.16, 0.68), (-0.04, 0.28, 0.40), rotation=(-10, 0, 0)),
            _p("Heel", (0.54, 0.38, 0.54), (0.00, -0.52, 0.50), shape="Ball", role="body_dark"),
            _p("Cuff", (0.84, 0.24, 0.76), (-0.04, 0.84, 0.34), role="accent_cream"),
            _p("Stripe", (0.76, 0.13, 0.70), (-0.03, 0.54, 0.38), role="accent_cream"),
            _p("Eye", (0.20, 0.20, 0.13), (-0.23, -0.10, -0.70), shape="Ball", role="eye"),
            _p("Eye", (0.20, 0.20, 0.13), (0.23, -0.10, -0.70), shape="Ball", role="eye"),
        ],
    },
}

# ---------------------------------------------------------------------------
# Rarity -> creature family. Three families, two variants each, so the arena has
# variety without ever muddying "which one is worth more".
# ---------------------------------------------------------------------------
FAMILY = {
    1: ("brain", "frog"),        # pink  +1  small critters
    5: ("fish", "goose"),        # gold  +5  sea / land birds
    10: ("toast", "sock"),       # prism +10 weird relics
}

# Extra silhouette mark per rarity (built by src/client/Iconography.luau).
MARK = {1: "none", 5: "crown", 10: "arms"}

# Shared hover ring: one part per cell, guarantees separation from pale floors.
HOVER_RING = {
    "Name": "Halo",
    "Size": [0.09, 1.62, 1.62],   # X is the cylinder axis: thin disc, laid flat
    "Shape": "Cylinder",
    "Rotation": [0, 0, 90],
    "Role": "glint",
    "Material": "SmoothPlastic",
}

PART_BUDGET = 12  # per cell model, including the pivot and the hover ring


def creature_for(slot_id: int, value: int) -> str:
    """Deterministic, client-side variant choice. Never sent to the server."""
    family = FAMILY[int(value)]
    return family[int(slot_id) % len(family)]


def total_cell_parts(value: int) -> int:
    """Worst case: pivot + creature + hover ring + rarity marks."""
    marks = {"none": 0, "crown": 1, "arms": 2}[MARK[int(value)]]
    biggest = max(len(CREATURES[name]["Parts"]) for name in FAMILY[int(value)])
    return 1 + biggest + 1 + marks


def validate():
    """Fail the build on a malformed or over-budget creature."""
    problems = []
    for name, spec in CREATURES.items():
        parts = spec["Parts"]
        if not 5 <= len(parts) <= 9:
            problems.append(f"{name}: {len(parts)} parts (want 5-9)")
        for part in parts:
            if part["Role"] not in ROLES:
                problems.append(f"{name}.{part['Name']}: unknown role {part['Role']}")
            if part["Shape"] not in ("Block", "Ball", "WedgePart", "Cylinder"):
                problems.append(f"{name}.{part['Name']}: unknown shape {part['Shape']}")
            if part["Material"] not in ("SmoothPlastic", "Neon", "Plastic"):
                problems.append(f"{name}.{part['Name']}: material {part['Material']}")
            if any(v <= 0 for v in part["Size"]):
                problems.append(f"{name}.{part['Name']}: non-positive size")
    for value in (1, 5, 10):
        for name in FAMILY[value]:
            if name not in CREATURES:
                problems.append(f"rarity {value} references unknown creature {name}")
        if total_cell_parts(value) > PART_BUDGET:
            problems.append(f"rarity {value} exceeds the {PART_BUDGET}-part cell budget")
    # Every family variant pair must be visually distinct in silhouette, not just
    # colour: compare part counts and the widest/tallest extents.
    for value, names in FAMILY.items():
        shapes = set()
        for name in names:
            parts = CREATURES[name]["Parts"]
            top = max(p["Offset"][1] + p["Size"][1] / 2 for p in parts)
            bottom = min(p["Offset"][1] - p["Size"][1] / 2 for p in parts)
            wide = max(p["Offset"][2] + p["Size"][2] / 2 for p in parts) - min(
                p["Offset"][2] - p["Size"][2] / 2 for p in parts)
            shapes.add((len(parts), round(top - bottom, 2), round(wide, 2)))
        if len(shapes) != len(names):
            problems.append(f"rarity {value}: variants share a silhouette")
    return problems


if __name__ == "__main__":
    issues = validate()
    for issue in issues:
        print("PROBLEM:", issue)
    print(f"{len(CREATURES)} creatures; "
          f"cell budget: " + ", ".join(
              f"{v}->{total_cell_parts(v)}" for v in (1, 5, 10)))
    raise SystemExit(1 if issues else 0)
