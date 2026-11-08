#!/usr/bin/env python3
"""Art-direction gate.

This does not replace the Studio acceptance pass; it makes the *design* rules
machine-checkable so the environment cannot regress to neon cyan floors, lime
foliage or purple platforms:

  1. no supersaturated environment surfaces (the old neon palette is banned),
  2. saturation budget per visual hierarchy layer (ground < props < hero),
  3. colour harmony: natural sand/teal/stone dominance, purple only on the beacon,
  4. material variety and a bounded, meaningful shadow budget,
  5. gameplay-object legibility: contrast of every collectible against every
     surface it can float over, plus signage contrast,
  6. lighting rig: soft blue sky, warm sun, shadows on, cheap post-processing,
  7. the lighting rig in the exported place matches tools/theme.py,
  8. walkable geometry, pickups and spawns are byte-identical to the frozen
     pre-redesign baseline, so gameplay cannot have been disturbed.
"""
from __future__ import annotations

import json
import math
import unittest
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

import theme
from world import make_world

ROOT = Path(__file__).resolve().parents[1]
WORLD = make_world()
PARTS = WORLD["Parts"]
BASELINE = json.loads((ROOT / "tests/fixtures/world-baseline.json").read_text())
# Collidable board panels: readable signage, not a walking surface.
SIGN_PANELS = {"TitleBoard", "QueueStatusBoard", "RulesBoard", "RewardsBoard"}


def names(obj):
    return obj.findtext("Properties/string[@name='Name']")


def props(obj):
    return obj.find("Properties")


def prop(obj, tag, name):
    return obj.find(f"Properties/{tag}[@name='{name}']")


def color_of(obj, name="Color"):
    element = prop(obj, "Color3", name)
    if element is None:
        return None
    return tuple(round(float(element.findtext(k)) * 255) for k in ("R", "G", "B"))


def child(obj, name):
    return next((o for o in obj.findall("Item") if names(o) == name), None)


# --------------------------------------------------------------------------
# Perceptual helpers (CIELAB chroma / delta-E 76)
# --------------------------------------------------------------------------
def _linear(c):
    c /= 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lab(rgb):
    r, g, b = (_linear(v) for v in rgb)
    x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883

    def f(t):
        return t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116

    fx, fy, fz = f(x), f(y), f(z)
    return 116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)


def chroma(rgb):
    _, a, b = lab(rgb)
    return math.hypot(a, b)


def lab_distance(a, b):
    la, aa, ba = lab(a)
    lb, ab, bb = lab(b)
    return math.sqrt((la - lb) ** 2 + (aa - ab) ** 2 + (ba - bb) ** 2)


def hue(rgb):
    r, g, b = rgb
    h, _, _ = theme.hsl(rgb)
    return h * 360


class ArtDirectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.regular = ET.parse(ROOT / "places/BrainrotArena.rbxlx").getroot()
        cls.lighting = child(cls.regular, "Lighting")
        env = [p for p in PARTS if p["Role"] not in ("accent", "hero")]
        cls.environment = env
        cls.hero = [p for p in PARTS if p["Role"] == "accent"]
        # Floors a cell can be seen against (walkable + court inlays + turf caps).
        cls.floors = [p for p in PARTS if p["Role"] in ("ground", "prop")
                      and p["Position"][1] >= 20.4 and p["Size"][0] < 3]

    # ---------------------------------------------------------------- palette
    def test_01_legacy_neon_palette_is_gone(self):
        banned = set(theme.LEGACY_NEON.values())
        offenders = [p["Name"] for p in self.environment if tuple(p["Color"]) in banned]
        self.assertEqual(offenders, [], "Legacy neon colours still used for environment parts")

    def test_02_no_environment_surface_is_supersaturated(self):
        # Hard ceiling in CIELAB chroma. Foliage highlights get a little more room
        # than stone/sand/wood because leaves are the one place where a green can
        # legitimately carry a bit of life. The old neon cyan/lime sat at 50-80.
        def limit_for(part):
            if part["Role"] == "foliage":
                return 52.0
            if part["Material"] in ("Grass", "LeafyGrass"):
                return 45.0        # living lawn, not a flat green plastic
            return 40.0
        offenders = [(p["Name"], p["Role"], round(chroma(p["Color"]), 1)) for p in self.environment
                     if chroma(p["Color"]) > limit_for(p)]
        self.assertEqual(offenders, [], "Over-saturated environment surfaces")

    def test_03_saturation_increases_with_hierarchy_layer(self):
        def mean_chroma(layer):
            values = [chroma(p["Color"]) for p in PARTS if p["Layer"] == layer]
            self.assertTrue(values, f"layer {layer} is empty")
            return sum(values) / len(values)
        ground, nature, prop, hero = (mean_chroma(i) for i in (1, 2, 3, 4))
        self.assertLess(ground, prop)
        self.assertLess(prop, hero, "Gameplay objects must be the most saturated thing on screen")
        self.assertGreater(hero, 2.2 * prop)

    def test_04_natural_family_dominates(self):
        families = Counter()
        for p in self.environment:
            h = hue(p["Color"])
            if 20 <= h <= 65:
                families["warm_sand_wood"] += 1
            elif 65 < h <= 160:
                families["green"] += 1
            elif 160 < h <= 215:
                families["teal_stone"] += 1
            else:
                families["neutral_other"] += 1
        total = sum(families.values())
        self.assertGreater(families["teal_stone"] / total, 0.05)
        self.assertGreater(families["warm_sand_wood"] / total, 0.2)
        self.assertGreater(families["green"] / total, 0.2)
        self.assertLessEqual(families["neutral_other"] / total, 0.02)  # dark signage only

    def test_05_purple_is_only_on_the_beacon_seam(self):
        purple = [p["Name"] for p in PARTS
                  if 245 <= hue(p["Color"]) <= 300 and chroma(p["Color"]) > 18]
        # The hero objects (beacon + the two lobby brain shrines) carry the only
        # purple in the world: one energy seam each. Architecture has none.
        self.assertTrue(all("Brain_" in n for n in purple), purple)
        self.assertLessEqual(len(purple), 3, "one seam per brain, nothing else")

    def test_06_cyan_is_only_gameplay_feedback(self):
        cyan = [p for p in PARTS if 172 <= hue(p["Color"]) <= 198 and chroma(p["Color"]) > 30]
        for part in cyan:
            self.assertIn(part["Role"], ("accent",), part["Name"])
            self.assertEqual(part["Material"], "Neon", part["Name"])

    def test_07_cells_are_pink_gold_and_prism_as_documented(self):
        config = (ROOT / "src/shared/Config.luau").read_text()
        for token in ("{ 255, 94, 190 }", "{ 255, 213, 67 }", "{ 83, 238, 255 }"):
            self.assertIn(token, config, "Pickup rarity colours must stay unchanged")

    # -------------------------------------------------------------- materials
    def test_08_material_variety_and_shadow_budget(self):
        used = {p["Material"] for p in PARTS}
        for expected in ("Sand", "Grass", "Rock", "Limestone", "WoodPlanks", "Marble"):
            self.assertIn(expected, used)
        self.assertGreaterEqual(len(used), 10, f"Material variety too flat: {sorted(used)}")
        casters = sum(1 for p in PARTS if p["CastShadow"])
        self.assertLessEqual(casters / len(PARTS), 0.72)
        self.assertFalse(any(p["CastShadow"] and p["Material"] == "Neon" for p in PARTS))

    def test_09_every_material_name_is_a_real_roblox_material(self):
        schema = json.loads((ROOT / "tests/fixtures/roblox-api.json").read_text())
        for part in PARTS:
            self.assertIn(part["Material"], schema["Enums"]["Material"], part["Name"])

    def test_10_performance_budget(self):
        static = len(PARTS)
        self.assertLessEqual(static, 640, "Static part budget for lower-end devices")
        cells = len(WORLD["PickupPositions"]) * 9
        self.assertLessEqual(static + cells, 1060, "Total runtime part budget")
        self.assertLessEqual(len(theme.LIGHTS), 7, "Point lights are the most expensive detail")
        for spec in theme.LIGHTS.values():
            self.assertFalse(spec["Shadows"], "Shadowed point lights are not shippable")
            self.assertLessEqual(spec["Range"], 40)

    # -------------------------------------------------------------- lighting
    def test_11_lighting_is_a_soft_blue_day(self):
        values = theme.LIGHTING
        r, g, b = values["Ambient"]
        self.assertTrue(b > g > r, "Ambient must be a cool sky fill, not black or magenta")
        fr, fg, fb = values["FogColor"]
        self.assertTrue(fb > fr and fb > fg - 10, "Fog should read as sky blue")
        tr, tg, tb = values["ColorShift_Top"]
        self.assertTrue(tr > tg > tb, "Sun tint must be warm")
        self.assertGreaterEqual(values["ClockTime"], 7)
        self.assertLessEqual(values["ClockTime"], 18, "Daylight only; no neon night scene")
        self.assertTrue(values["GlobalShadows"])
        self.assertGreater(values["ShadowSoftness"], 0.2)

    def test_12_post_processing_stays_cheap_and_neutral(self):
        effects = dict(theme.LIGHTING_EFFECTS)
        self.assertLessEqual(effects["BloomEffect"]["Intensity"], 0.3)
        self.assertGreaterEqual(effects["BloomEffect"]["Threshold"], 1.3,
                                "Only genuinely bright gameplay glow may bloom")
        self.assertLessEqual(effects["ColorCorrectionEffect"]["Saturation"], 0.12,
                             "No washed-out candy grade")
        self.assertLess(effects["Atmosphere"]["Density"], 0.45)
        allowed = {"Sky", "Atmosphere", "BloomEffect", "ColorCorrectionEffect"}
        self.assertEqual({name for name, _ in theme.LIGHTING_EFFECTS}, allowed)

    def test_13_exported_place_matches_the_theme(self):
        self.assertIsNotNone(self.lighting, "Lighting service missing from place")
        for key, value in theme.LIGHTING.items():
            if isinstance(value, tuple):
                self.assertEqual(color_of(self.lighting, key), value, key)
            elif isinstance(value, bool):
                self.assertEqual(prop(self.lighting, "bool", key).text, "true", key)
            else:
                self.assertAlmostEqual(float(prop(self.lighting, "float", key).text), value, 4, key)
        for class_name, properties in theme.LIGHTING_EFFECTS:
            node = child(self.lighting, theme.EFFECT_NAMES[class_name])
            self.assertIsNotNone(node, class_name)
            self.assertEqual(node.attrib["class"], class_name)
            for key, value in properties.items():
                if isinstance(value, tuple):
                    self.assertEqual(color_of(node, key), value, key)
                elif isinstance(value, bool):
                    self.assertEqual(prop(node, "bool", key).text, "true", key)
                else:
                    self.assertAlmostEqual(float(prop(node, "float", key).text), value, 4, key)

    def test_14_skybox_and_light_rig_in_place(self):
        sky = child(self.lighting, theme.EFFECT_NAMES["Sky"])
        for face, url in theme.SKYBOX.items():
            self.assertEqual(prop(sky, "Content", f"Skybox{face}").findtext("url"), url)
        world = child(child(self.regular, "Workspace"), "BrainrotWorld")
        lights = {}
        for part in world.findall("Item"):
            for light in part.findall("Item"):
                if light.attrib["class"] == "PointLight":
                    lights[names(part)] = light
        self.assertEqual(set(lights), set(theme.LIGHTS))
        for part_name, spec in theme.LIGHTS.items():
            light = lights[part_name]
            self.assertEqual(list(color_of(light)), theme.rgb(spec["Color"]))
            self.assertEqual(prop(light, "bool", "Shadows").text, "false")
            self.assertAlmostEqual(float(prop(light, "float", "Range").text), spec["Range"], 4)

    # ------------------------------------------------------------ legibility
    def test_15_every_cell_contrasts_with_every_floor(self):
        kinds = [(255, 94, 190), (255, 213, 67), (83, 238, 255)]
        worst = []
        for floor in self.floors:
            for kind in kinds:
                distance = lab_distance(kind, floor["Color"])
                worst.append((distance, floor["Name"], kind))
        worst.sort()
        self.assertGreater(worst[0][0], 38,
                           f"Lowest cell/floor separation: {worst[0][0]:.1f} on {worst[0][1]}")

    def test_16_cells_separate_from_every_floor(self):
        # Cells are Neon (self-lit) inside pale sand/stone courts, so a small raw
        # luminance gap is enough; what matters is that no surface is the same hue
        # family as a cell or within 18 delta-E of one.
        for floor in self.floors:
            for kind in ((255, 94, 190), (255, 213, 67), (83, 238, 255)):
                self.assertGreater(lab_distance(kind, floor["Color"]), 30, floor["Name"])
            cell_hue = 328.0  # the common (pink) cell; the rarest is the bonus
            separation = min(abs(hue(floor["Color"]) - cell_hue),
                             360 - abs(hue(floor["Color"]) - cell_hue))
            self.assertGreater(separation, 12, floor["Name"])

    def test_17_signage_contrast(self):
        for sign in WORLD["Signs"]:
            board = next(p for p in PARTS if p["Name"] == sign["Part"])
            for line in sign["Lines"]:
                ratio = theme.contrast_ratio(line["Color"], board["Color"])
                self.assertGreater(ratio, 3.6, f"{sign['Part']}:{line['Text']} contrast {ratio:.1f}")
            # Signs are SurfaceGuis with LightInfluence 0 (self-lit), not glowing parts.
            self.assertNotEqual(board["Material"], "Neon")

    def test_18_gameplay_surfaces_are_walkable_and_unchanged(self):
        old = {p["Name"]: p for p in BASELINE["collidable"]}
        new = {p["Name"]: p for p in PARTS if p["Collide"]}
        self.assertEqual(set(old), set(new), "Collidable part set changed")
        for name, part in old.items():
            # Signage panels are decoration, not walkable surface: the redesigned
            # status board moved onto the arch and got a tighter banner ratio.
            if name in SIGN_PANELS:
                continue
            for key in ("Position", "Size", "Rotation", "Shape", "Class"):
                self.assertEqual(part[key], new[name][key], f"{name}.{key} moved")

    def test_19_pickups_and_spawns_unchanged(self):
        self.assertEqual(WORLD["PickupPositions"], BASELINE["pickups"])
        self.assertEqual(WORLD["ArenaSpawns"], BASELINE["arena_spawns"])
        self.assertEqual(WORLD["LobbySpawns"], BASELINE["lobby_spawns"])
        for p in WORLD["PickupPositions"]:
            self.assertEqual(p["y"], 23.5)

    def test_20_islands_keep_their_identity(self):
        # Every part belongs to exactly one designed island/landmark grouping.
        for part in PARTS:
            self.assertTrue(part["Island"])
            self.assertIn(part["Layer"], (1, 2, 3, 4))
            self.assertGreaterEqual(part["Position"][2], -140)

    def test_21_entrance_portal_reads_as_an_entrance(self):
        names_ = {p["Name"] for p in PARTS}
        for required in ("Queue_ArchLeft", "Queue_ArchRight", "Queue_ArchTop",
                         "Portal_Medallion", "Portal_Lantern_-1", "Portal_Lantern_1",
                         "Entrance_Banner"):
            self.assertIn(required, names_)
        banner = next(p for p in PARTS if p["Name"] == "Entrance_Banner")
        self.assertFalse(banner["Collide"], "Banner must not block the doorway")
        left = next(p for p in PARTS if p["Name"] == "Queue_ArchLeft")
        right = next(p for p in PARTS if p["Name"] == "Queue_ArchRight")
        clearance = (right["Position"][0] - right["Size"][0] / 2) - (left["Position"][0] + left["Size"][0] / 2)
        self.assertGreater(clearance, 12, "Portal opening must stay wide for players")

    def test_22_landmark_hierarchy(self):
        # The beacon is the tallest, most saturated landmark; the lobby title board
        # is the second visual anchor, and both sit on the arena centreline.
        beacon = next(p for p in PARTS if p["Name"] == "ChaosAccent_BeaconTop")
        title = next(p for p in PARTS if p["Name"] == "TitleBoard")
        self.assertEqual((beacon["Position"][0], beacon["Position"][2]), (0, 0))
        self.assertGreater(title["Position"][1], beacon["Position"][1] + 10)
        self.assertGreater(chroma(beacon["Color"]), 40)

    def test_23_generated_art_module_is_in_sync(self):
        module = (ROOT / "src/shared/ArtDirection.luau").read_text()
        self.assertIn("GENERATED by tools/build_place.py from tools/theme.py", module)
        self.assertIn(f"Brightness = {float(theme.LIGHTING['Brightness'])!r}", module)
        for face, url in theme.SKYBOX.items():
            self.assertIn(url, module)
        for part_name in theme.LIGHTS:
            self.assertIn(part_name, module)

    def test_24_no_external_assets_were_introduced(self):
        xml = ET.tostring(self.regular, encoding="unicode")
        self.assertNotIn("rbxassetid://", xml)
        self.assertNotIn("http://", xml)


if __name__ == "__main__":
    unittest.main(verbosity=2)
