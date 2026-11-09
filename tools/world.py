"""Original low-poly world specification, shared by the Studio export and runtime builder.

ART DIRECTION (visual redesign pass)
------------------------------------
A stylised tropical archipelago at late afternoon: pale sand shores, teal stone
courts, a lush garden lobby and a single ceremonial brain beacon. Colour is used
to build hierarchy, not noise:

  level 1  ground        sand, sandstone, limestone, teal stone   (low saturation)
  level 2  nature        tropical greens, driftwood, pebbles      (low saturation)
  level 3  built props   timber, canvas, warm lantern light       (low saturation)
  level 4  hero objects  pink / gold / prism brain cells, beacon  (saturated, reserved)

Nothing saturated is used for environment surfaces. Purple has been removed from
the architecture entirely; it survives only as the beacon's energy seam.

GAMEPLAY IS UNTOUCHED: every collidable transform (position, size, rotation,
shape) is byte-identical to the previous build; pickups, spawns, bridges, rails
and beacon stairs keep their exact coordinates. Only colour, material, shadow
flags and *non-colliding* decoration have changed. `tests/fixtures/world-baseline.json`
freezes the walkable geometry for verification.

No toolbox models, meshes, decals, or remote asset dependencies.
"""
from __future__ import annotations

import math

from theme import MATERIALS, rgb, shade
import terrain_aug
import events


def make_world():
    parts, signs = [], []

    # ---------------------------------------------------------------- helpers
    def part(name, pos, size, color, *, rotation=(0, 0, 0), mat="smooth",
             collide=False, shape="Block", cls="Part", transparency=0.0, shadow=None):
        """Add one primitive. `mat` is a theme material token, `color` a palette name."""
        material, casts = MATERIALS[mat]
        item = {
            "Name": name, "Position": list(pos), "Size": list(size),
            "Color": rgb(color), "Rotation": list(rotation),
            "Material": material, "MaterialToken": mat,
            "CastShadow": casts if shadow is None else shadow,
            "Collide": collide, "Shape": shape, "Class": cls,
            "Transparency": transparency,
        }
        parts.append(item)
        return item

    def disk(name, x, y, z, radius, height, color, **kwargs):
        """Vertical cylinder. Rotation stays (0,0,90) so its axis is the Y axis."""
        return part(name, (x, y, z), (height, radius * 2, radius * 2), color,
                    rotation=(0, 0, 90), shape="Cylinder", **kwargs)

    def ball(name, pos, size, color, **kwargs):
        return part(name, pos, size, color, shape="Ball", **kwargs)

    def board(name, pos, size, rotation, lines, *, bg="panel", face="Front", mat="smooth",
              collide=True):
        # The world spec only stores the editable panel and its sign text. The
        # exporter bakes one extra non-colliding board instance carrying the
        # SurfaceGui, so the runtime builder never has two overlapping panels.
        part(name, pos, size, bg, rotation=rotation, collide=collide, mat=mat)
        signs.append({"Part": name, "Face": face, "Lines": lines})

    def line(text, color="sign_cream", weight="Bold", fraction=1, font="GothamBold"):
        return {"Text": text, "Color": rgb(color), "Weight": weight,
                "Fraction": fraction, "Font": font}

    # ------------------------------------------------------------- island body
    def island(name, x, z, radius, *, floor="sand", floor_mat="sand",
               cliff="rock", facet_a="rock", facet_b="slate", facets=None):
        """Layered floating island: dark keel, cliff band, wet ledge, top floor.

        The cylinder transforms are fixed by the walkable baseline; only the
        colour/material suffix markers change here.
        """
        for suffix, y, r, height, color, mat in (
            ("Rock", 17.5, radius + 1, 5, cliff, "rock"),
            ("RockLower", 14.55, radius + 0.55, 4.4, "rock_dark", "basalt"),
            ("RockTail", 11.55, max(3, radius - 2.5), 2.9, "teal_shadow", "slate"),
            ("Trim", 19.7, radius + 1.2, 0.7, "sand_wet", "pebble"),
            ("Turf", 20.5, radius, 1, floor, floor_mat),
        ):
            collide = suffix in ("Rock", "Turf")
            kwargs = {"collide": True} if collide else {}
            shape = "Cylinder"
            _part = part(f"{name}_{suffix}", (x, y, z), (height, r * 2, r * 2), color,
                         rotation=(0, 0, 90), shape=shape, mat=mat, **kwargs)
            _part["Role"] = "walkable" if collide else "island"
            _part["Island"] = name
        # Underside: a ring of smaller rock facets. Reads as a broken cliff instead of
        # two huge flat planes, and keeps every facet out of the walkable volume.
        count = facets if facets is not None else (10 if radius > 30 else 6)
        for i in range(count):
            a = i * math.tau / count
            r = radius * 0.62
            wobble = 1 + .18 * math.sin(i * 2.1)
            _part = part(f"{name}_Facet_{i}",
                         (x + math.cos(a) * r, 13.6 + .8 * math.sin(i * 1.7),
                          z + math.sin(a) * r),
                         (radius * .46 * wobble, 6.4 * wobble, radius * .4),
                         facet_b if i % 2 else facet_a,
                         cls="WedgePart", rotation=(0, -math.degrees(a), 180),
                         mat="rock" if i % 2 else "slate")
            _part["Role"] = "island"
            _part["Island"] = name

    # ------------------------------------------------------------------- palms
    def palm(name, x, z, height=10, *, lean=-7, base=True):
        """Signal palm: collidable trunk (unchanged transform) + tropical crown."""
        part(name + "_Trunk", (x, 21 + height / 2, z), (1.3, height, 1.3), "trunk",
             rotation=(0, 0, lean), collide=True, mat="planks")
        if base:
            disk(name + "_Base", x, 21.16, z, 1.65, 0.32, "sand_shade", mat="pebble")
        # Four long fronds, each a single tapered wedge: a full crown in 4 parts.
        for i in range(4):
            a = math.tau * i / 4 + .4
            droop = -14 - (i % 2) * 6
            part(name + f"_Fan_{i}", (x + .6 + math.cos(a) * 3.4, 21 + height - .15,
                                      z + math.sin(a) * 3.4),
                 (8.2, 1.2, 2.9), "leaf_light" if i % 2 else "leaf",
                 rotation=(0, -math.degrees(a), droop), cls="WedgePart")
            if i % 2 == 0:
                part(name + f"_Tip_{i}", (x + .6 + math.cos(a) * 5.9, 21 + height - .9,
                                          z + math.sin(a) * 5.9),
                     (2.5, .55, 1.8), "frond", rotation=(0, -math.degrees(a), droop - 14),
                     cls="WedgePart", shadow=False)

    # ------------------------------------------------------------- rock gardens
    def boulders(name, x, z, scale=1.0, *, colors=("rock", "rock_light", "teal_stone")):
        ball(f"{name}_0", (x, 21 + .9 * scale, z), (3.4 * scale, 2.6 * scale, 3.0 * scale),
             colors[0], mat="rock")
        part(f"{name}_1", (x + 1.9 * scale, 21 + .55 * scale, z - .9 * scale),
             (2.2 * scale, 1.5 * scale, 2.0 * scale), colors[1], cls="WedgePart",
             rotation=(0, 28, 180), shadow=False)


    def beam(name, start, end, thickness, color, *, mat="planks", shadow=True, taper=1.0):
        """A rotated block spanning two points.

        Two points -> one part: the cheapest way to build masts, guy-wires, braces
        and roof edges without a mesh. `taper` shrinks the far end into a wedge-ish
        cross-section by scaling the perpendicular size.
        """
        (x1, y1, z1), (x2, y2, z2) = start, end
        dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
        length = math.sqrt(dx * dx + dy * dy + dz * dz)
        if length <= 1e-6:
            raise ValueError(f"{name}: zero-length beam")
        yaw = math.degrees(math.atan2(-dx, -dz)) % 360
        pitch = math.degrees(math.asin(max(-1.0, min(1.0, dy / length))))
        mid = ((x1 + x2) / 2, (y1 + y2) / 2, (z1 + z2) / 2)
        size = (thickness * taper, thickness * taper, length)
        return part(name, mid, size, color, rotation=(0, yaw, pitch), mat=mat, shadow=shadow)

    def rotate2d(x, z, cx, cz, angle):
        """Rotate a point (x, z) about (cx, cz) by `angle` radians."""
        dx, dz = x - cx, z - cz
        cos, sin = math.cos(angle), math.sin(angle)
        return (cx + dx * cos - dz * sin, cz + dx * sin + dz * cos)

    def cone(name, x, y, z, radius, rise, color, *, sides=8, mat="canvas", shadow=False, yaw=0.0):
        """Tiered parasol roof: three stacked cylinders with a slight taper.

        Reads as a thatched canopy from any angle, costs three parts, and never
        produces the huge flat facets a ring of wedges does at close range.
        `sides` and `yaw` are kept for call-site compatibility.
        """
        tiers = 3
        for i in range(tiers):
            r = radius * (1 - i * 0.26)
            h = rise / tiers
            disk(f"{name}_{i}", x, y + h * (i + .5), z, r, h, color, mat=mat,
                 shadow=shadow if i == tiers - 1 else False)
        disk(f"{name}_Eave", x, y - .18, z, radius * 1.06, .22, color, mat=mat, shadow=False)

    def gable_roof(name, x, y, z, width, depth, rise, color, *, yaw=0.0, mat="planks",
                   shadow=True, overhang=0.5):
        """Two pitched halves. `yaw` rotates the ridge; 0 runs along Z."""
        angle = math.degrees(math.atan2(rise, depth / 2))
        span = math.hypot(depth / 2, rise) + overhang
        yaw_rad = math.radians(yaw)
        for sign, tag in ((-1, "A"), (1, "B")):
            dx, dz = rotate2d(0, sign * depth / 4, 0, 0, yaw_rad)
            part(f"{name}_{tag}", (x + dx, y + rise / 2, z + dz),
                 (width + overhang * 2, 0.32, span), color,
                 rotation=(sign * angle, yaw, 0), mat=mat, shadow=shadow)

    def grass_patch(name, x, z, radius, color="leaf"):
        disk(name, x, 21.05, z, radius, 0.1, color, mat="grass", shadow=False)

    # ------------------------------------------------------------------ brain
    def brain(name, x, y, z, scale=1):
        """Six lobes and a clean split: a recognisable, entirely procedural brain."""
        for side in (-1, 1):
            for j in range(3):
                ball(f"{name}_Lobe_{side}_{j}", (x + side * 1.5 * scale, y + (1 if j == 1 else .3) * scale,
                                                z + (j - 1) * 1.8 * scale),
                     (3.3 * scale, 3.8 * scale, 3 * scale), "cell_pink")
        part(name + "_Split", (x, y + .5 * scale, z), (.18 * scale, 3.3 * scale, 4.5 * scale),
             "rift_violet", mat="neon")
        ball(name + "_Stem", (x, y - 2.1 * scale, z), (1.5 * scale, 1.6 * scale, 1.5 * scale),
             "cell_pink")

    # ---------------------------------------------------------------- the sea
    # One enormous flat disc under everything: the archipelago reads as islands in
    # an ocean rather than props floating in a void. Two parts, no transparency
    # sorting cost, and the fog fades it into the horizon.
    disk("Sea_Shelf", 0, 5.0, 40, 980, 3.0, "sea_deep", mat="slate", shadow=False)
    disk("Sea_Surface", 0, 6.0, 40, 930, .6, "sea_tint", mat="slate", shadow=False)
    disk("Sea_Shallow", 0, 6.34, 40, 168, .12, "sea_shallow", mat="slate", shadow=False)

    # =========================================================== THE ARENA
    # A sun-bleached stone court on a sand island. Reads as one designed place:
    # beach ring -> stone court -> inlaid circuit -> ceremonial beacon.
    island("Arena", 0, 0, 52, floor="sand", floor_mat="sand")

    disk("Arena_Shore", 0, 20.995, 0, 51.4, .03, "sand_shade", mat="sand", shadow=False)
    disk("Arena_CourtBorder", 0, 21.015, 0, 41.6, .03, "teal_deep", mat="sandstone", shadow=False)
    disk("Arena_Court", 0, 21.035, 0, 40.6, .03, "court_stone", mat="sandstone", shadow=False)
    disk("Arena_CourtRing", 0, 21.05, 0, 24.6, .03, "teal_stone", mat="slate", shadow=False)
    disk("Arena_CourtInner", 0, 21.06, 0, 24.0, .03, "limestone", mat="marble", shadow=False)

    # Circuit inlay: neutral stone intaglio, one stud proud of the court.
    for i in range(12):
        a = i * math.tau / 12
        part(f"Circuit_Inlay_{i}", (math.cos(a) * 33, 21.08, math.sin(a) * 33),
             (15.8, .07, 5.8), "teal_stone" if i % 2 == 0 else "teal_deep",
             rotation=(0, -math.degrees(a) + 90, 0), mat="slate", shadow=False)
        # Inset node studs give the circuit a readable rhythm without neon.

    # Satellite platforms: sand shelf, grass heart, teal stone inlay.
    for i, (x, z) in enumerate(((73, 0), (-73, 0), (0, 73), (0, -73))):
        island(f"Satellite_{i}", x, z, 16, floor="sand", floor_mat="sand")
        disk(f"Satellite_{i}_Lawn", x, 21.045, z, 13.4, .05, "leaf", mat="grass", shadow=False)
        disk(f"Satellite_{i}_Inlay", x, 21.08, z, 9.4, .05, "stone_trim", mat="limestone", shadow=False)
        disk(f"Satellite_{i}_InlayCore", x, 21.1, z, 5.2, .05, "teal_deep", mat="slate", shadow=False)
        bridge_pos = (math.copysign(59, x) if x else 0, 20.5, math.copysign(59, z) if z else 0)
        size = (28, 1, 12) if x else (12, 1, 28)
        part(f"Bridge_{i}", bridge_pos, size, "wood_light", collide=True, mat="planks")
        if x:
            for side in (-1, 1):
                part(f"BridgeTrim_{i}_{side}", (bridge_pos[0], 21.15, side * 5.5), (28, .3, .5),
                     "wood_dark", mat="planks", shadow=False)
        else:
            for side in (-1, 1):
                part(f"BridgeTrim_{i}_{side}", (side * 5.5, 21.15, bridge_pos[2]), (.5, .3, 28),
                     "wood_dark", mat="planks", shadow=False)

        palm(f"Satellite_{i}_Palm", x + (8 if z else 0), z + (8 if x else 0), 8)
        boulders(f"Satellite_{i}_Boulder", x - (8.5 if z else 0), z - (8.5 if x else 0), .8)
        # Waypoint mast: a warm lantern, never a second rarity colour.
        a = math.atan2(z, x) + math.radians(135)
        mx, mz = x + math.cos(a) * 11.3, z + math.sin(a) * 11.3
        part(f"Satellite_{i}_Mast", (mx, 26.4, mz), (.42, 10.8, .42), "wood", mat="planks")
        ball(f"Satellite_{i}_Lantern", (mx, 31.9, mz), (1.7, 1.7, 1.7), "lantern", mat="neon")
        disk(f"Satellite_{i}_LanternCap", mx, 32.9, mz, .95, .3, "basalt", mat="slate", shadow=False)

    # Low perimeter parapet leaves the four cardinal bridge approaches open.
    for i in range(16):
        a = i * math.tau / 16
        # Cardinal gaps are the four bridge approaches, exactly as before.
        if i % 4 == 0:
            continue
        x, z = math.cos(a) * 50, math.sin(a) * 50
        part(f"Rail_{i}", (x, 23, z), (13, .65, .75), "stone_path",
             rotation=(0, 90 - math.degrees(a), 0), collide=True, mat="limestone")
        for side in (-1, 1):
            dx, dz = -math.sin(a) * side * 5.7, math.cos(a) * side * 5.7
            part(f"RailPost_{i}_{side}", (x + dx, 22.2, z + dz), (.9, 2.4, .9), "teal_stone",
                 collide=True, mat="limestone")

    # ---------------------------------------------------------- hero beacon
    disk("Beacon_Step_1", 0, 21.5, 0, 12, 1, "limestone", collide=True, mat="marble")
    disk("Beacon_Step_2", 0, 22.5, 0, 9, 1, "sand_shade", collide=True, mat="sandstone")
    disk("ChaosAccent_BeaconRing", 0, 23.08, 0, 7, .17, "beacon_gold", mat="neon", shadow=False)
    disk("Beacon_Plinth", 0, 24, 0, 4.4, 1.8, "basalt", collide=True, mat="basalt")
    disk("ChaosAccent_BeaconTop", 0, 25, 0, 4.8, .3, "beacon_pink", mat="neon", shadow=False)
    brain("Great_Brain_Beacon", 0, 29.6, 0, 1.95)
    for i in range(4):
        a = i * math.pi / 2
        for step in range(3):
            r = 14 - step * 1.6
            part(f"Beacon_Stair_{i}_{step}", (math.cos(a) * r, 21.2 + step * .32, math.sin(a) * r),
                 (2.1, .4 + step * .64, 7.5), "limestone",
                 rotation=(0, -math.degrees(a), 0), collide=True, mat="marble")
        # Framing columns give the landmark vertical rhythm and a warm uplight.
        part(f"Beacon_Column_{i}", (math.cos(a) * 10.9, 27.4, math.sin(a) * 10.9),
             (1.5, 12.4, 1.5), "basalt", rotation=(0, -math.degrees(a), 0), mat="basalt")
        ball(f"Beacon_ColumnLight_{i}", (math.cos(a) * 10.9, 34.1, math.sin(a) * 10.9),
             (1.5, 1.5, 1.5), "lantern", mat="neon", shadow=False)

    # Spawn medallions: pale stone discs with a teal lip, no neon. Two parts each.
    for i in range(8):
        a = (i + .5) * math.tau / 8
        disk(f"SpawnPad_{i}", math.cos(a) * 36, 21.1, math.sin(a) * 36, 2.85, .04, "teal_stone",
             mat="limestone", shadow=False)
        disk(f"SpawnPadRing_{i}", math.cos(a) * 36, 21.12, math.sin(a) * 36, 2.4, .05, "limestone",
             mat="marble", shadow=False)

    # --------------------------------------------------------- arena nature
    for i in range(8):
        a = (i + .5) * math.tau / 8
        palm(f"Arena_Palm_{i}", math.cos(a) * 46, math.sin(a) * 46, 9 + (i % 3))
    for i in range(8):
        a = (i + .2) * math.tau / 8
        boulders(f"Arena_Boulder_{i}", math.cos(a) * 46, math.sin(a) * 46, .7)

    # ============================================================== THE LOBBY
    # A garden terrace: lawn, stone plaza, framed signage and a timber entrance
    # gate that reads as the door to the arena.
    island("Lobby", 0, 180, 38, floor="leaf", floor_mat="grass")

    disk("Lobby_Plaza", 0, 21.02, 180, 24, .04, "sand_light", mat="sandstone", shadow=False)
    disk("Lobby_PlazaRing", 0, 21.06, 180, 15, .04, "teal_stone", mat="limestone", shadow=False)
    disk("Lobby_PlazaCenter", 0, 21.1, 180, 12.5, .06, "limestone", mat="marble", shadow=False)
    # Compass rose inlay: a readable stone cross in the plaza centre. Four rays
    # instead of eight keeps the detail while respecting the part budget.
    for i in range(4):
        a = i * math.tau / 4
        part(f"Lobby_Rose_{i}", (math.cos(a) * 5.6, 21.15, 180 + math.sin(a) * 5.6),
             (10.4, .04, 1.8), "sand_shade" if i % 2 else "stone_path",
             rotation=(0, -math.degrees(a), 0), shadow=False)
    # A continuous paving band replaces the old confetti ring: one inlay instead
    # of sixteen scatter stones, and it reads as a designed path edge.
    disk("Lobby_Confetti", 0, 21.15, 180, 21.6, .12, "sand_shade", mat="sandstone", shadow=False)
    disk("Lobby_ConfettiLip", 0, 21.17, 180, 19.9, .1, "teal_stone", mat="limestone", shadow=False)

    for i in range(6):
        a = i * math.tau / 6
        palm(f"Lobby_Palm_{i}", math.cos(a) * 33, 180 + math.sin(a) * 33, 10)
    for i in range(4):
        a = (i + .5) * math.tau / 4
        grass_patch(f"Lobby_Lawn_{i}", math.cos(a) * 27, 180 + math.sin(a) * 27, 3.6,
                    "leaf_light" if i % 2 else "leaf")

    # Social props: benches, planters and two shade umbrellas facing the plaza.
    for i, side in enumerate((-1, 1)):
        for j, along in enumerate((-8, 0, 8)):
            x, z = side * 26.5, 180 + along
            part(f"Lobby_Bench_{i}_{j}_Seat", (x, 22.1, z), (2.2, .3, 5.2),
                 "wood_light", mat="planks")
            part(f"Lobby_Bench_{i}_{j}_Leg", (x, 21.5, z), (.5, 1.2, 4.4),
                 "wood_dark", mat="planks", shadow=False)
            part(f"Lobby_Bench_{i}_{j}_Back", (x + side * .95, 22.85, z), (.28, 1.5, 5.2),
                 "wood", mat="planks", shadow=False)
        disk(f"Lobby_Planter_{i}", side * 20.5, 21.35, 180, 2.6, .7, "teal_stone", mat="pebble")
        ball(f"Lobby_Shrub_{i}", (side * 20.5, 22.5, 180), (3.6, 2.8, 3.6), "leaf_dark")
        ball(f"Lobby_ShrubTop_{i}", (side * 20.2, 24.1, 180), (2.4, 2.0, 2.4), "leaf_light", shadow=False)
        disk(f"Lobby_UmbrellaPole_{i}", side * 13.6, 24.2, 193.5, .3, 6.8, "wood", mat="planks")
        part(f"Lobby_Umbrella_{i}", (side * 13.6, 27.4, 193.5), (8.8, .24, 8.8), "sand_shade",
             mat="canvas", rotation=(0, 45 * i, 0))
        part(f"Lobby_UmbrellaCrown_{i}", (side * 13.6, 28.3, 193.5), (3.8, .28, 3.8), "canvas",
             mat="canvas", rotation=(0, 45 * i, 0), shadow=False)

    # Lobby brain shrines (grounded on stone stands, clearly "special objects").
    for side in (-1, 1):
        disk(f"Lobby_BrainStand_{side}", side * 21, 22, 158, 3, 2, "basalt", collide=True, mat="basalt")
        disk(f"Lobby_BrainStandRim_{side}", side * 21, 23.1, 158, 3.3, .3, "sand_shade",
             mat="sandstone", shadow=False)
        brain(f"Lobby_Brain_{side}", side * 21, 25.5, 158, .75)

    # ------------------------------------------------------- entrance portal
    # Timber gate with stone feet, lanterns, a hanging banner and a warm veil.
    part("Queue_ArchLeft", (-9, 29, 155), (2.5, 16, 3), "wood_dark", collide=True, mat="planks")
    part("Queue_ArchRight", (9, 29, 155), (2.5, 16, 3), "wood_dark", collide=True, mat="planks")
    part("Queue_ArchTop", (0, 37, 155), (20.5, 3, 3), "wood_dark", collide=True, mat="planks")
    for side in (-1, 1):
        part(f"Portal_Foot_{side}", (side * 9, 21.6, 155), (3.6, 1.2, 4.2), "teal_stone",
             mat="pebble", shadow=False)
        part(f"Portal_Beam_{side}", (side * 9, 31.4, 156.2), (.6, 8.6, .6), "wood_light",
             mat="planks", shadow=False)
        ball(f"Portal_Lantern_{side}", (side * 6.6, 34.4, 156.6), (1.45, 1.45, 1.45),
             "lantern", mat="neon", shadow=False)
        part(f"Portal_LanternBracket_{side}", (side * 6.6, 35.6, 156.6), (.3, 1.6, .3),
             "basalt", shadow=False)
    part("ChaosAccent_QueueLeft", (-7.55, 29, 156.65), (.3, 14, .3), "lantern", mat="neon", shadow=False)
    part("ChaosAccent_QueueRight", (7.55, 29, 156.65), (.3, 14, .3), "lantern", mat="neon", shadow=False)
    disk("Portal_Medallion", 0, 21.12, 155, 6.4, .05, "sand_shade", mat="sandstone", shadow=False)
    disk("Portal_MedallionCore", 0, 21.16, 155, 4.6, .04, "teal_stone", mat="limestone", shadow=False)

    board("Entrance_Banner", (0, 34.0, 156.55), (13, 3.2, .3), (0, 180, 0),
          [line("SYNAPSE CIRCUIT", "sign_gold", fraction=1.05, font="GothamBlack"),
           line("STEP IN  •  AUTO JOIN", "sign_cream", font="GothamBold")],
          bg="wood_dark", mat="planks", collide=False)

    # ---------------------------------------------------------------- signage
    # Dark charcoal panel (matching the HUD) inside a timber frame: the wordmark
    # gets ~7:1 contrast while the frame keeps it physically part of the gate.
    part("TitleBoard", (0, 43.4, 155), (31, 9, .8), "ink", rotation=(0, 180, 0),
         collide=True, mat="smooth")
    for side in (-1, 1):
        part(f"Title_Post_{side}", (side * 14.4, 30.6, 155), (1.2, 17.6, 1.2), "wood",
             mat="planks", shadow=False)
        part(f"Title_PostFoot_{side}", (side * 14.4, 21.4, 155), (2.4, .9, 2.4), "basalt",
             shadow=False)
        part(f"Title_Frame_{side}", (side * 15.9, 43.4, 154.4), (.7, 9.9, .7), "wood_light",
             rotation=(0, 180, 0), mat="planks", shadow=False)
    part("Title_FrameTop", (0, 48.4, 154.4), (32.4, .7, .7), "wood_light", rotation=(0, 180, 0),
         mat="planks", shadow=False)
    part("Title_Canopy", (0, 50.2, 152.6), (34, .5, 7.2), "canvas", mat="canvas",
         rotation=(0, 180, 0), shadow=False)
    for side in (-1, 1):
        part(f"Title_CanopyArm_{side}", (side * 15.4, 49.2, 154.6), (.5, 2.4, .5), "wood_dark",
             mat="planks", shadow=False)
    signs.append({"Part": "TitleBoard", "Face": "Front", "Lines": [
        line("BRAINROT", "sign_gold", fraction=1.25, font="GothamBlack"),
        line("A R E N A", "sign_pink", fraction=1.05, font="GothamBlack"),
    ]})

    board("QueueStatusBoard", (0, 37.1, 156.55), (14, 2.4, .4), (0, 180, 0),
          [line("AUTO JOIN • EVERY ROUND", "sign_cream")], bg="panel")

    board("RulesBoard", (-26, 28.5, 179), (19, 13, .7), (0, -160, 0),
          [line("HOW IT WORKS", "sign_gold", .95, .8),
           line("COLLECT. SURVIVE. REPEAT.", "sign_cream", 1.0, 1.15),
           line("PINK +1    GOLD +5    PRISM +10", "sign_cream", .95, 1.05),
           line("MOST CELLS IN 3 MINUTES WINS", "sign_cream", .95, 1.0),
           line("LOW GRAVITY = BIG JUMPS", "sign_prism", .95, 1.0),
           line("FALL? YOUR SCORE STAYS.", "sign_cream", .95, 1.0)],
          bg="panel")

    board("RewardsBoard", (26, 28.5, 179), (19, 13, .7), (0, 160, 0),
          [line("PLAY FOR YOUR GLOW", "sign_gold", 1.0, 1.15),
           line("EARN COINS EVERY ROUND", "sign_cream", .95, 1.05),
           line("PULSE HALO • 100 COINS", "sign_prism", .95, 1.0),
           line("OPEN REWARDS IN YOUR HUD", "sign_cream", .95, 1.0),
           line("COINS LAST THIS SESSION", "sign_cream", .95, 1.0)],
          bg="panel")

    # Framed map boards: a limestone frame set just behind each panel, standing on
    # a stone plinth. Reads as signage instead of a floating dark slab. The frame
    # shares each panel's yaw so it can never swing across the text.
    # Yaw is chosen so each panel's Front face points back down the plaza toward
    # the spawn: signage must be readable on approach, not only from the arena.
    for side, board_name, board_yaw in ((-1, "RulesBoard", -160), (1, "RewardsBoard", 160)):
        yaw = math.radians(board_yaw)
        nx, nz = -math.sin(yaw), -math.cos(yaw)      # panel facing normal (local -Z)
        for leg in (-1, 1):
            part(f"{board_name}_Foot_{leg}", (side * 26 + leg * 6.5, 21.7, 179),
                 (1.0, 1.4, 1.6), "basalt", shadow=False)
        part(f"{board_name}_Plinth", (side * 26, 21.6, 179), (20, 1.2, 2.6), "teal_stone",
             rotation=(0, board_yaw, 0), mat="sandstone", shadow=False)
        part(f"{board_name}_Frame", (side * 26 - nx * .55, 28.5, 179 - nz * .55),
             (20.6, 14.4, .5), "limestone", rotation=(0, board_yaw, 0),
             mat="sandstone", shadow=False)
        part(f"{board_name}_Cap", (side * 26 - nx * .9, 36.0, 179 - nz * .9),
             (21.4, .55, 2.4), "wood_dark", rotation=(0, board_yaw, 0),
             mat="planks", shadow=False)

    # Welcome mat: stone inlay from the spawn pad to the plaza.
    part("Lobby_WelcomePath", (0, 21.08, 186), (6, .04, 12), "sand_shade",
         mat="sandstone", shadow=False)
    part("Lobby_PathStud", (0, 21.12, 183), (3.2, .04, 1.2), "teal_stone", shadow=False)

    part("LobbySpawn", (0, 21.4, 188), (8, .4, 8), "limestone", cls="SpawnLocation",
         mat="marble", collide=True, transparency=.1)

    # ----------------------------- distant decorative islets (out of play)
    for i, (x, z, y) in enumerate(((-122, -80, 46), (116, -90, 57), (-108, 104, 38), (108, 195, 60))):
        # Floating islet: grass crown, sand lip, two faceted rock masses and a keel.
        disk(f"SkyShard_{i}_Top", x, y, z, 9, 2, "leaf", mat="leafy")
        disk(f"SkyShard_{i}_Shore", x, y - 1.15, z, 9.3, .5, "sand_shade", mat="sand", shadow=False)
        ball(f"SkyShard_{i}_Rock", (x, y - 4.6, z), (15, 7.4, 14), "rock_light", mat="rock")
        ball(f"SkyShard_{i}_RockLow", (x + 1.4, y - 7.8, z - .8), (9.6, 6.2, 9.0),
             "rock", mat="rock", shadow=False)
        ball(f"SkyShard_{i}_Keel", (x - .6, y - 11.0, z + .6), (5.2, 4.4, 5.0), "teal_shadow",
             mat="slate", shadow=False)
        ball(f"SkyShard_{i}_Signal", (x + 3.2, y + 3.4, z - 2.4), (2.6, 2.6, 2.6), "signal_prism",
             mat="neon", shadow=False)

    # ------------------------------------------------------------- pickups
    # Unchanged: 48 server-owned collection slots with verified walkable floors.
    pickups = []
    for radius, count, offset in ((20, 8, .15), (31, 12, .35), (43, 16, 0)):
        for i in range(count):
            a = (i + offset) * math.tau / count
            pickups.append({"x": round(math.cos(a) * radius, 4), "y": 23.5, "z": round(math.sin(a) * radius, 4)})
    for x, z in ((73, 0), (-73, 0), (0, 73), (0, -73)):
        for dx, dz in ((-5, -4), (5, -4), (0, 5)):
            pickups.append({"x": x + dx, "y": 23.5, "z": z + dz})

    # -------------------------------------------------------------- spawns
    arena_spawns = []
    lobby_spawns = []
    for i in range(8):
        a = (i + .5) * math.tau / 8
        arena_spawns.append([round(math.cos(a) * 36, 4), 25, round(math.sin(a) * 36, 4)])
        lobby_spawns.append([round(math.cos(a) * 6, 4), 25, 187 + round(math.sin(a) * 6, 4)])
    # ---- Phase 2 built environment: pavilion, lookout, beach bar, shrine, dock,
    # camp, kiosk, pergolas, terrace and the nature pass. All decorative parts are
    # non-colliding unless they are structural (posts, decks, stairs, totems).
    terrain_aug.extend_arena({
        "part": part, "disk": disk, "ball": ball, "beam": beam, "cone": cone,
        "gable_roof": gable_roof, "rotate2d": rotate2d,
    })
    terrain_aug.extend_satellites({
        "part": part, "disk": disk, "ball": ball, "beam": beam, "cone": cone,
        "gable_roof": gable_roof, "rotate2d": rotate2d,
    })
    terrain_aug.extend_lobby({
        "part": part, "disk": disk, "ball": ball, "beam": beam, "cone": cone,
        "gable_roof": gable_roof, "rotate2d": rotate2d,
        "signs": signs, "line": line, "board": board,
    })
    terrain_aug.extend_nature({
        "part": part, "disk": disk, "ball": ball, "beam": beam,
    })
    # ---- Phase 5 event geometry: three moving rafts and four vanishing paths.
    # Both are ordinary anchored parts; the server animates them by name during a
    # round, and they rest in the pose baked here.
    events.build({"part": part, "disk": disk})

    _finalize(parts)
    return {"Version": 1, "Parts": parts, "Signs": signs, "PickupPositions": pickups,
            "ArenaSpawns": arena_spawns, "LobbySpawns": lobby_spawns}


# ---------------------------------------------------------------------------
# Read-only metadata used by the art-direction verification and the preview
# renderer. It never affects how a part is built, coloured or collided.
# The visual hierarchy is explicit: 1 ground, 2 nature, 3 built props, 4 hero.
# ---------------------------------------------------------------------------
_ANCHORS = (
    ("Arena", (0, 0)),
    ("Satellite_0", (73, 0)), ("Satellite_1", (-73, 0)),
    ("Satellite_2", (0, 73)), ("Satellite_3", (0, -73)),
    ("Lobby", (0, 180)),
)
_FOLIAGE_MARKERS = ("_Fan_", "_Tip_", "_Trunk", "_Bud", "_Coconut", "_Shrub", "_Hedge",
                    "Lawn", "Palm", "_Top", "_Base", "Bloom", "_Flower", "Fern", "_Bed",
                    "Driftwood", "DriftKnot", "Vine", "FlowerPatch")


def _finalize(parts):
    for item in parts:
        name, token = item["Name"], item["MaterialToken"]
        if name.startswith("Sea_"):
            # The ocean is its own ground plane: it belongs to no island group.
            item["Role"], item["Layer"] = "sea", 1
            item["Island"], item["BakeOnly"] = "Sea", False
            continue
        if name.startswith("ChaosAccent_") or token == "neon":
            role, layer = "accent", 4
        elif "Brain_" in name:
            # The living Brain Cells / beacon lobes: reserved hero objects.
            role, layer = "hero", 4
        elif item["Name"].startswith("SkyShard_"):
            role, layer = "island", 2
        elif any(marker in name for marker in _FOLIAGE_MARKERS):
            role, layer = "foliage", 2
        elif item["Collide"]:
            role, layer = "ground", 1
        elif token in ("rock", "basalt", "slate", "pebble"):
            role, layer = "rock", 2
        else:
            role, layer = "prop", 3
        item["Role"] = role
        item["Layer"] = layer
        item["BakeOnly"] = False
        if "Island" not in item:
            if item["Name"].startswith("SkyShard_"):
                item["Island"] = "SkyShard_" + item["Name"].split("_")[1]
            else:
                x, z = item["Position"][0], item["Position"][2]
                item["Island"] = min(
                    _ANCHORS, key=lambda a: (x - a[1][0]) ** 2 + (z - a[1][1]) ** 2)[0]
