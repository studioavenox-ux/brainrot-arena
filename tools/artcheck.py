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

import creatures
import theme
from world import make_world
import ui

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
        # Phase 5 spends 66 parts on event geometry (three rafts + four vanishing
        # paths, all non-colliding) to reach 906. The ceiling moves with it, and the
        # per-visible-cell budget below is what actually governs a phone.
        self.assertLessEqual(static, 920, "Static part budget for lower-end devices")
        event = [p for p in PARTS if p["Name"].startswith(("EventRaft", "EventPath"))]
        self.assertLessEqual(len(event), 90, "Event geometry must stay cheap")
        self.assertGreaterEqual(len(event), 60, "Event geometry must actually exist")
        for p in event:
            self.assertFalse(p["Collide"], f"{p['Name']} must not collide at rest")
        # Characters are only built for cells that are actually on screen, so the
        # mobile budget is paid per *visible* cell: 16 (the ceiling of the part
        # table) + the shared pivot + hover ring + rarity marks = 20.
        cells = creatures.VISIBLE_CELL_PARTS
        self.assertLessEqual(cells, 20, "Per-cell render budget for a collection game")
        # A whole round is never resident: the client builds a model only inside
        # VIEW_RANGE of the camera, so this is the streaming ceiling, not 48 models.
        self.assertLessEqual(48 * cells, 960, "All-cell ceiling must still stream")
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
            if floor["Name"].startswith("Sea_"):
                # The ocean is 15 studs below the lowest pickup and never shares a
                # frame edge with a cell; it is the one surface allowed to sit in the
                # same cool hue family, because islands need a horizon.
                continue
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
        # Phase 2 adds structures, so the collidable set may only *grow*. Nothing
        # that existed before may move, shrink, rotate or stop colliding.
        self.assertTrue(set(old) <= set(new), "An original walkable part was removed or stopped colliding")
        self.assertGreater(len(new) - len(old), 0, "Phase 2 must add structures, not only decoration")
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

    def test_24_generated_creature_module_is_in_sync(self):
        module = (ROOT / "src/client/CreatureData.luau").read_text()
        self.assertIn("GENERATED by tools/build_place.py from tools/creatures.py", module)
        for name, spec in creatures.CREATURES.items():
            self.assertIn(f"\t\t{name} = {{", module)
            self.assertIn(spec["Label"], module)
            for part in spec["Parts"]:
                self.assertIn(
                    f"Size = {{{part['Size'][0]}, {part['Size'][1]}, {part['Size'][2]}}}", module)
        for value, family in creatures.FAMILY.items():
            rendered = ", ".join(f'"{name}"' for name in family)
            self.assertIn(f"\t\t[{value}] = {{{rendered}}},", module)

    def test_25_every_creature_is_within_the_cell_part_budget(self):
        self.assertEqual(creatures.validate(), [])
        for value in (1, 5, 10):
            self.assertLessEqual(creatures.total_cell_parts(value), creatures.PART_BUDGET)

    def test_26_creature_variants_differ_in_silhouette_not_just_colour(self):
        # No two of the six may share a coarse shape signature: they have to be
        # distinguishable as *characters*, not as recolours of each other.
        seen = {}
        for name in creatures.CREATURES:
            signature = creatures.silhouette(name)
            self.assertNotIn(signature, seen, f"{name} looks like {seen.get(signature)}")
            seen[signature] = name
        for value, family in creatures.FAMILY.items():
            self.assertNotEqual(creatures.silhouette(family[0]), creatures.silhouette(family[1]),
                                f"rarity {value} variants look alike")

    def test_27_creature_cast_uses_original_primitives_only(self):
        # Original cast: six characters, primitive parts only, no meshes or asset ids,
        # and neutral inks for faces so no new saturated hue enters the palette.
        self.assertEqual(len(creatures.CREATURES), 6)
        for name, spec in creatures.CREATURES.items():
            parts = creatures.parts_of(name)
            self.assertGreaterEqual(len(parts), 9, name)
            self.assertLessEqual(len(parts), 14, name)
            self.assertTrue(spec["Blurb"], name)
            self.assertTrue(spec["Lore"], name)
            for part in parts:
                self.assertIn(part["Kind"], ("box", "ball", "cyl"))
                self.assertIn(part["Role"], creatures.ROLES)
                if part["Role"] in creatures.FIXED_COLORS:
                    color = creatures.FIXED_COLORS[part["Role"]]
                    self.assertLess(chroma(color), 22, f"{name}.{part['Name']} carries hue")

    def test_27b_every_character_has_a_face_and_a_name_card_height(self):
        # Expressive faces are a delivery requirement, so they are gated: two eyes
        # plus a mouth/beak, and the floating label must clear the tallest part.
        for name in creatures.CREATURES:
            parts = creatures.parts_of(name)
            eyes = [p for p in parts if p["Role"] == "ink" and p["Size"][1] <= .30]
            self.assertGreaterEqual(len(eyes), 2, f"{name} has no eyes")
            # +Z is the face direction: eyes must sit on the front half of the body.
            self.assertGreater(min(p["At"][2] for p in eyes), 0,
                               f"{name}: eyes must face the camera (+Z)")
            self.assertGreater(creatures.label_height(name), creatures.top_of(name) + .2,
                               f"{name}: label would clip the model")
            self.assertLess(creatures.top_of(name) - creatures.bottom_of(name), 1.8,
                            f"{name}: taller than a cell, would dominate the arena")

    def test_28_rarity_families_are_stable_and_deterministic(self):
        # The variant is chosen from the slot id on the client only: the same slot
        # must always show the same critter, and every slot must be covered.
        for value in (1, 5, 10):
            seen = {creatures.creature_for(slot, value) for slot in range(48)}
            self.assertEqual(seen, set(creatures.FAMILY[value]))
        for slot in range(48):
            self.assertEqual(creatures.creature_for(slot, 1), creatures.creature_for(slot, 1))
        # Server-side data is untouched: rarity weights and values are unchanged.
        config = (ROOT / "src/shared/Config.luau").read_text()
        self.assertIn("Weight = 78", config)
        self.assertIn("Weight = 18", config)
        self.assertIn("Weight = 4", config)

    def test_29_hover_ring_is_thin_and_flat(self):
        ring = creatures.HOVER_RING
        self.assertEqual(ring["Kind"], "cyl")
        # Roblox cylinders run along local X, so X is the thickness axis.
        self.assertLess(ring["Size"][0], .2)
        self.assertAlmostEqual(ring["Size"][1], ring["Size"][2], 3)
        self.assertEqual(ring["Rotation"], [0, 0, 90])

    # ------------------------------------------------------------------ #
    # The interface is designed under the same gate as the environment.
    # ------------------------------------------------------------------ #
    def test_31_hud_design_system_passes_its_own_contrast_and_hue_rules(self):
        self.assertEqual(ui.validate(), [])

    def test_32_generated_theme_matches_the_design_source(self):
        # The client theme is generated data, never hand-edited: if someone edits it
        # by hand, this fails and they have to change tools/ui.py instead.
        theme = (ROOT / "src/client/Theme.luau").read_text(encoding="utf-8")
        self.assertIn("GENERATED by tools/build_place.py", theme)
        for name, rgb in ui.COLORS.items():
            self.assertIn(f"{name} = Color3.fromRGB({rgb[0]}, {rgb[1]}, {rgb[2]}),", theme)
        for name, size in ui.TYPE.items():
            self.assertIn(f"{name} = {size},", theme)
        for name, text in ui.COPY.items():
            self.assertIn(f'{name} = "{text}",', theme)

    def test_33_hud_uses_only_the_design_system(self):
        # No magic colours or ad-hoc text sizes in the HUD panels: everything routes
        # through Theme/Kit, so the design system cannot drift.
        for name in ("Hud.luau", "Panels.luau"):
            source = (ROOT / "src/client" / name).read_text(encoding="utf-8")
            self.assertNotIn("Color3.fromRGB", source, f"{name} hardcodes a colour")
            self.assertNotIn("Color3.new", source, f"{name} hardcodes a colour")
            self.assertNotIn("rbxassetid://", source, f"{name} uses an uploaded asset")
            # TextSize must come from the scale (or an inline expression on it).
            for line in source.splitlines():
                stripped = line.strip()
                if stripped.startswith("--"):
                    continue
                self.assertNotIn("TextSize = 2", stripped, f"{name}: ad-hoc TextSize in {stripped}")

    def test_34_every_hud_button_is_wired(self):
        # A button is only allowed if it is created through Kit.button, which refuses
        # to build one without an onClick handler.
        for name in ("Hud.luau", "Panels.luau"):
            source = (ROOT / "src/client" / name).read_text(encoding="utf-8")
            self.assertNotIn('Instance.new("TextButton")', source, f"{name} builds a raw button")
            self.assertNotIn('create("TextButton"', source)
        kit = (ROOT / "src/client/Kit.luau").read_text(encoding="utf-8")
        self.assertIn('assert(type(onClick) == "function"', kit)

    def test_35_no_external_assets_were_introduced(self):
        xml = ET.tostring(self.regular, encoding="unicode")
        self.assertNotIn("rbxassetid://", xml)
        self.assertNotIn("http://", xml)


if __name__ == "__main__":
    unittest.main(verbosity=2)
