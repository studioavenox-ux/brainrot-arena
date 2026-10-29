"""Original low-poly world specification, shared by the Studio export and runtime builder.
No toolbox models, meshes, decals, or remote asset dependencies.
"""
from __future__ import annotations
import math

P = {
    "ink": [23, 24, 63], "rock": [67, 47, 119], "rock_light": [105, 71, 169],
    "grass": [99, 218, 154], "mint": [151, 247, 183], "path": [255, 221, 99],
    "cyan": [66, 228, 247], "purple": [155, 95, 255], "pink": [255, 94, 190],
    "white": [239, 250, 255], "gold": [255, 194, 61], "trunk": [149, 97, 75],
    "leaf": [47, 190, 141], "leaf_light": [158, 239, 91], "blue": [65, 139, 228],
}


def make_world():
    parts, signs = [], []

    def part(name, pos, size, color, *, rotation=(0, 0, 0), material="SmoothPlastic",
             collide=False, shape="Block", cls="Part", transparency=0):
        item = {"Name": name, "Position": list(pos), "Size": list(size),
                "Color": P.get(color, color), "Rotation": list(rotation),
                "Material": material, "Collide": collide, "Shape": shape,
                "Class": cls, "Transparency": transparency}
        parts.append(item)
        return item

    def disk(name, x, y, z, radius, height, color, **kwargs):
        return part(name, (x, y, z), (height, radius * 2, radius * 2), color,
                    rotation=(0, 0, 90), shape="Cylinder", **kwargs)

    def ball(name, pos, size, color, **kwargs):
        return part(name, pos, size, color, shape="Ball", **kwargs)

    def board(name, pos, size, rotation, lines, *, bg="ink", face="Front"):
        part(name, pos, size, bg, rotation=rotation, collide=True)
        signs.append({"Part": name, "Face": face, "Lines": lines})

    def line(text, color="white", weight="Bold", fraction=1):
        return {"Text": text, "Color": P.get(color, color), "Weight": weight, "Fraction": fraction}

    def island(name, x, z, radius):
        disk(name + "_Rock", x, 17.5, z, radius + 1, 5, "rock", collide=True)
        disk(name + "_Trim", x, 19.7, z, radius + 1.2, 0.7, "purple")
        disk(name + "_Turf", x, 20.5, z, radius, 1, "grass", collide=True)
        for i in range(6 if radius > 30 else 3):
            a = i * math.tau / (6 if radius > 30 else 3)
            r = radius * 0.55
            part(f"{name}_Facet_{i}", (x + math.cos(a) * r, 12.5, z + math.sin(a) * r),
                 (radius * .8, 9, radius * .65), "rock_light" if i % 2 else "rock",
                 cls="WedgePart", rotation=(0, -math.degrees(a), 180))

    def tree(name, x, z, height=10):
        # Deliberately original "signal palms": angular trunks and oversized geometric fans.
        part(name + "_Trunk", (x, 21 + height / 2, z), (1.3, height, 1.3), "trunk",
             rotation=(0, 0, -7), collide=True)
        ball(name + "_Bud", (x + .6, 21 + height, z), (2.4, 2.4, 2.4), "gold")
        for i in range(5):
            a = math.tau * i / 5
            part(name + f"_Fan_{i}", (x + .6 + math.cos(a)*3.1, 21 + height, z + math.sin(a)*3.1),
                 (6.6, 1.1, 2.6), "leaf_light" if i % 2 else "leaf",
                 rotation=(0, -math.degrees(a), -12), cls="WedgePart")

    def crystal(name, x, z, color, scale=1):
        for i, (dx, dz, height) in enumerate(((-1, 0, 3), (.7, .2, 4.4), (1.6, 1, 2.4))):
            part(f"{name}_{i}", (x + dx*scale, 21 + height*scale/2, z + dz*scale),
                 (1.8*scale, height*scale, 1.7*scale), color, rotation=(0, 25*i, 12-10*i),
                 cls="WedgePart", material="Neon" if i == 1 else "SmoothPlastic")

    def brain(name, x, y, z, scale=1):
        # Six lobes and a clean split: a recognizable, entirely procedural brain beacon.
        for side in (-1, 1):
            for j in range(3):
                ball(f"{name}_Lobe_{side}_{j}", (x + side*1.5*scale, y + (1 if j == 1 else .3)*scale,
                                               z + (j-1)*1.8*scale),
                     (3.3*scale, 3.8*scale, 3*scale), "pink", material="SmoothPlastic")
        part(name + "_Split", (x, y + .5*scale, z), (.18*scale, 3.3*scale, 4.5*scale),
             "purple", material="Neon")

    # SYNAPSE CIRCUIT: generous safe floor, four connected satellite islands, one beacon.
    island("Arena", 0, 0, 52)
    for i in range(12):
        a = i * math.tau / 12
        part(f"Circuit_Inlay_{i}", (math.cos(a)*33, 21.06, math.sin(a)*33),
             (15.8, .12, 5.8), "path" if i % 2 == 0 else "mint", rotation=(0, -math.degrees(a)+90, 0))
    for i, (x, z) in enumerate(((73, 0), (-73, 0), (0, 73), (0, -73))):
        color = ("cyan", "gold", "purple", "pink")[i]
        island(f"Satellite_{i}", x, z, 16)
        bridge_pos = (math.copysign(59, x) if x else 0, 20.5, math.copysign(59, z) if z else 0)
        size = (28, 1, 12) if x else (12, 1, 28)
        part(f"Bridge_{i}", bridge_pos, size, "path", collide=True)
        if x:
            for side in (-1, 1):
                part(f"BridgeTrim_{i}_{side}", (bridge_pos[0], 21.15, side*5.5), (28, .3, .5), color, material="Neon")
        else:
            for side in (-1, 1):
                part(f"BridgeTrim_{i}_{side}", (side*5.5, 21.15, bridge_pos[2]), (.5, .3, 28), color, material="Neon")
        disk(f"Satellite_{i}_Inlay", x, 21.04, z, 11, .08, color)
        tree(f"Satellite_{i}_Palm", x + (8 if z else 0), z + (8 if x else 0), 8)
        crystal(f"Satellite_{i}_Crystal", x - (9 if z else 0), z - (9 if x else 0), color, .8)

    # Low perimeter rails leave cardinal bridge approaches open.
    for i in range(16):
        a = i * math.tau / 16
        if i % 4 == 0:
            continue
        x, z = math.cos(a)*50, math.sin(a)*50
        part(f"Rail_{i}", (x, 23, z), (13, .65, .75), "purple",
             rotation=(0, 90-math.degrees(a), 0), collide=True)
        for side in (-1, 1):
            dx, dz = -math.sin(a)*side*5.7, math.cos(a)*side*5.7
            part(f"RailPost_{i}_{side}", (x+dx, 22.2, z+dz), (.9, 2.4, .9), "white", collide=True)

    disk("Beacon_Step_1", 0, 21.5, 0, 12, 1, "white", collide=True)
    disk("Beacon_Step_2", 0, 22.5, 0, 9, 1, "purple", collide=True)
    disk("ChaosAccent_BeaconRing", 0, 23.08, 0, 7, .17, "cyan", material="Neon")
    disk("Beacon_Plinth", 0, 24, 0, 4.4, 1.8, "ink", collide=True)
    disk("ChaosAccent_BeaconTop", 0, 25, 0, 4.8, .3, "pink", material="Neon")
    brain("Great_Brain_Beacon", 0, 28.8, 0, 1.55)
    for i in range(4):
        a = i*math.pi/2
        for step in range(3):
            r = 14-step*1.6
            part(f"Beacon_Stair_{i}_{step}", (math.cos(a)*r, 21.2+step*.32, math.sin(a)*r),
                 (2.1, .4+step*.64, 7.5), "white", rotation=(0, -math.degrees(a), 0), collide=True)
    for i in range(8):
        a = (i+.5)*math.tau/8
        tree(f"Arena_Palm_{i}", math.cos(a)*46, math.sin(a)*46, 9+(i%3))
    for i in range(8):
        a = (i+.2)*math.tau/8
        crystal(f"Arena_Geode_{i}", math.cos(a)*46, math.sin(a)*46, "cyan" if i%2 else "purple", .65)
    for i in range(8):
        a = (i+.5)*math.tau/8
        disk(f"SpawnPad_{i}", math.cos(a)*36, 21.07, math.sin(a)*36, 2.4, .14, "cyan")

    # LOBBY: a separate social island. The arch is a queue landmark, not a fake store.
    island("Lobby", 0, 180, 38)
    disk("Lobby_Plaza", 0, 21.04, 180, 24, .08, "white")
    disk("Lobby_PlazaRing", 0, 21.1, 180, 15, .12, "purple")
    disk("Lobby_PlazaCenter", 0, 21.18, 180, 12.5, .14, "ink")
    for i in range(16):
        a = i*math.tau/16
        part(f"Lobby_Confetti_{i}", (math.cos(a)*20, 21.15, 180+math.sin(a)*20),
             (2, .12, 4), ("cyan", "pink", "gold", "purple")[i%4], rotation=(0, -math.degrees(a), 0))
    part("Queue_ArchLeft", (-9, 29, 155), (2.5, 16, 3), "purple", collide=True)
    part("Queue_ArchRight", (9, 29, 155), (2.5, 16, 3), "purple", collide=True)
    part("Queue_ArchTop", (0, 37, 155), (20.5, 3, 3), "purple", collide=True)
    part("ChaosAccent_QueueLeft", (-7.55, 29, 156.65), (.3, 14, .3), "cyan", material="Neon")
    part("ChaosAccent_QueueRight", (7.55, 29, 156.65), (.3, 14, .3), "cyan", material="Neon")
    part("Queue_Glow", (0, 29, 154), (14, 14, .3), "cyan", material="Neon", transparency=.78)
    board("TitleBoard", (0, 43.4, 155), (31, 9, .8), (0, 180, 0),
          [line("BRAINROT", "gold", fraction=1.2), line("ARENA", "pink", fraction=1.2)])
    board("QueueStatusBoard", (0, 34, 157), (14, 3, .5), (0, 180, 0),
          [line("AUTO JOIN • EVERY ROUND", "cyan")])
    board("RulesBoard", (-26, 28.5, 179), (19, 13, .7), (0, -70, 0),
          [line("COLLECT. SURVIVE. REPEAT.", "gold"), line("PINK +1   GOLD +5   PRISM +10"),
           line("MOST CELLS IN 3 MINUTES WINS"), line("LOW GRAVITY = BIG JUMPS", "cyan"),
           line("FALL? YOUR SCORE STAYS.")])
    board("RewardsBoard", (26, 28.5, 179), (19, 13, .7), (0, 70, 0),
          [line("PLAY FOR YOUR GLOW", "pink"), line("EARN COINS EVERY ROUND"),
           line("PULSE HALO • 100 COINS", "cyan"), line("OPEN REWARDS IN YOUR HUD"),
           line("COINS & HALO LAST THIS SESSION")])
    for side in (-1, 1):
        disk(f"Lobby_BrainStand_{side}", side*21, 22, 158, 3, 2, "ink", collide=True)
        brain(f"Lobby_Brain_{side}", side*21, 25.5, 158, .75)
    for i in range(6):
        a = i*math.tau/6
        tree(f"Lobby_Palm_{i}", math.cos(a)*33, 180+math.sin(a)*33, 10)
    part("LobbySpawn", (0, 21.4, 188), (8, .4, 8), "cyan", cls="SpawnLocation",
         material="Neon", collide=True, transparency=.1)

    # Decorative satellites are intentionally distant from the playable routes.
    for i, (x, z, y) in enumerate(((-122, -80, 46), (116, -90, 57), (-108, 104, 38), (108, 195, 60))):
        disk(f"SkyShard_{i}_Top", x, y, z, 9, 2, "mint")
        part(f"SkyShard_{i}_Rock", (x, y-5, z), (14, 10, 14), "rock_light", cls="WedgePart", rotation=(0, i*40, 180))
        ball(f"SkyShard_{i}_Signal", (x, y+4, z), (4, 4, 4), "cyan" if i%2 else "pink", material="Neon")

    pickups = []
    for radius, count, offset in ((20, 8, .15), (31, 12, .35), (43, 16, 0)):
        for i in range(count):
            a = (i+offset)*math.tau/count
            pickups.append({"x": round(math.cos(a)*radius, 4), "y": 23.5, "z": round(math.sin(a)*radius, 4)})
    for x, z in ((73, 0), (-73, 0), (0, 73), (0, -73)):
        for dx, dz in ((-5, -4), (5, -4), (0, 5)):
            pickups.append({"x": x+dx, "y": 23.5, "z": z+dz})
    arena_spawns = []
    lobby_spawns = []
    for i in range(8):
        a = (i+.5)*math.tau/8
        arena_spawns.append([round(math.cos(a)*36, 4), 25, round(math.sin(a)*36, 4)])
        lobby_spawns.append([round(math.cos(a)*6, 4), 25, 187+round(math.sin(a)*6, 4)])
    return {"Version": 1, "Parts": parts, "Signs": signs, "PickupPositions": pickups,
            "ArenaSpawns": arena_spawns, "LobbySpawns": lobby_spawns}
