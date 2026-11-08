"""BRAINROT ARENA — visual art direction, single source of truth.

Premium stylized low-poly tropical environment:
  * natural teal / stone / sand ground surfaces instead of neon cyan,
  * tropical greens instead of lime,
  * purple removed from environment geometry,
  * soft blue sky with warm afternoon sun and atmospheric haze,
  * pink / gold / prism reserved for living Brain Cells, the beacon and UI,
  * material variety (sand, grass, rock, limestone, wood, pebble) for readability.

Everything here is declarative data: the world builder, the place exporter and the
verification suite all read these tables, so a palette or lighting change can never
silently drift between the .rbxlx export and the runtime builder.

NOTE: this module only describes appearance. Gameplay timings, scoring, spawn
locations and pickup positions live in Config.luau / world.py and are untouched.
"""
from __future__ import annotations

import colorsys

# ---------------------------------------------------------------------------
# Palette. Every value is 0-255 sRGB.
# ---------------------------------------------------------------------------
PALETTE = {
    # --- ground: sand, teal stone, pale limestone -------------------------
    "sand": (226, 204, 168),
    "sand_light": (231, 214, 183),
    "sand_shade": (203, 177, 139),
    "sand_wet": (183, 160, 129),
    "teal_stone": (104, 146, 140),
    "teal_deep": (78, 118, 118),
    "teal_shadow": (60, 96, 100),
    # Sea: cooler than the stone teal so the horizon reads as water, still low chroma.
    "sea_deep": (52, 92, 108),
    "sea_tint": (74, 122, 133),
    "sea_shallow": (104, 152, 152),
    "limestone": (223, 216, 197),
    "stone_path": (208, 197, 174),
    "court_stone": (207, 191, 164),
    "stone_trim": (236, 230, 213),
    # --- rock / island mass ------------------------------------------------
    "rock": (128, 132, 130),
    "rock_light": (156, 157, 150),
    "rock_dark": (104, 110, 112),
    "slate": (96, 112, 120),
    "basalt": (74, 84, 92),
    "moss": (118, 140, 104),
    "rock_shade": (92, 100, 104),
    # --- vegetation --------------------------------------------------------
    "leaf": (88, 142, 76),
    "leaf_light": (124, 172, 90),
    "leaf_dark": (62, 108, 64),
    "leaf_sun": (150, 186, 92),
    "frond": (104, 158, 82),
    "trunk": (126, 94, 70),
    "trunk_dark": (98, 74, 58),
    "leaf_deep": (46, 88, 56),
    "moss_dark": (86, 108, 82),
    # --- built props -------------------------------------------------------
    "wood": (150, 116, 86),
    "wood_light": (180, 146, 110),
    "wood_dark": (112, 84, 64),
    "wood_mid": (138, 104, 78),
    "clay": (168, 118, 92),
    "stone_cool": (186, 190, 184),
    "canvas": (214, 199, 170),   # sun-bleached awning canvas
    "ink": (38, 44, 54),
    "panel": (50, 58, 70),
    "white": (245, 246, 242),
    # --- gameplay / special accents (the ONLY saturated hues in the scene) --
    "cell_pink": (255, 104, 190),
    "cell_gold": (255, 206, 74),
    "cell_prism": (122, 230, 255),
    "signal_pink": (255, 126, 198),
    "signal_gold": (255, 208, 108),
    "signal_prism": (150, 228, 255),
    "beacon_pink": (255, 132, 214),
    "beacon_gold": (255, 214, 116),
    "rift_violet": (152, 126, 216),
    # --- light -------------------------------------------------------------
    "lantern": (255, 200, 138),
    "sign_cream": (247, 240, 226),
    "sign_gold": (255, 206, 120),
    "sign_pink": (255, 150, 202),
    "sign_prism": (150, 226, 245),
}

# Hues that may ONLY be used by living Brain Cells, the beacon accents, the
# Pulse Halo and UI labels — never by environment geometry.
ACCENT_NAMES = frozenset({
    "cell_pink", "cell_gold", "cell_prism",
    "signal_pink", "signal_gold", "signal_prism",
    "beacon_pink", "beacon_gold", "rift_violet",
})

# The supersaturated palette this redesign replaces. Environment geometry must
# not contain these values again; the verification suite asserts their absence.
LEGACY_NEON = {
    "cyan": (66, 228, 247),
    "lime": (158, 239, 91),
    "violet": (155, 95, 255),
    "mint": (151, 247, 183),
    "grass_green": (99, 218, 154),
    "violet_rock": (67, 47, 119),
    "violet_rock_light": (105, 71, 169),
    "bright_blue": (65, 139, 228),
    "electric_gold": (255, 221, 99),
}

# Names kept for backwards compatibility with older world specs.
LEGACY_ALIASES = {
    "rock": "rock",
    "rock_light": "rock_light",
    "grass": "sand",
    "mint": "stone_trim",
    "path": "stone_path",
    "cyan": "cell_prism",
    "purple": "teal_stone",
    "pink": "signal_pink",
    "white": "sign_cream",
    "gold": "signal_gold",
    "trunk": "trunk",
    "leaf": "leaf",
    "leaf_light": "leaf_light",
    "blue": "slate",
    "ink": "ink",
}

# ---------------------------------------------------------------------------
# Materials. token -> (Roblox material, cast shadows)
# Standard primitives only; no textures, meshes, unions or terrain.
# ---------------------------------------------------------------------------
MATERIALS = {
    "smooth": ("SmoothPlastic", True),   # painted props, foliage
    "matte": ("Plastic", True),          # small hard props
    "ground": ("Ground", True),          # packed earth / island cap
    "grass": ("Grass", True),            # lawn patches
    "leafy": ("LeafyGrass", True),       # lush patches
    "sand": ("Sand", True),              # beach floor, plaza dust
    "sandstone": ("Sandstone", True),    # cut stone blocks
    "limestone": ("Limestone", True),    # pale built stone
    "concrete": ("Concrete", True),      # structural slabs
    "marble": ("Marble", True),          # polished medallion
    "rock": ("Rock", True),              # island mass, boulders
    "slate": ("Slate", True),            # flat ledges, shallow water
    "basalt": ("Basalt", True),          # dark rock detail
    "pebble": ("Pebble", True),          # shoreline stones
    "wood": ("Wood", True),              # driftwood, posts
    "planks": ("WoodPlanks", True),      # decks, bridges
    "canvas": ("Fabric", True),          # umbrellas, awnings
    "neon": ("Neon", False),             # gameplay glow only
}

NATURAL_MATERIALS = frozenset({
    "ground", "grass", "leafy", "sand", "sandstone", "limestone", "rock",
    "slate", "basalt", "pebble", "wood", "planks",
})

# ---------------------------------------------------------------------------
# Lighting: soft blue sky, warm late-afternoon sun, gentle haze.
# Values are plain Roblox property values (see tools/build_place.py).
# ---------------------------------------------------------------------------
LIGHTING = {
    "Brightness": 2.2,
    "ClockTime": 16.15,
    "GeographicLatitude": 12.0,        # gentle tropical sun angle
    "GlobalShadows": True,
    "ShadowSoftness": 0.38,
    "ExposureCompensation": 0.09,
    "Ambient": (96, 108, 122),         # cool sky-bounce fill, never black
    "OutdoorAmbient": (150, 164, 176),
    "ColorShift_Top": (255, 233, 204),  # warm sun tint
    "ColorShift_Bottom": (122, 140, 152),
    "EnvironmentDiffuseScale": 0.55,
    "EnvironmentSpecularScale": 0.3,
    "FogColor": (198, 216, 228),
    "FogStart": 260,
    "FogEnd": 1150,
}

# Children of Lighting. Each entry is (class name, properties).
LIGHTING_EFFECTS = (
    ("Sky", {
        "CelestialBodiesShown": True,
        "SunAngularSize": 22,
        "StarCount": 0,
        "MoonAngularSize": 11,
    }),
    ("Atmosphere", {
        "Density": 0.32,
        "Offset": 0.1,
        "Color": (214, 232, 244),
        "Decay": (146, 166, 190),
        "Haze": 1.6,
        "Glare": 0.08,
    }),
    ("BloomEffect", {          # only genuinely bright gameplay glow blooms
        "Intensity": 0.22,
        "Size": 20,
        "Threshold": 1.45,
    }),
    ("ColorCorrectionEffect", {  # neutral grade; replaces the old "CandyColor"
        "Saturation": 0.06,
        "Contrast": 0.05,
        "Brightness": 0.01,
        "TintColor": (255, 252, 248),
    }),
)

# Camera used by the saved place's edit-time framing (a lobby establishing shot).
CAMERA_EYE = (118, 96, 214)
CAMERA_FOCUS = (0, 26, 172)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def rgb(name):
    """Resolve a palette name (or a raw 3-sequence) to an RGB triple."""
    if isinstance(name, (tuple, list)):
        return list(name)
    if name in PALETTE:
        return list(PALETTE[name])
    raise KeyError(f"Unknown palette colour: {name}")


def shade(color, amount):
    """Lighten (amount > 0) or darken (< 0) a palette name or RGB triple."""
    base = rgb(color)
    if amount >= 0:
        target = (255, 255, 255)
    else:
        target = (18, 22, 26)
        amount = -amount
    return [round(c + (t - c) * amount) for c, t in zip(base, target)]


def hex_color(values):
    return "#%02x%02x%02x" % tuple(values)


def hsl(values):
    r, g, b = (c / 255 for c in values)
    return colorsys.rgb_to_hls(r, g, b)  # returns (h, l, s)


def saturation(values):
    return hsl(values)[2]


def luminance(values):
    """sRGB relative luminance, 0-1."""
    def channel(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (channel(c) for c in values)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast_ratio(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def material(token):
    return MATERIALS[token][0]


def casts_shadow(token):
    return MATERIALS[token][1]


# ---------------------------------------------------------------------------
# Runtime-facing values (mirrored into src/shared/ArtDirection.luau by the build
# so Rojo users and the baked place get the identical look).
# ---------------------------------------------------------------------------
EFFECT_NAMES = {
    "Sky": "TropicalDaySky",
    "Atmosphere": "CoastalHaze",
    "BloomEffect": "GameplayBloom",
    "ColorCorrectionEffect": "NeutralGrade",
}

SKYBOX = {face: f"rbxasset://textures/sky/sky512_{suffix}.tex" for face, suffix in (
    ("Bk", "bk"), ("Dn", "dn"), ("Ft", "ft"), ("Lf", "lf"), ("Rt", "rt"), ("Up", "up"))}

# Low-gravity event: a bright prismatic pulse. Gameplay feedback, so saturated.
EVENT_ACCENT = (168, 240, 255)
EVENT_REST = {
    "ChaosAccent_BeaconRing": "beacon_gold",
    "ChaosAccent_BeaconTop": "beacon_pink",
    "ChaosAccent_QueueLeft": "lantern",
    "ChaosAccent_QueueRight": "lantern",
}
EVENT_LIGHT = (255, 150, 224)

# Point lights are expensive relative to geometry: exactly seven, all shadowless,
# all attached to meaningful landmarks (the beacon, the gate, satellite masts).
LIGHTS = {
    "ChaosAccent_BeaconTop": {
        "Name": "BeaconGlow", "Color": "beacon_pink", "Brightness": 2.2,
        "Range": 36, "Shadows": False,
    },
    "Portal_Lantern_-1": {
        "Name": "GateWarmth", "Color": "lantern", "Brightness": 1.1,
        "Range": 18, "Shadows": False,
    },
    "Portal_Lantern_1": {
        "Name": "GateWarmth", "Color": "lantern", "Brightness": 1.1,
        "Range": 18, "Shadows": False,
    },
    **{
        f"Satellite_{index}_Lantern": {
            "Name": "MastWarmth", "Color": "lantern", "Brightness": 0.9,
            "Range": 22, "Shadows": False,
        }
        for index in range(4)
    },
}
SIGN_FONT = "GothamBold"
SIGN_DISPLAY_FONT = "GothamBlack"

# In-world sign palette (surface GUI text).
SIGN_TEXT = {
    "body": "sign_cream",
    "heading": "sign_gold",
    "rarity": "sign_prism",
    "win": "sign_pink",
}

# HUD / UI palette.
UI = {
    "Ink": (24, 32, 36),
    "Panel": (34, 44, 50),
    "Line": (92, 110, 116),
    "Muted": (176, 190, 190),
    "White": (243, 247, 245),
    "Pink": (255, 108, 186),
    "Prism": (126, 226, 250),
    "Gold": (255, 205, 96),
    "Sea": (98, 176, 168),
    "Highlight": (46, 74, 74),
}
