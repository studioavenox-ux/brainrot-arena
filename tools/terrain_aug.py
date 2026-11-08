"""Phase 2 architecture pass: built structures layered onto the Phase 1 terrain.

Phase 1 proved the palette and the lighting. Phase 2 makes the island read as a
*place someone built*: a tea pavilion and a lookout tower on the arena promenade, a
beach bar on the sand, a carved shrine on the far shore, a dock, a camp, a kiosk and
an amphitheatre terrace in the lobby.

Design rules held by everything in this file
-------------------------------------------
* Same primitive vocabulary as `world.py` (block / ball / cylinder / wedge) — no
  meshes, models, unions, decals or asset ids, so the export stays fully editable.
* Structure, not scatter: every building has a floor plane, vertical supports, a
  pitched or parasol roof and one warm lantern. Nothing floats unattached.
* Teal stone + limewash plaster + timber + canvas only. No saturated colour: the
  pink / gold / prism budget still belongs to cells, the beacon and the HUD.
* Colliders are deliberate. Posts and stairs are solid; roofs, railings, awnings and
  decor are not. Nothing new stands on a pickup ring or a spawn pad, and the four
  cardinal bridge approaches stay clear.
* Part cost is spent where the camera actually looks: the lobby entrance and the
  beacon terrace get the most detail, the far beach gets the least.

The geometry is authored around the Phase 1 terrain heights: arena and lobby turf
tops are y = 21.0, so a floor slab is y ~= 21.2 and a 3-stud wall spans 21.2-27.2.
"""
from __future__ import annotations

import math

TAU = math.tau


# --------------------------------------------------------------------------- #
# Arena: promenade buildings + beach amenities
# --------------------------------------------------------------------------- #

def _pavilion(b, cx, cz):
    """Open tea pavilion: stone plinth, four timber posts, parasol roof, one lantern."""
    part, disk, ball, cone, beam = b["part"], b["disk"], b["ball"], b["cone"], b["beam"]
    # The plinth is only 0.3 studs proud of the sand: walkable, so it stays
    # non-colliding and can never pen a player in on a pickup ring.
    disk("Arena_Pavilion_Plinth", cx, 21.25, cz, 3.9, .5, "limestone", mat="marble")
    disk("Arena_Pavilion_PlinthTrim", cx, 21.55, cz, 3.3, .12, "teal_stone", mat="limestone",
         shadow=False)
    # Four posts on the diagonals so the interior stays walkable.
    for i in range(4):
        a = TAU * i / 4 + math.pi / 4
        px, pz = cx + math.cos(a) * 2.9, cz + math.sin(a) * 2.9
        part(f"Arena_Pavilion_Post_{i}", (px, 24.7, pz), (.7, 6.4, .7), "wood_dark",
             collide=True, mat="planks")
        part(f"Arena_Pavilion_Foot_{i}", (px, 21.65, pz), (1.4, .5, 1.4), "teal_stone",
             mat="pebble", shadow=False)
        # Bracket: a short beam leaning into the roof ring.
        beam(f"Arena_Pavilion_Brace_{i}", (px, 27.2, pz),
             (cx + math.cos(a) * 1.9, 28.0, cz + math.sin(a) * 1.9), .32, "wood_mid")
    cone("Arena_Pavilion_Roof", cx, 28.4, cz, 5.6, 2.0, "canvas", sides=8, mat="canvas")
    ball("Arena_Pavilion_Finial", (cx, 30.1, cz), (1.0, 1.0, 1.0), "wood_dark", shadow=False)
    ball("Arena_Pavilion_Lantern", (cx, 29.2, cz), (1.1, 1.1, 1.1), "lantern", mat="neon",
         shadow=False)
    # Tea table and two stools: the reason the pavilion exists.
    disk("Arena_Pavilion_Table", cx, 22.55, cz, 1.7, .22, "wood_light", mat="planks")
    part("Arena_Pavilion_TableLeg", (cx, 21.9, cz), (.5, 1.2, .5), "wood_dark", mat="planks",
         shadow=False)
    for i, a in enumerate((0.0, math.pi)):
        ball(f"Arena_Pavilion_Stool_{i}", (cx + math.cos(a) * 2.6, 21.9, cz + math.sin(a) * 2.6),
             (1.1, .9, 1.1), "teal_stone", mat="pebble", shadow=False)


def _lookout(b, cx, cz):
    """Lifeguard-style lookout tower: braced legs, railings, ladder and parasol roof."""
    part, ball, cone, beam, disk = b["part"], b["ball"], b["cone"], b["beam"], b["disk"]
    disk("Arena_Lookout_Base", cx, 21.2, cz, 3.4, .4, "limestone", collide=True, mat="sandstone")
    for i in range(4):
        a = TAU * i / 4 + math.pi / 4
        px, pz = cx + math.cos(a) * 2.3, cz + math.sin(a) * 2.3
        part(f"Arena_Lookout_Leg_{i}", (px, 26.4, pz), (.66, 10.8, .66), "wood_dark",
             collide=True, mat="planks")
    # Cross bracing, one beam per face: cheap and reads as engineering.
    for i in range(2):
        a = TAU * i / 4 + math.pi / 4
        a2 = a + math.pi / 2
        beam(f"Arena_Lookout_Brace_{i}",
             (cx + math.cos(a) * 2.3, 23.4, cz + math.sin(a) * 2.3),
             (cx + math.cos(a2) * 2.3, 27.6, cz + math.sin(a2) * 2.3), .3, "wood_mid",
             shadow=False)
    part("Arena_Lookout_Deck", (cx, 31.9, cz), (7.0, .5, 7.0), "wood_light", collide=True,
         mat="planks")
    for i in range(4):
        a = TAU * i / 4
        part(f"Arena_Lookout_Rail_{i}", (cx + math.cos(a) * 3.3, 33.1, cz + math.sin(a) * 3.3),
             (6.6 if i % 2 == 0 else .3, .3, .3 if i % 2 == 0 else 6.6), "wood_dark",
             mat="planks", shadow=False)
    cone("Arena_Lookout_Roof", cx, 34.4, cz, 4.6, 1.7, "canvas", sides=6, mat="canvas")
    ball("Arena_Lookout_Signal", (cx, 36.4, cz), (.9, .9, .9), "lantern", mat="neon", shadow=False)
    # Ladder: two rails plus four rungs, leaning on the seaward face.
    for side in (-1, 1):
        beam(f"Arena_Lookout_Ladder_{side}", (cx + side * .55, 21.2, cz + 3.0),
             (cx + side * .55, 31.9, cz + 1.4), .22, "wood_mid", shadow=False)
    for rung in range(3):
        y = 23.0 + rung * 3.0
        part(f"Arena_Lookout_Rung_{rung}", (cx, y, cz + 3.0 - (y - 21.2) * .155),
             (1.4, .16, .2), "wood_light", mat="planks", shadow=False)


def _beach_bar(b, cx, cz, yaw):
    """Sand-footed beach bar: counter, awning, crates, stools and a lantern string."""
    part, ball, beam, gable = b["part"], b["ball"], b["beam"], b["gable_roof"]
    rot = b["rotate2d"]
    part("Arena_BeachBar_Floor", (cx, 21.2, cz), (9.2, .4, 5.6), "wood_light",
         mat="planks", rotation=(0, yaw, 0))
    # Back wall: two plaster panels between three posts.
    for i, along in enumerate((-3.6, 0.0, 3.6)):
        px, pz = rot(cx + along, cz + 2.4, cx, cz, math.radians(-yaw))
        part(f"Arena_BeachBar_Post_{i}", (px, 23.6, pz), (.5, 5.2, .5), "wood_dark",
             collide=True, mat="planks")
    px, pz = rot(cx, cz + 2.4, cx, cz, math.radians(-yaw))
    part("Arena_BeachBar_Back", (px, 23.0, pz), (8.6, 3.2, .35), "canvas",
         rotation=(0, yaw, 0), mat="smooth")
    # Counter slab in front of the wall.
    px, pz = rot(cx, cz + .3, cx, cz, math.radians(-yaw))
    part("Arena_BeachBar_Counter", (px, 22.65, pz), (8.2, .3, 1.5), "wood_mid",
         collide=True, rotation=(0, yaw, 0), mat="planks")
    px, pz = rot(cx, cz + .3, cx, cz, math.radians(-yaw))
    part("Arena_BeachBar_CounterSkirt", (px, 22.0, pz), (8.0, 1.0, 1.2), "teal_stone",
         rotation=(0, yaw, 0), mat="sandstone", shadow=False)
    gable("Arena_BeachBar_Awning", cx, 26.2, cz, 10.4, 6.6, 1.5, "canvas", yaw=yaw,
          mat="canvas", overhang=1.0)
    beam("Arena_BeachBar_Ridge", (cx - math.cos(math.radians(yaw)) * 5.2, 27.6,
                                  cz + math.sin(math.radians(yaw)) * 5.2),
         (cx + math.cos(math.radians(yaw)) * 5.2, 27.6,
          cz - math.sin(math.radians(yaw)) * 5.2), .28, "wood_dark", shadow=False)
    ball("Arena_BeachBar_Lantern", (cx, 25.4, cz), (1.0, 1.0, 1.0), "lantern", mat="neon",
         shadow=False)
    for i, (dx, dz, size) in enumerate(((-3.4, -2.2, 1.5), (-2.0, -2.8, 1.2), (3.6, -2.4, 1.4))):
        px, pz = rot(cx + dx, cz + dz, cx, cz, math.radians(-yaw))
        part(f"Arena_BeachBar_Crate_{i}", (px, 21.2 + size / 2, pz), (size, size, size),
             "wood_mid" if i % 2 else "wood_light", rotation=(0, yaw + i * 12, 0), mat="planks",
             shadow=False)
    for i, dx in enumerate((-2.6, 0.4, 3.0)):
        px, pz = rot(cx + dx, cz - 1.9, cx, cz, math.radians(-yaw))
        ball(f"Arena_BeachBar_Stool_{i}", (px, 21.85, pz), (1.0, .8, 1.0), "teal_stone",
             mat="pebble", shadow=False)


def _shrine(b, cx, cz):
    """Carved shore shrine: stepped plinth, totem relief and a warm votive light."""
    part, disk, ball, beam = b["part"], b["disk"], b["ball"], b["beam"]
    disk("Arena_Shrine_Step1", cx, 21.35, cz, 5.2, .7, "limestone", mat="sandstone")
    disk("Arena_Shrine_Step2", cx, 21.95, cz, 3.9, .6, "sand_shade", mat="sandstone")
    disk("Arena_Shrine_Step3", cx, 22.45, cz, 2.8, .5, "teal_stone", mat="marble")
    # Totem: four tapering stone blocks with a carved band between them.
    heights = ((1.9, 2.6), (1.5, 2.2), (1.25, 2.0), (1.0, 1.7))  # (width, height)
    y = 22.7
    for i, (width, height) in enumerate(heights):
        part(f"Arena_Shrine_Totem_{i}", (cx, y + height / 2, cz), (width, height, width),
             "teal_stone" if i % 2 == 0 else "limestone", collide=True, mat="marble")
        y += height
        if i < len(heights) - 1:
            part(f"Arena_Shrine_Band_{i}", (cx, y + .12, cz), (width + .25, .25, width + .25),
                 "sand_shade", mat="sandstone", shadow=False)
            y += .25
    ball("Arena_Shrine_Orb", (cx, y + .8, cz), (1.5, 1.5, 1.5), "lantern", mat="neon",
         shadow=False)
    disk("Arena_Shrine_OrbCap", cx, y + 1.7, cz, .9, .3, "basalt", mat="basalt", shadow=False)
    # Low votive wall, broken at the walkable side.
    for i in range(2):
        a = math.pi * i
        part(f"Arena_Shrine_Wall_{i}", (cx + math.cos(a) * 3.6, 21.75, cz + math.sin(a) * 3.6),
             (3.2, .9, .7), "teal_deep", rotation=(0, -math.degrees(a) + 90, 0),
             collide=True, mat="sandstone")
    for i, a in enumerate((0.4, 2.7)):
        beam(f"Arena_Shrine_Banner_{i}", (cx + math.cos(a) * 2.9, 26.4, cz + math.sin(a) * 2.9),
             (cx + math.cos(a) * 4.6, 24.2, cz + math.sin(a) * 4.6), .18, "clay", shadow=False)


def extend_arena(b):
    """Promenade buildings on the diagonals, plus the beacon terrace detail."""
    # Diagonals of the beach promenade, at r = 44: the midpoint between two 43-stud
    # pickup slots, inside the rail ring, and clear of every spawn pad and bridge.
    _pavilion(b, 36.6, 24.4)
    _lookout(b, -36.6, -24.4)
    _beach_bar(b, 24.4, -36.6, yaw=-34)
    _shrine(b, -24.4, 36.6)

    part, disk, ball, beam = b["part"], b["disk"], b["ball"], b["beam"]
    # ---- beacon terrace: four diagonal pylons so the landmark reads as a monument
    for i in range(4):
        a = TAU * i / 4 + math.pi / 4
        x, z = math.cos(a) * 13.0, math.sin(a) * 13.0
        disk(f"Beacon_PylonBase_{i}", x, 21.6, z, 1.9, 1.2, "limestone", collide=True,
             mat="sandstone")
        part(f"Beacon_Pylon_{i}", (x, 24.2, z), (1.5, 4.6, 1.5), "teal_stone", collide=True,
             mat="marble")
        part(f"Beacon_PylonCap_{i}", (x, 26.7, z), (2.1, .45, 2.1), "basalt", mat="basalt",
             shadow=False)
        ball(f"Beacon_PylonLantern_{i}", (x, 27.4, z), (1.05, 1.05, 1.05), "lantern",
             mat="neon", shadow=False)
        # Low link wall between the pylon and the first step: frames the ceremony.
        mid = (math.cos(a) * 11.6, math.sin(a) * 11.6)
        part(f"Beacon_LinkWall_{i}", (mid[0], 21.9, mid[1]), (3.4, .8, .6), "sand_shade",
             rotation=(0, -math.degrees(a) + 90, 0), collide=True, mat="sandstone")
    # Plinth relief: four wedge fins give the dark base some carved depth.
    for i in range(4):
        a = TAU * i / 4
        part(f"Beacon_PlinthFin_{i}", (math.cos(a) * 4.4, 24.4, math.sin(a) * 4.4),
             (2.2, 3.0, 1.2), "teal_deep", rotation=(0, -math.degrees(a), 0),
             cls="WedgePart", mat="marble", shadow=False)
    # Ceremonial brazier ring on the terrace, outside the stairs.
    for i in range(2):
        a = TAU * i / 2 + math.pi / 4
        x, z = math.cos(a) * 16.4, math.sin(a) * 16.4
        disk(f"Beacon_Brazier_{i}", x, 21.5, z, 1.05, 1.0, "basalt", mat="basalt", shadow=False)
        ball(f"Beacon_BrazierEmber_{i}", (x, 22.3, z), (.7, .7, .7), "lantern", mat="neon",
             shadow=False)


# --------------------------------------------------------------------------- #
# Satellites: one landmark each, so the four platforms stop looking identical
# --------------------------------------------------------------------------- #

def _dock(b, cx, cz, yaw):
    """Timber pier reaching off the island edge, with crates and a mooring lamp."""
    part, ball, beam = b["part"], b["ball"], b["beam"]
    rot = b["rotate2d"]
    for i, along in enumerate((0.0, 4.6, 9.2)):
        px, pz = rot(cx + along, cz, cx, cz, math.radians(-yaw))
        part(f"Satellite_0_Dock_Deck_{i}", (px, 21.0, pz), (4.6, .45, 5.2), "wood_light",
             collide=True, rotation=(0, yaw, 0), mat="planks")
        for side in (-1, 1):
            px, pz = rot(cx + along + 1.6, cz + side * 2.3, cx, cz, math.radians(-yaw))
            part(f"Satellite_0_Dock_Pile_{i}_{side}", (px, 19.4, pz), (.5, 3.4, .5),
                 "wood_dark", rotation=(0, yaw, 0), mat="planks", shadow=False)
    px, pz = rot(cx + 9.8, cz, cx, cz, math.radians(-yaw))
    part("Satellite_0_Dock_LampPost", (px, 23.2, pz), (.34, 4.4, .34), "wood_dark", mat="planks",
         shadow=False)
    ball("Satellite_0_Dock_Lamp", (px, 25.6, pz), (1.0, 1.0, 1.0), "lantern", mat="neon",
         shadow=False)
    for i, (along, side, size) in enumerate(((3.0, -1.4, 1.5), (4.2, -1.2, 1.1), (7.4, 1.2, 1.3))):
        px, pz = rot(cx + along, cz + side, cx, cz, math.radians(-yaw))
        part(f"Satellite_0_Dock_Crate_{i}", (px, 21.2 + size / 2, pz), (size, size, size),
             "wood_mid", rotation=(0, yaw + i * 9, 0), mat="planks", shadow=False)
    for i, along in enumerate((5.6, 8.4)):
        px, pz = rot(cx + along, cz - 2.2, cx, cz, math.radians(-yaw))
        part(f"Satellite_0_Dock_Bollard_{i}", (px, 21.8, pz), (.6, 1.4, .6), "teal_stone",
             mat="pebble", shadow=False)


def _satellite_tower(b, cx, cz):
    """Small lookout tower: legs, deck, rails, parasol roof and a signal lamp."""
    part, ball, cone = b["part"], b["ball"], b["cone"]
    for i in range(4):
        a = TAU * i / 4 + math.pi / 4
        part(f"Satellite_1_Tower_Leg_{i}", (cx + math.cos(a) * 2.0, 25.0,
                                            cz + math.sin(a) * 2.0), (.58, 8.0, .58),
             "wood_dark", collide=True, mat="planks")
    part("Satellite_1_Tower_Deck", (cx, 28.9, cz), (6.2, .45, 6.2), "wood_light", collide=True,
         mat="planks")
    for i in range(4):
        a = TAU * i / 4
        part(f"Satellite_1_Tower_Rail_{i}", (cx + math.cos(a) * 2.9, 29.9,
                                             cz + math.sin(a) * 2.9),
             (5.8 if i % 2 == 0 else .28, .28, .28 if i % 2 == 0 else 5.8), "wood_dark",
             mat="planks", shadow=False)
    cone("Satellite_1_Tower_Roof", cx, 31.2, cz, 4.1, 1.6, "canvas", sides=6, mat="canvas")
    ball("Satellite_1_Tower_Lamp", (cx, 33.0, cz), (.85, .85, .85), "lantern", mat="neon",
         shadow=False)
    for i in range(3):
        part(f"Satellite_1_Tower_Stair_{i}", (cx + 3.6, 21.8 + i * .9, cz - 1.6 + i * 1.5),
             (2.6, .3, 1.7), "wood_mid", collide=True, mat="planks", shadow=False)


def _satellite_shrine(b, cx, cz):
    """Garden shrine: two stone steps, a carved totem and clipped shrubs."""
    part, disk, ball = b["part"], b["disk"], b["ball"]
    disk("Satellite_2_Shrine_Step", cx, 21.3, cz, 4.6, .6, "limestone", collide=True,
         mat="sandstone")
    disk("Satellite_2_Shrine_StepTop", cx, 21.8, cz, 3.4, .5, "teal_stone", collide=True,
         mat="marble")
    y = 22.05
    for i, width in enumerate((1.35, 1.05, .8)):
        part(f"Satellite_2_Shrine_Totem_{i}", (cx, y + width, cz), (width, width * 2, width),
             "limestone" if i % 2 else "teal_deep", collide=True, mat="marble")
        y += width * 2 + .18
    ball("Satellite_2_Shrine_Orb", (cx, y + .7, cz), (1.2, 1.2, 1.2), "lantern", mat="neon",
         shadow=False)
    for i, a in enumerate((0.6, 2.5, 4.3)):
        x, z = cx + math.cos(a) * 5.2, cz + math.sin(a) * 5.2
        disk(f"Satellite_2_Shrine_Planter_{i}", x, 21.3, z, 1.5, .5, "teal_stone", mat="pebble")
        ball(f"Satellite_2_Shrine_Shrub_{i}", (x, 22.2, z), (2.1, 1.7, 2.1), "leaf_dark",
             shadow=False)


def _satellite_camp(b, cx, cz, yaw):
    """Beach camp: canvas tent, log seats, fire pit with an ember."""
    part, disk, ball, gable, beam = b["part"], b["disk"], b["ball"], b["gable_roof"], b["beam"]
    rot = b["rotate2d"]
    for side in (-1, 1):
        px, pz = rot(cx, cz + side * 2.1, cx, cz, math.radians(-yaw))
        part(f"Satellite_3_Camp_Pole_{side}", (px, 23.2, pz), (.4, 4.4, .4), "wood_dark",
             mat="planks", shadow=False)
    gable("Satellite_3_Camp_Tent", cx, 23.4, cz, 4.6, 4.4, 2.0, "canvas", yaw=yaw,
          mat="canvas", overhang=.4)
    for side in (-1, 1):
        px, pz = rot(cx + side * 2.4, cz, cx, cz, math.radians(-yaw))
        part(f"Satellite_3_Camp_Wing_{side}", (px, 22.4, pz), (.6, 2.6, 4.2), "sand_shade",
             rotation=(0, yaw, 0), mat="canvas", shadow=False)
    disk("Satellite_3_Camp_Fire", cx + 5.4, 21.25, cz + 1.4, 1.6, .3, "basalt", mat="basalt",
         shadow=False)
    for i in range(5):
        a = TAU * i / 5
        ball(f"Satellite_3_Camp_Stone_{i}", (cx + 5.4 + math.cos(a) * 1.5, 21.45,
                                             cz + 1.4 + math.sin(a) * 1.5),
             (.7, .55, .7), "rock_light", mat="rock", shadow=False)
    ball("Satellite_3_Camp_Ember", (cx + 5.4, 21.6, cz + 1.4), (.9, .5, .9), "lantern",
         mat="neon", shadow=False)
    for i, (dx, dz, yaw_off) in enumerate(((2.6, 2.8, 20), (3.6, -1.4, -30))):
        beam(f"Satellite_3_Camp_Log_{i}", (cx + dx - 1.2, 21.6, cz + dz),
             (cx + dx + 1.2, 21.6, cz + dz + .5), .7, "wood_mid", shadow=False)


def extend_satellites(b):
    _dock(b, 84, 0, yaw=0)
    _satellite_tower(b, -80.5, 2.0)
    _satellite_shrine(b, -8.0, 81.0)
    _satellite_camp(b, 0, -78, yaw=90)


# --------------------------------------------------------------------------- #
# Lobby: the arrival sequence, which is where every player spawns
# --------------------------------------------------------------------------- #

def extend_lobby(b):
    part, disk, ball, beam, gable, cone = (b["part"], b["disk"], b["ball"], b["beam"],
                                           b["gable_roof"], b["cone"])
    signs, line = b["signs"], b["line"]
    board = b["board"]

    # ---- 1. Amphitheatre terrace behind the spawn: two stone steps and a hedge line
    for i, (depth, height) in enumerate(((5.2, .6), (3.4, 1.2))):
        z = 197.5 - i * 2.6
        part(f"Lobby_Terrace_Step_{i}", (0, 21.0 + height / 2, z), (34 - i * 6, height, depth),
             "limestone" if i == 0 else "sand_shade", collide=True, mat="sandstone")
    for i in range(5):
        x = -14 + i * 7
        ball(f"Lobby_Terrace_Hedge_{i}", (x, 22.4, 201.5), (6.4, 2.6, 3.4), "leaf_dark")
        ball(f"Lobby_Terrace_HedgeTop_{i}", (x, 23.5, 201.5), (5.0, 1.6, 2.8), "leaf_light",
             shadow=False)
    for side in (-1, 1):
        part(f"Lobby_Terrace_Pillar_{side}", (side * 18.4, 23.4, 199.4), (1.8, 4.8, 1.8),
             "teal_stone", collide=True, mat="marble")
        ball(f"Lobby_Terrace_Lamp_{side}", (side * 18.4, 26.1, 199.4), (1.1, 1.1, 1.1),
             "lantern", mat="neon", shadow=False)

    # ---- 2. Kiosk: a little counter hut facing the plaza
    kx, kz, kyaw = -15.5, 167.5, 62
    part("Lobby_Kiosk_Floor", (kx, 21.25, kz), (6.4, .5, 5.4), "wood_light",
         rotation=(0, kyaw, 0), mat="planks")
    for i, (dx, dz) in enumerate(((-2.4, -1.9), (2.4, -1.9), (-2.4, 1.9), (2.4, 1.9))):
        part(f"Lobby_Kiosk_Post_{i}", (kx + dx, 23.9, kz + dz), (.5, 5.0, .5), "wood_dark",
             collide=True, mat="planks")
    part("Lobby_Kiosk_Back", (kx, 23.4, kz + 1.9), (5.4, 3.4, .35), "clay",
         rotation=(0, kyaw, 0), mat="smooth")
    part("Lobby_Kiosk_Counter", (kx, 22.5, kz - 1.6), (5.6, .3, 1.3), "wood_mid", collide=True,
         rotation=(0, kyaw, 0), mat="planks")
    gable("Lobby_Kiosk_Roof", kx, 26.4, kz, 7.6, 6.4, 1.4, "canvas", yaw=kyaw, mat="canvas",
          overhang=.8)
    ball("Lobby_Kiosk_Lamp", (kx, 25.5, kz), (.9, .9, .9), "lantern", mat="neon", shadow=False)
    for i in range(1):
        part(f"Lobby_Kiosk_Crate_{i}", (kx + 3.4 + i * .2, 21.75 + i * .2, kz + 1.2 + i * 1.4),
             (1.3, 1.3, 1.3), "wood_mid", mat="planks", shadow=False)
    board("Lobby_KioskBoard", (kx + .2, 24.6, kz - 1.75), (4.6, 1.5, .2), (0, kyaw, 0),
          [line("HALO STAND", "sign_gold", .95, .85),
           line("100 COINS", "sign_cream", .95, .9)],
          bg="panel", mat="smooth", collide=False)

    # ---- 3. Pergola promenades: shade over both bench rows
    for side in (-1, 1):
        x = side * 29.5
        for i, z in enumerate((166, 173, 180, 187, 194)):
            part(f"Lobby_Pergola_Post_{side}_{i}", (x, 23.9, z), (.55, 5.8, .55), "wood_dark",
                 collide=True, mat="planks")
        beam(f"Lobby_Pergola_BeamA_{side}", (x, 26.9, 164.5), (x, 26.9, 195.5), .42,
             "wood_mid", shadow=False)
        beam(f"Lobby_Pergola_BeamB_{side}", (x, 27.2, 164.0), (x, 27.2, 196.0), .34,
             "wood_light", shadow=False)
        for i in range(6):
            z = 166.5 + i * 5.4
            part(f"Lobby_Pergola_Slat_{side}_{i}", (x, 27.5, z), (4.6, .22, .5), "wood_mid",
                 rotation=(0, 0, 0), mat="planks", shadow=False)
        # Vine growth along the pergola: reads as a planted structure, not a frame.
        for i in range(3):
            ball(f"Lobby_Pergola_Vine_{side}_{i}", (x - side * .6, 27.4, 170 + i * 9.6),
                 (3.4, 1.1, 2.6), "leaf_dark", shadow=False)

    # ---- 4. Bunting between the gate posts and the title posts
    for i in range(4):
        t = (i + .5) / 4
        x = -9 + 18 * t
        y = 33.6 - math.sin(t * math.pi) * 1.4
        part(f"Lobby_Bunting_{i}", (x, y, 155.6), (.9, .9, .06), "clay",
             rotation=(0, 0, (i % 2) * 8 - 4), mat="smooth", shadow=False)
    beam("Lobby_BuntingLine", (-9, 33.6, 155.6), (9, 33.6, 155.6), .1, "wood_dark", shadow=False)

    # ---- 5. Plaza edge planting: stone planters with flowers, either side of the path
    for i, side in enumerate((-1, 1)):
        for j in range(2):
            x, z = side * 8.4, 173 + j * 11.0
            disk(f"Lobby_PlanterBed_{i}_{j}", x, 21.35, z, 1.7, .7, "teal_stone", mat="pebble",
                 shadow=False)
            ball(f"Lobby_PlanterBloom_{i}_{j}", (x, 22.15, z), (2.0, 1.2, 2.0),
                 "leaf_light" if (i + j) % 2 else "leaf")
            ball(f"Lobby_PlanterFlower_{i}_{j}", (x + .3, 22.9, z - .2), (.8, .5, .8),
                 "clay", mat="smooth", shadow=False)

    # ---- 6. Twin lamp posts flanking the welcome path, so the spawn reads as an entry
    for side in (-1, 1):
        x, z = side * 5.6, 182.5
        disk(f"Lobby_LampBase_{side}", x, 21.35, z, .9, .7, "teal_stone", mat="pebble",
             shadow=False)
        part(f"Lobby_LampPost_{side}", (x, 24.0, z), (.42, 5.4, .42), "wood_dark", mat="planks")
        disk(f"Lobby_LampCap_{side}", x, 27.0, z, 1.0, .5, "clay", mat="smooth", shadow=False)
        ball(f"Lobby_LampGlobe_{side}", (x, 26.4, z), (1.0, 1.0, 1.0), "lantern", mat="neon",
             shadow=False)

    # ---- 7. Lobby wayfinding plaque beside the gate: the last thing seen on the way in
    board("Lobby_Plaque", (13.6, 25.0, 160.5), (5.2, 3.2, .3), (0, 148, 0),
          [line("ARENA", "sign_gold", .95, 1.0),
           line("THIS WAY  →", "sign_cream", .95, .9),
           line("3 MINUTES  •  AUTO JOIN", "sign_cream", .9, .75)],
          bg="panel", mat="smooth", collide=False)
    for side in (-1, 1):
        part(f"Lobby_PlaquePost_{side}", (13.6 + side * 2.1, 22.6, 160.5),
             (.35, 3.6, .35), "wood_dark", mat="planks", shadow=False)


# --------------------------------------------------------------------------- #
# Nature pass: shoreline driftwood, fern clumps and flower patches
# --------------------------------------------------------------------------- #

def extend_nature(b):
    part, ball, beam, disk = b["part"], b["ball"], b["beam"], b["disk"]
    # Driftwood and ferns on the arena beach, between the palms.
    for i in range(8):
        a = TAU * i / 8 + math.radians(12)
        x, z = math.cos(a) * 47.6, math.sin(a) * 47.6
        if i % 2:
            beam(f"Arena_Driftwood_{i}", (x - 1.6, 21.35, z - .8), (x + 1.8, 21.6, z + .9),
                 .55, "trunk_dark", shadow=False)
            ball(f"Arena_DriftKnot_{i}", (x + 1.9, 21.5, z + .9), (.9, .7, .8), "trunk",
                 shadow=False)
        else:
            for j, (dx, dz) in enumerate(((-.6, 0), (.7, .3), (0, .8))):
                part(f"Arena_Fern_{i}_{j}", (x + dx, 21.6, z + dz), (1.3, 1.1, .3),
                     "leaf_deep" if j % 2 else "leaf_dark",
                     rotation=(0, 30 * j + i * 15, -28), cls="WedgePart", shadow=False)
    # Flower patches: three clay dots on a green cushion, eight around the court.
    for i in range(4):
        a = TAU * i / 4 + math.radians(30)
        x, z = math.cos(a) * 44.2, math.sin(a) * 44.2
        disk(f"Arena_FlowerPatch_{i}", x, 21.12, z, 1.6, .12, "moss", mat="grass", shadow=False)
        for j in range(2):
            b_angle = TAU * j / 2 + i
            ball(f"Arena_Flower_{i}_{j}", (x + math.cos(b_angle) * .6, 21.35,
                                           z + math.sin(b_angle) * .6), (.5, .42, .5), "clay",
                 mat="smooth", shadow=False)
    # Shrub fringes around the lobby terrace and behind the planner beds.
    for i in range(4):
        a = TAU * i / 4 + .4
        x, z = math.cos(a) * 30.5, 180 + math.sin(a) * 30.5
        ball(f"Lobby_ShrubFringe_{i}", (x, 22.3, z), (3.0, 2.2, 3.0), "leaf_dark", shadow=False)
        ball(f"Lobby_ShrubFringeTop_{i}", (x + .4, 23.9, z + .3), (1.9, 1.5, 1.9),
             "leaf_sun", shadow=False)
    # Satellite ground cover, so the four islands are not bare turf.
    for index, (cx, cz) in enumerate(((73, 0), (-73, 0), (0, 73), (0, -73))):
        for j in range(2):
            a = TAU * j / 2 + index * 1.1
            x, z = cx + math.cos(a) * 9.4, cz + math.sin(a) * 9.4
            disk(f"Satellite_{index}_Bed_{j}", x, 21.12, z, 2.2, .1, "moss", mat="grass",
                 shadow=False)
            ball(f"Satellite_{index}_BedShrub_{j}", (x, 21.9, z), (1.9, 1.4, 1.9),
                 "leaf_light" if j % 2 else "leaf_dark", shadow=False)
