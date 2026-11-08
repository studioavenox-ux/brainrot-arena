"""The Brainrot cast — six original 3D characters, specified as data.

Why this module exists
----------------------
Phase 2 replaced "every cell is a brain" with a cast of six critters, but only as
*client-side scenery*: anonymous primitive clusters scattered over the arena. Phase 3
promotes each critter to a real, named, reusable Roblox **Model** with a face, a
rig of attach points, per-character idle and collect motion, a floating name +
rarity label and a pickup burst — and gives the player a collection record of the
six of them.

This file is the single source of truth:

    tools/creatures.py  ──►  src/client/CreatureData.luau   (runtime part tables)
                        ──►  src/shared/Creatures.luau      (names, rarity, copy)
                        ──►  tools/preview.py               (cast sheet + arena plates)
                        ──►  tools/uidraw.py                (collection card art)
                        ──►  tools/build_place.py           (lobby exhibit models)

The part tables are deliberately primitive-only (`box`, `ball`, `cyl`) so the
models are: cheap on mobile, free of uploaded assets, deterministic to rebuild, and
identical in the place export, at runtime, and in the review plates.

Gameplay contract (server-owned, unchanged by anything here)
------------------------------------------------------------
    rarity      value   cost in cells
    Common      +1      Brain, Frog
    Rare        +5      Fish, Goose
    Legendary   +10     Toast, Sock

Which of the two family members a given cell shows is decided *on the server* at
spawn time (`PickupLedger.rollKind` picks the rarity, then a deterministic
species roll picks the character), so the receipt the client animates is the same
character the player actually collected. Appearance still cannot feed back into
scoring: the server picks from a fixed family of two, both worth the same value.

Part grammar
------------
    Kind   box  | ball | cyl          (Part / Part-Shape / Part-Shape-Cylinder)
    Size   studs, Roblox part size. A cylinder's X is its length (axis = X).
    At     local offset in studs from the model origin. +Z is the face direction,
           +Y is up, origin is the model's primary-part centre.
    Rot    degrees, applied as CFrame.Angles(X, Y, Z) = Rx * Ry * Rz.
    Role   how the runtime colours the part (see ROLES).
    Join   optional animation joint: "head" (follows head sway/turn),
           "jaw" (opens on chant), "armR"/"armL" (swing), "tail" (wag).
"""
from __future__ import annotations

import math

# --------------------------------------------------------------------------- #
# Roles → colour resolution at runtime.
#   body / body_light / body_dark / neon : tints of the character's rarity colour
#   ink / glint                          : fixed dark + white (faces)
#   cream / wood                         : fixed warm neutrals (beaks, cuffs, toes)
#   blush                                : rarity colour warmed toward pink
# --------------------------------------------------------------------------- #
ROLES = ("body", "body_light", "body_dark", "neon", "ink", "glint", "cream", "wood", "blush")

FIXED_COLORS = {
    "ink": (30, 35, 44),
    "glint": (252, 251, 247),
    "cream": (242, 233, 214),
    "wood": (128, 96, 70),
}


def _p(name, kind, size, at, *, rot=(0, 0, 0), role="body", material="SmoothPlastic",
       join=None):
    part = {
        "Name": name, "Kind": kind, "Size": list(size), "At": list(at),
        "Rot": list(rot), "Role": role, "Material": material,
    }
    if join:
        part["Join"] = join
    return part


# --------------------------------------------------------------------------- #
# The cast. Authored around a 1.5-stud collectible so every character reads at
# gameplay camera distance; the same tables also build the lobby exhibit at 1:1.
#
# Silhouette rules (enforced by validate()):
#   • every character is a different overall shape, not a recolour
#   • the face points along +Z and sits in the upper third
#   • nothing but a beak/ear/toe extends more than 0.85 studs from centre
# --------------------------------------------------------------------------- #
CREATURES = {
    # ------------------------------------------------------------------ BRAIN
    "brain": {
        "Name": "Brainy",
        "Label": "BRAINY",
        "Title": "The Overthinker",
        "Rarity": "Common",
        "Value": 1,
        "Blurb": "Two hemispheres, zero impulse control.",
        "Lore": "Has been thinking about the same sandwich since Tuesday.",
        "Parts": [
            # Two hemispheres, lumpy and slightly lopsided.
            _p("LobeL", "ball", (1.04, 1.02, .92), (-.34, .18, 0), rot=(0, 0, 7), role="body"),
            _p("LobeR", "ball", (1.00, .98, .90), (.34, .20, 0), rot=(0, 0, -6), role="body"),
            _p("LobeBack", "ball", (.90, .74, .52), (0, .06, -.40), role="body_dark"),
            # The fold down the middle: dark, thin, unmistakably a brain.
            _p("Seam", "box", (.09, .74, .82), (0, .30, .02), role="body_dark"),
            _p("Stem", "ball", (.28, .30, .28), (0, -.44, -.30), role="body_dark"),
            # Face: a squint and a half-smile. Asymmetric on purpose.
            _p("EyeL", "ball", (.19, .23, .16), (-.28, .26, .42), rot=(0, 0, -12), role="ink"),
            _p("EyeR", "ball", (.19, .23, .16), (.28, .31, .42), rot=(0, 0, 15), role="ink"),
            _p("Brow", "box", (.30, .06, .09), (.28, .44, .41), rot=(0, 0, 16), role="ink"),
            _p("Mouth", "box", (.36, .08, .10), (-.08, .04, .42), rot=(0, 0, -9), role="ink"),
            # Limbs: one wave, one shrug.
            _p("ArmR", "cyl", (.40, .13, .13), (.62, .40, .16), rot=(0, 0, 34), role="body_light",
               join="armR"),
            _p("ArmL", "cyl", (.34, .12, .12), (-.62, -.06, .14), rot=(0, 0, -18), role="body_light",
               join="armL"),
        ],
        # Feet are one shared primitive each: last so they sit under everything.
        "Feet": ("box", (.16, .18, .22), "cream"),
        "Idle": {"Bob": .16, "Sway": .09, "Rate": 1.7, "Spin": .22},
        "Collect": {"Spin": 2.2, "Pop": 1.34},
    },
    # ------------------------------------------------------------------- FROG
    "frog": {
        "Name": "Blorbo",
        "Label": "BLORBO",
        "Title": "The Wide One",
        "Rarity": "Common",
        "Value": 1,
        "Blurb": "Sits on the router for warmth.",
        "Lore": "Ninety percent mouth. The remaining ten percent is also mouth.",
        "Parts": [
            # Enormous head, tiny everything else: the whole silhouette is the joke.
            _p("Head", "ball", (1.32, .92, 1.10), (0, .10, .06), role="body"),
            _p("Jaw", "ball", (.98, .42, .78), (0, -.28, .24), role="body_light", join="jaw"),
            _p("Belly", "ball", (.78, .52, .58), (0, -.34, .30), role="body_dark"),
            _p("Haunch", "ball", (.92, .62, .56), (0, -.14, -.44), role="body_dark"),
            # Eyes on turrets, so they read from above as well as in front.
            _p("EyeTurretL", "ball", (.36, .36, .34), (-.40, .52, .16), role="body_light",
               join="head"),
            _p("EyeTurretR", "ball", (.36, .36, .34), (.40, .52, .16), role="body_light",
               join="head"),
            _p("EyeL", "ball", (.17, .17, .14), (-.40, .56, .32), role="ink", join="head"),
            _p("EyeR", "ball", (.17, .17, .14), (.40, .56, .32), role="ink", join="head"),
            _p("Mouth", "box", (.62, .07, .12), (0, -.14, .58), rot=(0, 0, 3), role="ink"),
            _p("Cheek", "box", (.72, .10, .08), (0, -.02, .54), role="blush", join="head"),
            _p("FoldL", "box", (.18, .26, .30), (-.52, -.44, -.10), rot=(0, 0, 14), role="body"),
            _p("FoldR", "box", (.18, .26, .30), (.52, -.44, -.10), rot=(0, 0, -14), role="body"),
        ],
        "Feet": ("box", (.28, .12, .34), "cream"),
        "Idle": {"Bob": .10, "Sway": .05, "Rate": 2.2, "Spin": .10},
        "Collect": {"Spin": 1.8, "Pop": 1.42},
    },
    # ------------------------------------------------------------------- FISH
    "fish": {
        "Name": "Glorp",
        "Label": "GLORP",
        "Title": "The Legally A Fish",
        "Rarity": "Rare",
        "Value": 5,
        "Blurb": "Cannot swim. Will not discuss it.",
        "Lore": "Holds its breath on land out of politeness.",
        "Parts": [
            _p("Body", "ball", (1.46, .96, .92), (0, 0, 0), role="body"),
            _p("Belly", "ball", (1.00, .52, .80), (0, -.30, 0), role="body_light"),
            # Big goofy lips, the fish's entire personality.
            _p("LipTop", "ball", (.56, .17, .22), (0, .02, .46), role="body_dark", join="jaw"),
            _p("LipBottom", "ball", (.52, .16, .20), (0, -.16, .44), role="body_light", join="jaw"),
            _p("EyeL", "ball", (.28, .28, .22), (-.30, .28, .30), role="ink", join="head"),
            _p("EyeR", "ball", (.28, .28, .22), (.30, .28, .30), role="ink", join="head"),
            _p("GlintL", "ball", (.10, .10, .08), (-.32, .34, .42), role="glint", join="head"),
            _p("GlintR", "ball", (.10, .10, .08), (.28, .34, .42), role="glint", join="head"),
            # Dorsal fin + fan tail: two cues that say "fish" from any angle.
            _p("Dorsal", "box", (.34, .34, .16), (0, .50, -.10), rot=(-16, 0, 0),
               role="body_light", join="head"),
            _p("Tail", "box", (.12, .74, .46), (0, .10, -.52), rot=(-12, 0, 0), role="body_light",
               join="tail"),
            _p("FinL", "box", (.52, .12, .30), (-.66, -.06, .06), rot=(0, 0, 22),
               role="body_light", join="armL"),
            _p("FinR", "box", (.52, .12, .30), (.66, -.06, .06), rot=(0, 0, -22),
               role="body_light", join="armR"),
        ],
        "Feet": None,
        "Idle": {"Bob": .20, "Sway": .12, "Rate": 1.5, "Spin": .40},
        "Collect": {"Spin": 2.8, "Pop": 1.30},
    },
    # ------------------------------------------------------------------ GOOSE
    "goose": {
        "Name": "Hjonk",
        "Label": "HJONK",
        "Title": "The Unbothered",
        "Rarity": "Rare",
        "Value": 5,
        "Blurb": "Has never paid rent. Has never been asked to.",
        "Lore": "Fears nothing except being perceived while walking downhill.",
        "Parts": [
            _p("Body", "ball", (1.10, .78, .82), (0, -.16, -.06), role="body"),
            # S-neck: two offset cylinders so the bend actually reads.
            _p("Neck", "cyl", (.62, .22, .22), (-.02, .30, .04), rot=(0, 0, 74), role="body_light"),
            _p("Head", "ball", (.44, .42, .42), (.16, .62, .08), role="body_light", join="head"),
            # Long flat beak, top and bottom halves that can clack.
            _p("BeakTop", "box", (.42, .09, .18), (.46, .64, .08), rot=(0, 0, -6), role="cream",
               join="head"),
            _p("BeakBottom", "box", (.36, .07, .16), (.44, .54, .08), role="cream", join="jaw"),
            _p("Eye", "ball", (.15, .15, .13), (.24, .70, .22), role="ink", join="head"),
            _p("Brow", "box", (.22, .05, .08), (.24, .80, .18), rot=(0, 0, -14), role="ink",
               join="head"),
            # Wings out, as if it is about to take something from you.
            _p("WingL", "ball", (.62, .30, .20), (-.44, -.02, .10), rot=(0, 0, 22),
               role="body_light", join="armL"),
            _p("WingR", "ball", (.62, .30, .20), (.44, -.02, .10), rot=(0, 0, -22),
               role="body_light", join="armR"),
            _p("Rump", "ball", (.66, .54, .44), (-.34, -.06, -.26), role="body_dark"),
            _p("Tail", "box", (.30, .20, .30), (-.52, .02, -.30), rot=(0, 0, 18), role="body_dark",
               join="tail"),
        ],
        "Feet": ("box", (.20, .12, .34), "cream"),
        "Idle": {"Bob": .12, "Sway": .07, "Rate": 1.3, "Spin": .18},
        "Collect": {"Spin": 2.0, "Pop": 1.38},
    },
    # ------------------------------------------------------------------ TOAST
    "toast": {
        "Name": "Crusty",
        "Label": "CRUSTY",
        "Title": "The Breakfast",
        "Rarity": "Legendary",
        "Value": 10,
        "Blurb": "Breakfast appliance. House cat. Pick one.",
        "Lore": "Fully toasted. Emotionally available. Slightly burnt on one side.",
        "Parts": [
            # Slice of toast: a slab with two shoulder bumps, seen from the front.
            _p("Slice", "box", (.86, 1.00, .26), (0, .04, 0), rot=(0, 0, -3), role="body"),
            _p("ShoulderL", "ball", (.34, .34, .26), (-.28, .50, 0), role="body"),
            _p("ShoulderR", "ball", (.34, .34, .26), (.28, .50, 0), role="body"),
            # Crust rim on the left edge only: reads as "burnt side".
            _p("Crust", "box", (.16, .96, .30), (-.42, .02, 0), rot=(0, 0, -3), role="body_dark"),
            _p("SliceBack", "box", (.88, .94, .24), (.04, .00, -.24), rot=(0, 0, 5),
               role="body_dark"),
            _p("Butter", "box", (.34, .10, .22), (.06, .46, .06), rot=(0, 6, 8), role="cream"),
            _p("EyeL", "ball", (.18, .22, .14), (-.20, .16, .16), rot=(0, 0, 10), role="ink"),
            _p("EyeR", "ball", (.18, .22, .14), (.20, .12, .16), rot=(0, 0, -6), role="ink"),
            _p("Mouth", "box", (.30, .07, .10), (.02, -.16, .16), rot=(0, 0, 6), role="ink"),
            _p("ArmR", "cyl", (.34, .11, .11), (.52, .04, .06), rot=(0, 0, -40), role="body_light",
               join="armR"),
        ],
        "Feet": ("box", (.14, .20, .16), "wood"),
        "Idle": {"Bob": .14, "Sway": .10, "Rate": 1.9, "Spin": .30},
        "Collect": {"Spin": 2.4, "Pop": 1.32},
    },
    # ------------------------------------------------------------------- SOCK
    "sock": {
        "Name": "Whiffers",
        "Label": "WHIFFERS",
        "Title": "The Sentient Sock",
        "Rarity": "Legendary",
        "Value": 10,
        "Blurb": "Escaped the laundry basket. It remembers everything.",
        "Lore": "Knows what you did with the other one.",
        "Parts": [
            # L-shape: a leg tube and a foot, the foot pointing at the player.
            _p("Leg", "box", (.52, .92, .50), (-.10, .30, -.16), rot=(-6, 0, 4), role="body"),
            _p("Foot", "box", (.56, .40, .86), (-.10, -.26, .16), rot=(0, 0, 4), role="body"),
            _p("Toe", "ball", (.60, .44, .40), (-.10, -.24, .52), role="body_light"),
            _p("Heel", "ball", (.46, .34, .30), (-.10, -.38, -.22), role="body_dark"),
            # Cuff and stripes: the cues that say "sock" and not "boot".
            _p("Cuff", "box", (.70, .26, .64), (-.10, .74, -.18), rot=(-6, 0, 4), role="cream"),
            _p("Stripe", "box", (.56, .10, .52), (-.10, .46, -.16), rot=(-6, 0, 4), role="cream"),
            _p("EyeL", "ball", (.16, .18, .12), (-.24, -.06, .56), rot=(0, 0, 12), role="ink"),
            _p("EyeR", "ball", (.16, .18, .12), (.06, -.02, .56), rot=(0, 0, -8), role="ink"),
            _p("Mouth", "box", (.22, .06, .09), (-.08, -.26, .62), rot=(0, 0, -5), role="ink"),
            _p("ArmL", "cyl", (.30, .10, .10), (-.44, .18, .04), rot=(0, 0, 52), role="body_light",
               join="armL"),
        ],
        "Feet": None,
        "Idle": {"Bob": .18, "Sway": .14, "Rate": 2.0, "Spin": .34},
        "Collect": {"Spin": 3.0, "Pop": 1.28},
    },
}

# --------------------------------------------------------------------------- #
# Rarity → the two characters that share it. Order is the collection order shown
# in the UI, so it also defines "slot 1..6" of the collection card grid.
# --------------------------------------------------------------------------- #
FAMILY = {
    1: ("brain", "frog"),        # Common    +1
    5: ("fish", "goose"),        # Rare      +5
    10: ("toast", "sock"),       # Legendary +10
}

RARITY = {
    1: {"Key": "Common", "Label": "COMMON", "Color": "Pink"},
    5: {"Key": "Rare", "Label": "RARE", "Color": "Gold"},
    10: {"Key": "Legendary", "Label": "LEGENDARY", "Color": "Prism"},
}

# Extra silhouette mark per rarity (built by src/client/Iconography.luau).
MARK = {1: "none", 5: "crown", 10: "arms"}

# Shared hover ring: one part per cell, guarantees separation from pale floors.
HOVER_RING = {
    "Name": "Halo",
    "Size": [.09, 1.62, 1.62],   # X is the cylinder axis: thin disc, laid flat
    "Kind": "cyl",
    "Rotation": [0, 0, 90],
    "Role": "glint",
    "Material": "SmoothPlastic",
}

# Per cell model, including the pivot, the hover ring and the rarity mark.
PART_BUDGET = 16

# What a client actually builds per *visible* cell: the part table ceiling, the
# invisible pivot the model is moved by, the shared hover ring and the two arms of
# the legendary mark. Characters are only instantiated inside the camera range, so
# this — not the 48-cell total — is the mobile budget.
VISIBLE_CELL_PARTS = PART_BUDGET + 1 + 1 + 2

# Robot rig parts the collection-card viewport needs (a small stage, not a stage set).
EXHIBIT = {"Plinth": (1.5, .18, 1.5), "Ring": (1.34, .05, 1.34)}


# --------------------------------------------------------------------------- #
# Derived data
# --------------------------------------------------------------------------- #
def parts_of(name):
    """Every part of a character, including its feet (feet are added last so the
    shared primitive can be one box or two, per character)."""
    spec = CREATURES[name]
    parts = list(spec["Parts"])
    feet = spec.get("Feet")
    if feet:
        kind, size, role = feet
        # Distinct part names: a Model with two parts called the same thing is legal
        # in the engine but indistinguishable to a human, to Studio's explorer and to
        # the exhibit test that proves the bake matches this table.
        for side, suffix in ((-1, "L"), (1, "R")):
            parts.append(_p("Foot" + suffix, kind, size, (side * .24, -.60, .10), role=role))
    return parts


def part_count(name):
    return len(parts_of(name))


def top_of(name):
    return max(p["At"][1] + p["Size"][1] / 2 for p in parts_of(name))


def bottom_of(name):
    return min(p["At"][1] - p["Size"][1] / 2 for p in parts_of(name))


def widest(name):
    return max(p["At"][0] + p["Size"][0] / 2 for p in parts_of(name)) - min(
        p["At"][0] - p["Size"][0] / 2 for p in parts_of(name))


def label_height(name):
    """Where the floating name/rarity card hangs, in model space."""
    return top_of(name) + .62


def silhouette(name):
    """Coarse shape signature: used to prove the six are not recolours."""
    parts = parts_of(name)
    return tuple(round(v, 2) for v in (len(parts), widest(name), top_of(name) - bottom_of(name),
                                       max(p["Size"][2] for p in parts)))


def creature_for(slot_id: int, value: int) -> str:
    """Deterministic species choice. The server uses the same function, so the
    receipt a client animates names the character the player actually collected."""
    family = FAMILY[int(value)]
    return family[int(slot_id) % len(family)]


def species_index(name: str) -> int:
    """1..6 position in the collection, ordered Common → Rare → Legendary."""
    order = [n for value in (1, 5, 10) for n in FAMILY[value]]
    return order.index(name) + 1


def total_cell_parts(value: int) -> int:
    """Worst case: pivot + hover ring + rarity marks + the biggest family member."""
    marks = {"none": 0, "crown": 1, "arms": 2}[MARK[int(value)]]
    biggest = max(part_count(name) for name in FAMILY[int(value)])
    return 1 + biggest + 1 + marks


def mount_parts(name, origin, yaw=0.0):
    """World-space part list for one character standing at `origin`.

    Shared by the arena preview plates, the lobby exhibit render and the build
    report so a plate can never show a different creature from the game.
    """
    cos, sin = math.cos(yaw), math.sin(yaw)
    out = []
    for part in parts_of(name):
        ax, ay, az = part["At"]
        rx, ry, rz = part["Rot"]
        out.append({
            "Name": f"{name}_{part['Name']}",
            "Kind": part["Kind"],
            "Size": list(part["Size"]),
            "Position": [origin[0] + ax * cos - az * sin, origin[1] + ay,
                         origin[2] + ax * sin + az * cos],
            "Rotation": [rx, ry + math.degrees(yaw), rz],
            "Role": part["Role"],
            "Material": part["Material"],
        })
    return out


def validate():
    """Fail the build on a malformed, over-budget or samey character."""
    problems = []
    for name, spec in CREATURES.items():
        parts = parts_of(name)
        if not 9 <= len(parts) <= 14:
            problems.append(f"{name}: {len(parts)} parts (want 9-14)")
        for part in parts:
            if part["Role"] not in ROLES:
                problems.append(f"{name}.{part['Name']}: unknown role {part['Role']}")
            if part["Kind"] not in ("box", "ball", "cyl"):
                problems.append(f"{name}.{part['Name']}: unknown kind {part['Kind']}")
            if part["Material"] not in ("SmoothPlastic", "Neon", "Plastic"):
                problems.append(f"{name}.{part['Name']}: material {part['Material']}")
            if any(v <= 0 for v in part["Size"]):
                problems.append(f"{name}.{part['Name']}: non-positive size")
            if part["Size"][0] > 1.5:
                problems.append(f"{name}.{part['Name']}: wider than a cell")
            if "Join" in part and part["Join"] not in ("head", "jaw", "armL", "armR", "tail"):
                problems.append(f"{name}.{part['Name']}: unknown joint {part['Join']}")
        # A face must exist: two eyes, and something to be expressive with.
        eyes = [p for p in parts if p["Role"] == "ink" and p["Size"][1] < .3]
        if len(eyes) < 2:
            problems.append(f"{name}: needs two eyes")
        # The character must be readable from behind too: something must face -Z.
        if min(p["At"][2] - p["Size"][2] / 2 for p in parts) > -.30:
            problems.append(f"{name}: no rear mass, silhouette is a flat card")
        if spec["Value"] not in (1, 5, 10):
            problems.append(f"{name}: invalid reward {spec['Value']}")
        if spec["Rarity"] != RARITY[spec["Value"]]["Key"]:
            problems.append(f"{name}: rarity does not match reward")
        for key in ("Name", "Label", "Title", "Blurb", "Lore"):
            if not spec[key].strip():
                problems.append(f"{name}: empty {key}")
    # Every reward must have exactly two characters, both blessed by the table.
    for value, names in FAMILY.items():
        if len(names) != 2:
            problems.append(f"rarity {value}: needs exactly two characters")
        for name in names:
            if name not in CREATURES:
                problems.append(f"rarity {value} references unknown character {name}")
            elif CREATURES[name]["Value"] != value:
                problems.append(f"{name}: reward does not match its family")
        if total_cell_parts(value) > PART_BUDGET:
            problems.append(f"rarity {value} exceeds the {PART_BUDGET}-part cell budget")
    # Distinct silhouettes: no two characters may share a shape signature.
    seen = {}
    for name in CREATURES:
        signature = silhouette(name)
        if signature in seen:
            problems.append(f"{name} and {seen[signature]} share a silhouette")
        seen[signature] = name
    # The six must be ordered Common → Rare → Legendary in the collection.
    if [species_index(n) for n in CREATURES] != sorted(species_index(n) for n in CREATURES):
        problems.append("species index order is broken")
    return problems


if __name__ == "__main__":
    issues = validate()
    for issue in issues:
        print("PROBLEM:", issue)
    print(f"{len(CREATURES)} characters; "
          f"cell budget: " + ", ".join(f"{v}->{total_cell_parts(v)}" for v in (1, 5, 10)))
    for name in CREATURES:
        print(f"  {species_index(name)}. {CREATURES[name]['Label']:<10} {CREATURES[name]['Rarity']:<10} "
              f"+{CREATURES[name]['Value']:<3} {part_count(name)} parts  "
              f"h={top_of(name) - bottom_of(name):.2f} w={widest(name):.2f}")
    raise SystemExit(1 if issues else 0)
