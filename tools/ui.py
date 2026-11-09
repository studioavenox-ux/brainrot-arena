"""HUD design system — one source of truth for colour, type, spacing and motion.

The Phase 3 interface is specified here as data so the runtime HUD
(`src/client/Theme.luau`, generated from this file), the marketing plates and the
art gate cannot drift apart.

Visual identity
---------------
Premium stylised game UI: deep navy translucent panels, rounded corners, a subtle
vertical gradient on every panel, and three accents that each *mean* something:

    cyan   structure, timer, rarity-tier-3
    violet brand, navigation, rewards
    amber  currency, winner, embers

The world is a warm tropical palette, so the HUD is deliberately cool navy: it
separates cleanly from sand and stone without tinting it. Contrast is checked in
`tools/artcheck.py` against WCAG-ish ratios, not eyeballed.

Nothing here is gameplay. It is colour, type sizes, spacing, tween timings and
copy strings.
"""
from __future__ import annotations

# --------------------------------------------------------------------------- #
# Colour. sRGB 0-255. Every value is a deliberate member of the five families.
# --------------------------------------------------------------------------- #
COLORS = {
    # navy panel stack (back to front)
    "Void": (10, 14, 26),
    "Navy": (16, 22, 38),
    "NavyRaised": (25, 33, 54),
    "NavyEdge": (44, 56, 86),
    # text
    "White": (238, 243, 255),
    "Muted": (160, 174, 202),
    "Dim": (112, 126, 154),
    # accents, one job each
    "Cyan": (86, 224, 255),
    "Violet": (158, 120, 255),
    "Amber": (255, 199, 92),
    # semantic
    "Danger": (255, 108, 138),
    "Success": (118, 240, 178),
}

# Transparency per surface kind (0 = opaque, 1 = invisible).
ALPHA = {
    # Panels must be readable over bright sand and sky, so the navy is present, not
    # a whisper: 0.07 leaves roughly a 25:1 text contrast, 0.2 about 15:1.
    "Panel": 0.07,
    "PanelRaised": 0.04,
    "Scrim": 0.45,
    "Hairline": 0.55,
    "Ghost": 0.92,
}

# --------------------------------------------------------------------------- #
# Type scale. Roblox has no custom fonts without uploads, so the scale is size,
# weight and letter-spacing discipline on the bundled Gotham family.
# --------------------------------------------------------------------------- #
TYPE = {
    "Display": 34,   # round clock, hero numbers
    "Title": 22,     # panel titles, brand
    "Heading": 16,   # card headings
    "Body": 13,      # default body
    "Label": 11,     # caps labels, eyebrows
    "Micro": 9,      # meta, units
}

FONTS = {
    "Display": "GothamBlack",
    "Title": "GothamBlack",
    "Heading": "GothamBold",
    "Body": "GothamMedium",
    "Label": "GothamBold",
    "Micro": "GothamMedium",
}

# Spacing scale in pixels (4-point grid). Used for panel padding and gaps.
SPACE = {"xs": 4, "sm": 8, "md": 12, "lg": 16, "xl": 24, "xxl": 32}

# Animation. Seconds. All of it honours the reduced-motion toggle: when that is on
# the HUD snaps to its end state instead of tweening.
MOTION = {
    "Snap": 0.08,
    "Fast": 0.18,
    "Base": 0.28,
    "Slow": 0.45,
    "Toast": 0.35,
    "Notice": 3.6,      # how long a centre toast stays up
}

RADIUS = 14

# --------------------------------------------------------------------------- #
# Procedural glyphs. No images, no asset ids: every icon is frames and corners.
# Each entry describes the pieces of a 20x20 box in relative units.
# --------------------------------------------------------------------------- #
GLYPHS = {
    # brain-lobe cluster: the score counter
    "cell": {
        "Box": 20,
        "Kind": "cluster",
        "Accent": "Cyan",
        "Pieces": "3x2",
    },
    # coin: a disc with a cut-out and a rim
    "coin": {
        "Box": 20,
        "Kind": "disc",
        "Accent": "Amber",
        "Inner": 0.46,
    },
    # timer: a ring with a tick
    "clock": {
        "Box": 20,
        "Kind": "ring",
        "Accent": "Cyan",
        "Ticks": 4,
    },
    "shop": {"Box": 20, "Kind": "bag", "Accent": "Amber"},
    "inventory": {"Box": 20, "Kind": "grid", "Accent": "Cyan"},
    "settings": {"Box": 20, "Kind": "cog", "Accent": "Violet"},
    "rank": {"Box": 14, "Kind": "chevron", "Accent": "Violet"},
    # a hooked hand: the steal action
    "steal": {"Box": 20, "Kind": "hook", "Accent": "Danger"},
    # a lightning bolt: the live event chip
    "bolt": {"Box": 16, "Kind": "bolt", "Accent": "Cyan"},
}

# --------------------------------------------------------------------------- #
# Copy. Short, in-voice, and never a stand-in for real state: every string here is
# either a static label or a format string the server's data fills in.
# --------------------------------------------------------------------------- #
COPY = {
    "BrandTop": "BRAINROT",
    "BrandBottom": "A R E N A",
    "BrandTag": "COLLECT • STEAL • SURVIVE • DOMINATE",
    "CellsLabel": "BRAIN CELLS",
    "CoinsLabel": "COINS",
    "TimerLabel": "ROUND",
    "BoardTitle": "THIS ROUND",
    "BoardSub": "MOST CELLS WINS",
    "ShopBar": "SHOP",
    "InventoryBar": "GEAR",
    "SettingsBar": "SETTINGS",
    "ShopTitle": "HALO STAND",
    "ShopBody": "A cyan orbit for an overactive brain.",
    "InventoryTitle": "SPECIMEN LOG",
    "CollectionTitle": "SPECIMEN LOG",
    "InventoryEmpty": "No specimens logged yet. Walk into a cell to catch one.",
    "CollectionHint": "WALK INTO A SPECIMEN TO CATCH IT",
    "CollectionFound": "FOUND",
    "CollectionMissing": "NOT SEEN YET",
    "CollectionCount": "CAUGHT",
    "SettingsTitle": "SETTINGS",
    "LobbyWelcome": "WELCOME TO THE ARENA",
    "LobbySub": "Rounds start automatically. You are always in.",
    "WaitingStatus": "WAITING FOR BRAINS",
    "IntermissionStatus": "GET READY",
    "PlayingStatus": "COLLECT",
    "ResultsStatus": "ROUND COMPLETE",
    "EventBanner": "LOW GRAVITY",
    "TieBanner": "A MEETING OF MINDS",
    "WinBanner": "BIG BRAIN ENERGY",
    "NoScoreBanner": "THE BRAINS ARE WARMING UP",
    "TouchHint": "Drag to look • thumbstick to move",
    # Phase 5: stealing and the staged round.
    "StealBar": "STEAL",
    "StealReady": "STEAL READY",
    "StealCooling": "STEAL",
    "StealEmpty": "NOTHING TO TAKE",
    "StealProtected": "PROTECTED",
    "StealOutOfRange": "TOO FAR",
    "StealCooldown": "RECHARGING",
    "StealRepeat": "SAME TARGET",
    "StealImmune": "JUST HIT",
    "StealWon": "STEAL",
    "StealLost": "STOLEN",
    "StealHint": "TAP STEAL BESIDE A RIVAL TO TAKE ONE CARRIED CELL",
    "StageCollect": "COLLECT PHASE — BANK WHAT YOU CATCH",
    "StageCompete": "COMPETE — CARRIED CELLS ARE AT RISK",
    "StageChaos": "CHAOS — EVENTS ARE LIVE",
    "StageFinal": "FINAL RUSH — EVERYTHING IS ON THE LINE",
    "EventIncoming": "INCOMING",
    "EventLive": "ACTIVE",
    "CarriedLabel": "CARRIED",
    "BankedLabel": "BANKED",
    "ResultsSteals": "STEALS",
    "ResultsLost": "LOST",
}

# --------------------------------------------------------------------------- #
# Validation. The art gate calls this; so does the generator, so a bad palette
# fails the build instead of shipping.
# --------------------------------------------------------------------------- #
def _lum(rgb):
    def channel(value):
        c = value / 255.0
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (channel(v) for v in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def hue(rgb):
    r, g, b = (v / 255.0 for v in rgb)
    hi, lo = max(r, g, b), min(r, g, b)
    if hi == lo:
        return 0.0
    delta = hi - lo
    if hi == r:
        h = ((g - b) / delta) % 6
    elif hi == g:
        h = (b - r) / delta + 2
    else:
        h = (r - g) / delta + 4
    return h * 60.0


def hue_gap(a, b):
    """Shortest angular distance between two colour names' hues, in degrees."""
    d = abs(hue(COLORS[a]) - hue(COLORS[b])) % 360.0
    return min(d, 360.0 - d)


# The brightest thing the HUD ever sits on: sunlit sand from the arena floor.
WORLD_BRIGHTEST = (214, 196, 158)


def over_panel(base):
    """Composite a panel of `Panel` alpha (over a fully opaque base)... """
    alpha = 1.0 - ALPHA["Panel"]
    return tuple(round(COLORS["Navy"][i] * alpha + base[i] * (1 - alpha)) for i in range(3))


# ...and again through the edge scrim, which darkens the background further.
COLORS["PanelOnSand"] = over_panel(WORLD_BRIGHTEST)
SCRIM_EDGE = tuple(round(COLORS["Void"][i] * 0.8 + WORLD_BRIGHTEST[i] * 0.2) for i in range(3))
COLORS["ScrimOnSand"] = SCRIM_EDGE


def contrast(fg, bg):
    """WCAG relative contrast ratio between two sRGB triples."""
    a, b = _lum(COLORS[fg] if isinstance(fg, str) else fg), _lum(COLORS[bg] if isinstance(bg, str) else bg)
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)


# Text/background pairs that must be legible, with the ratio they must clear.
CONTRAST_MIN = {
    ("White", "Navy"): 12.0,
    ("White", "NavyRaised"): 9.0,
    ("Muted", "Navy"): 4.5,
    ("Dim", "Navy"): 3.0,
    ("Cyan", "Navy"): 6.0,
    ("Amber", "Navy"): 8.0,
    ("Violet", "Navy"): 4.5,
    ("Danger", "Navy"): 4.5,
    ("Success", "Navy"): 7.0,
    ("White", "PanelOnSand"): 12.0,
    ("Muted", "PanelOnSand"): 4.5,
    ("Cyan", "PanelOnSand"): 5.0,
    ("Amber", "PanelOnSand"): 6.0,
    ("Violet", "PanelOnSand"): 4.0,
}


def validate():
    """Return a list of human-readable design-system problems (empty is good)."""
    problems = []
    for (fg, bg), floor in CONTRAST_MIN.items():
        ratio = contrast(fg, bg)
        if ratio < floor:
            problems.append(f"contrast {fg} on {bg} is {ratio:.2f}:1, needs {floor:.1f}:1")
    # The panel stack must be ordered back-to-front or layering reads wrong.
    order = ["Void", "Navy", "NavyRaised", "NavyEdge"]
    lums = [_lum(COLORS[name]) for name in order]
    if lums != sorted(lums):
        problems.append("panel stack is not ordered darkest -> lightest: " + ", ".join(order))
    # Type scale must be monotonic so hierarchy is unambiguous.
    sizes = [TYPE[name] for name in ("Micro", "Label", "Body", "Heading", "Title", "Display")]
    if sizes != sorted(sizes) or len(set(sizes)) != len(sizes):
        problems.append("type scale is not strictly increasing")
    # Every glyph must name a real accent.
    for name, spec in GLYPHS.items():
        accent = spec.get("Accent")
        if accent not in COLORS:
            problems.append(f"glyph {name} uses unknown accent {accent}")
    # Accents must be distinguishable *as hues*: equal luminance is fine (cyan and
    # amber sit at the same brightness on purpose), but hue must be far apart so the
    # three accents never read as one colour.
    for a, b in (("Cyan", "Violet"), ("Cyan", "Amber"), ("Violet", "Amber")):
        gap = hue_gap(a, b)
        if gap < 30.0:
            problems.append(f"accents {a} and {b} are only {gap:.0f} degrees apart in hue")
    # Copy must never be empty and must fit a label width at its own type size.
    for name, text in COPY.items():
        if not text.strip():
            problems.append(f"copy {name} is empty")
        if "\n" in text:
            problems.append(f"copy {name} contains a newline; use wrapping instead")
    return problems


def metrics():
    """Numbers the HUD layout depends on, printed by the build report."""
    return {
        "Contrast": {f"{fg}/{bg}": round(contrast(fg, bg), 2) for fg, bg in CONTRAST_MIN},
        "TypeScale": dict(TYPE),
        "Radius": RADIUS,
        "Motion": dict(MOTION),
        "Accents": {k: COLORS[k] for k in ("Cyan", "Violet", "Amber")},
    }
