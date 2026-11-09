"""Phase 5 event geometry: moving platforms and temporary disappearing paths.

Why these exist
---------------
The survival events need real geometry, not a screen tint. Two of them are places
you stand on:

* **Moving platforms**  three stone rafts that ride the beach promenade in a slow
  orbit. They are *not* baked as moving parts (Roblox cannot animate a welded
  anchored assembly cheaply, and the export must stay deterministic): they are
  baked at their parked position and the server moves them by pivot each tick.
* **Vanishing paths**   four short spans that rise out of the floor to join the
  arena ring to the four satellite bridges. They are baked hidden and non-colliding
  and only become solid during the event.

Both sets are ordinary anchored Parts with explicit names, so the servers can find
them by name and the export verifier can assert their rest pose, their climb range
and that nothing overlaps a pickup ring or a spawn pad.

Design rules
------------
* Same primitive vocabulary and palette as everything else (teal stone, timber,
  warm lantern light). No new materials, no saturated environment colour.
* Nothing sits on a pickup slot, an arena spawn or a bridge approach: the arena is
  y = 21.0, pickup slots are a ring at r = 20/31/43 and the bridges leave the arena
  at the four diagonals, x = z.
* Every part is non-colliding at rest, so a parked raft can never trap a player.
"""
from __future__ import annotations

import math

# --------------------------------------------------------------------------- #
# Moving platforms
# --------------------------------------------------------------------------- #
# Each raft rides a small circle: centre, radius, phase and height. The circle is
# chosen in the gaps between the promenade buildings and the pickup rings.
# The rafts ride circles on the *diagonals*, in the lane between the r = 31 and
# r = 43 pickup rings, where no pickup slot, spawn pad, bridge or rail post lives.
# Top surface 21.9 is 0.9 studs above the arena floor: step-up-able, unmistakably a
# platform, and never a trap when it is parked.
# A 25.5-stud orbit is the widest clean lane on the arena floor: it clears the
# beacon stairs (r <= 16) and the rail ring (r >= 33), and still stays 5.5 studs from
# the nearest pickup slot at every point of the circuit.
PLATFORMS = (
    # name suffix, orbit centre (x, z), orbit radius, phase, top surface
    ("A", (0.0, 0.0), 25.5, math.radians(45), 21.9),
    ("B", (0.0, 0.0), 25.5, math.radians(165), 21.9),
    ("C", (0.0, 0.0), 25.5, math.radians(285), 21.9),
)
PLATFORM_SIZE = (5.0, .55, 5.0)
PLATFORM_PERIOD = 30.0       # seconds for one full circuit
PLATFORM_RING_PARTS = 4


def platform_pose(index: int, t: float):
    """World position of raft `index` at orbit time `t` (seconds). Pure + seeded."""
    _name, (cx, cz), radius, phase, top = PLATFORMS[index]
    angle = phase + t * math.tau / PLATFORM_PERIOD
    return (cx + math.cos(angle) * radius, top - PLATFORM_SIZE[1] / 2, cz + math.sin(angle) * radius)


def platform_parts(part, disk):
    """Bake the three rafts at their parked pose, plus the orbit marker rings."""
    out = []
    for index, (suffix, (cx, cz), radius, phase, top) in enumerate(PLATFORMS):
        x, y, z = platform_pose(index, 0.0)
        out.append(part(f"EventRaft_{suffix}_Deck", (x, y, z), PLATFORM_SIZE, "teal_stone",
                        collide=False, mat="marble"))
        # A warm underglow *below* the deck: the walkable surface stays teal stone
        # (readable against sand) and the raft still glows like a levitating tile.
        out.append(part(f"EventRaft_{suffix}_Lip", (x, y - PLATFORM_SIZE[1] / 2 - .07, z),
                        (PLATFORM_SIZE[0] + .3, .12, PLATFORM_SIZE[2] + .3), "lantern",
                        collide=False, mat="neon", shadow=False))
        for ring in range(PLATFORM_RING_PARTS):
            a = math.tau * ring / PLATFORM_RING_PARTS
            out.append(disk(f"EventRaft_{suffix}_Stud_{ring}",
                            x + math.cos(a) * (PLATFORM_SIZE[0] / 2 - .55),
                            y + PLATFORM_SIZE[1] / 2 + .02,
                            z + math.sin(a) * (PLATFORM_SIZE[2] / 2 - .55),
                            .34, .1, "teal_shadow", mat="slate", shadow=False))
        # The orbit is drawn on the floor: a dashed ring of small inlays. Purely
        # decorative, so the player can read where the raft will travel.
        # 16 dashes, not 24: the orbit line only has to read as "this thing circles
        # here", and every extra inlay is a part a phone has to draw.
        for dash in range(12):
            # 12 dashes evenly around the full circle (the divisor must match the
            # count, or the orbit line reads as a broken arc instead of a ring).
            a = math.tau * dash / 12
            out.append(disk(f"EventRaft_{suffix}_Track_{dash}",
                            cx + math.cos(a) * radius, 21.06, cz + math.sin(a) * radius,
                            .38, .08, "sand_shade", mat="sandstone", shadow=False))
    return out


# --------------------------------------------------------------------------- #
# Vanishing paths
# --------------------------------------------------------------------------- #
# Four spans, one per diagonal, joining the arena ring to the satellite bridges.
# They are hidden at rest (transparency 1, non-colliding) and lift 0.9 studs when
# the event runs.
# Four diagonal shortcut spans that reach out over open water from just outside the
# arena rail (r = 48) toward the satellites (r = 58). Solid only while the event
# runs: a legal risk, since the existing fall rescue returns anyone who drops.
PATH_SPAN = (3.4, .35, 6.2)
PATH_SEGMENTS = 3
PATH_LIFT = .9
PATH_ANGLES = (45.0, 135.0, 225.0, 315.0)
PATH_RADIUS = 49.0      # clear of the r = 43 pickup ring and of the arena rail


def path_pose(index: int, segment: int):
    """World position of one span segment. Deterministic, used by bake and server."""
    angle = math.radians(PATH_ANGLES[index])
    radius = PATH_RADIUS + segment * (PATH_SPAN[2] + .5)
    return (math.cos(angle) * radius, 21.0 + PATH_SPAN[1] / 2, math.sin(angle) * radius)


def path_parts(part, disk):
    out = []
    for index, yaw in enumerate(PATH_ANGLES):
        for segment in range(PATH_SEGMENTS):
            x, y, z = path_pose(index, segment)
            out.append(part(f"EventPath_{index}_Span_{segment}", (x, y, z), PATH_SPAN,
                            "teal_stone", collide=False, rotation=(0, -yaw, 0),
                            mat="marble", transparency=1.0, shadow=False))
            out.append(part(f"EventPath_{index}_Glow_{segment}", (x, y + .2, z),
                            (PATH_SPAN[0] - .5, .08, .18), "lantern", collide=False,
                            rotation=(0, -yaw, 0), mat="neon", transparency=1.0, shadow=False))
        # Anchor posts stay visible: they explain where the path will appear.
        marker = path_pose(index, 0)
        out.append(disk(f"EventPath_{index}_Anchor", marker[0], 21.15, marker[2], .55, .3,
                        "teal_deep", mat="slate", shadow=False))
    return out


def build(world_builder):
    """Called by tools/world.py with the shared primitive helpers."""
    return platform_parts(world_builder["part"], world_builder["disk"]) + \
        path_parts(world_builder["part"], world_builder["disk"])
