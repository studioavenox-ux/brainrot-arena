#!/usr/bin/env python3
"""Structural/API/geometry checks. This is not a substitute for loading in Roblox Studio."""
from __future__ import annotations
import json
import math
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET
from world import make_world
from build_place import cframe

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = json.loads((ROOT / "tests/fixtures/roblox-api.json").read_text())
WORLD = make_world()


def name(obj):
    return obj.findtext("Properties/string[@name='Name']")


def child(obj, child_name):
    return next((o for o in obj.findall("Item") if name(o) == child_name), None)


def resolve(root, path):
    for segment in path.split("/"):
        root = child(root, segment)
        if root is None:
            raise AssertionError(f"Missing instance path: {path}")
    return root


def definition(cls, prop):
    while cls:
        info = SCHEMA["Classes"].get(cls)
        if info is None:
            return None
        if prop in info["Properties"]:
            return info["Properties"][prop]
        cls = info["Superclass"]
    return None


def source_paths():
    for file in sorted((ROOT / "src").rglob("*.luau")):
        bits = file.relative_to(ROOT / "src").parts
        base = {"shared": "ReplicatedStorage/BrainrotShared", "server": "ServerScriptService/BrainrotServer", "client": "StarterPlayer/StarterPlayerScripts/BrainrotClient"}[bits[0]]
        filename = bits[-1].removesuffix(".luau")
        cls = "ModuleScript"
        if filename.endswith(".server"):
            filename, cls = filename.removesuffix(".server"), "Script"
        elif filename.endswith(".client"):
            filename, cls = filename.removesuffix(".client"), "LocalScript"
        yield file, "/".join([base, *bits[1:-1], filename]), cls


def supported(x, z, radius=0):
    if math.hypot(x, z) <= 52-radius:
        return True
    for sx, sz in ((73, 0), (-73, 0), (0, 73), (0, -73)):
        if math.hypot(x-sx, z-sz) <= 16-radius:
            return True
    return False


class PlaceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.regular = ET.parse(ROOT / "places/BrainrotArena.rbxlx").getroot()
        cls.quick = ET.parse(ROOT / "places/BrainrotArena-QuickTest.rbxlx").getroot()
        cls.world = resolve(cls.regular, "Workspace/BrainrotWorld")

    def test_01_valid_studio_xml_root(self):
        for root in (self.regular, self.quick):
            self.assertEqual(root.tag, "roblox")
            self.assertEqual(root.attrib["version"], "4")

    def test_02_required_services(self):
        for service in ("Workspace", "ReplicatedStorage", "ServerScriptService", "StarterPlayer", "Lighting", "Players", "SoundService"):
            self.assertEqual(resolve(self.regular, service).attrib["class"], service)

    def test_03_unique_referents(self):
        refs = [i.attrib["referent"] for i in self.regular.iter("Item")]
        self.assertEqual(len(refs), len(set(refs)))

    def test_04_references_resolve(self):
        refs = {i.attrib["referent"] for i in self.regular.iter("Item")}
        for ref in self.regular.iter("Ref"):
            self.assertIn(ref.text, refs | {"null", "nil"})

    def test_05_all_imported_properties_exist_and_can_load(self):
        # size/shape are Roblox's legacy serialized aliases; public names also CanLoad.
        aliases = {"size": "Size", "shape": "Shape"}
        for item in self.regular.iter("Item"):
            self.assertIn(item.attrib["class"], SCHEMA["Classes"])
            for prop in item.find("Properties"):
                info = definition(item.attrib["class"], aliases.get(prop.attrib["name"], prop.attrib["name"]))
                self.assertIsNotNone(info, f"Unknown property {item.attrib['class']}.{prop.attrib['name']}")
                self.assertTrue(info["CanLoad"], f"Non-loadable property {item.attrib['class']}.{prop.attrib['name']}")

    def test_06_every_source_embedded_in_correct_class(self):
        for file, path, cls in source_paths():
            obj = resolve(self.regular, path)
            self.assertEqual(obj.attrib["class"], cls)
            self.assertEqual(obj.findtext("Properties/ProtectedString[@name='Source']"), file.read_text())

    def test_07_only_two_executable_scripts(self):
        scripts = [o for o in self.regular.iter("Item") if o.attrib["class"] in ("Script", "LocalScript")]
        self.assertEqual(len(scripts), 2)
        for obj in scripts:
            self.assertEqual(obj.findtext("Properties/bool[@name='Disabled']"), "false")

    def test_08_quick_test_changes_only_studio_fast_flag(self):
        for file, path, cls in source_paths():
            expected = file.read_text()
            if file.name == "Config.luau":
                expected = expected.replace("StudioFastMode = false,", "StudioFastMode = true,")
            self.assertEqual(resolve(self.quick, path).findtext("Properties/ProtectedString[@name='Source']"), expected)

    def test_09_map_baked_and_editable(self):
        self.assertEqual(self.world.attrib["class"], "Model")
        self.assertEqual(len(self.world.findall("Item")), len(WORLD["Parts"]))
        self.assertEqual(len(WORLD["Parts"]), 358)

    def test_10_part_budget(self):
        self.assertLessEqual(len(WORLD["Parts"]), 500)
        # Six lobes, a split, a local pivot and one server root per slot.
        self.assertLessEqual(len(WORLD["Parts"]) + len(WORLD["PickupPositions"])*9, 800)

    def test_11_all_map_parts_anchored(self):
        for obj in self.world.findall("Item"):
            self.assertEqual(obj.findtext("Properties/bool[@name='Anchored']"), "true")

    def test_12_lobby_spawn_enabled_neutral_and_non_forcefield(self):
        spawn = child(self.world, "LobbySpawn")
        self.assertEqual(spawn.attrib["class"], "SpawnLocation")
        self.assertEqual(spawn.findtext("Properties/bool[@name='Neutral']"), "true")
        self.assertEqual(spawn.findtext("Properties/bool[@name='Enabled']"), "true")
        self.assertEqual(spawn.findtext("Properties/int[@name='Duration']"), "0")

    def test_13_baked_geometry_matches_runtime_generator(self):
        for part in WORLD["Parts"]:
            obj = child(self.world, part["Name"])
            actual = obj.find("Properties/CoordinateFrame[@name='CFrame']")
            expected = cframe(part["Position"], part["Rotation"])
            for element, value in zip(actual, expected):
                self.assertAlmostEqual(float(element.text), value, places=5)
            size = obj.find("Properties/Vector3[@name='size']")
            for element, value in zip(size, part["Size"]):
                self.assertAlmostEqual(float(element.text), value, places=5)

    def test_14_cylinder_axes_are_vertical(self):
        for part in WORLD["Parts"]:
            if part["Shape"] == "Cylinder":
                self.assertEqual(part["Rotation"], [0, 0, 90])

    def test_15_all_48_pickups_have_walkable_floor(self):
        self.assertEqual(len(WORLD["PickupPositions"]), 48)
        for p in WORLD["PickupPositions"]:
            self.assertTrue(supported(p["x"], p["z"], 1.5))
            self.assertEqual(p["y"], 23.5)

    def test_16_pickups_not_inside_central_sculpture(self):
        for p in WORLD["PickupPositions"]:
            self.assertGreater(math.hypot(p["x"], p["z"]), 18)

    def test_17_pickup_slots_unique_and_spaced(self):
        points = WORLD["PickupPositions"]
        self.assertEqual(len({(p["x"], p["z"]) for p in points}), len(points))
        for i, a in enumerate(points):
            for b in points[i+1:]:
                self.assertGreater(math.hypot(a["x"]-b["x"], a["z"]-b["z"]), 6)

    def test_18_arena_spawns_safe_and_spaced(self):
        spawns = WORLD["ArenaSpawns"]
        self.assertEqual(len(spawns), 8)
        for i, p in enumerate(spawns):
            self.assertTrue(supported(p[0], p[2], 3))
            self.assertEqual(p[1], 25)
            for q in spawns[i+1:]:
                self.assertGreater(math.hypot(p[0]-q[0], p[2]-q[2]), 10)

    def test_19_lobby_spawns_on_lobby_floor(self):
        for x, y, z in WORLD["LobbySpawns"]:
            self.assertLess(math.hypot(x, z-180), 34)
            self.assertEqual(y, 25)

    def test_20_four_bridges_have_no_gaps(self):
        bridges = [p for p in WORLD["Parts"] if p["Name"].startswith("Bridge_")]
        self.assertEqual(len(bridges), 4)
        for bridge in bridges:
            axis = 0 if bridge["Position"][0] else 2
            low = abs(bridge["Position"][axis])-bridge["Size"][axis]/2
            high = abs(bridge["Position"][axis])+bridge["Size"][axis]/2
            self.assertLessEqual(low, 52)
            self.assertGreaterEqual(high, 73-16)
            self.assertEqual(bridge["Position"][1]+bridge["Size"][1]/2, 21)
            self.assertTrue(bridge["Collide"])

    def test_21_signs_present_and_readable(self):
        self.assertEqual(len(WORLD["Signs"]), 4)
        for sign in WORLD["Signs"]:
            obj = resolve(self.world, sign["Part"] + "/Sign")
            self.assertEqual(obj.attrib["class"], "SurfaceGui")
            board = next(p for p in WORLD["Parts"] if p["Name"] == sign["Part"])
            canvas = obj.find("Properties/Vector2[@name='CanvasSize']")
            self.assertEqual(float(canvas.findtext("Y")), max(100, math.floor(1200 * board["Size"][1] / board["Size"][0])))
            for index, line in enumerate(sign["Lines"]):
                label = child(obj, f"Line{index+1}")
                self.assertEqual(label.findtext("Properties/string[@name='Text']"), line["Text"])
                self.assertEqual(label.findtext("Properties/token[@name='Font']"), str(SCHEMA["Enums"]["Font"]["GothamBold"]))

    def test_22_camera_points_at_world(self):
        self.assertIsNotNone(resolve(self.regular, "Workspace/Camera").find("Properties/CoordinateFrame[@name='CFrame']"))

    def test_23_no_toolbox_or_third_party_asset_ids(self):
        xml = ET.tostring(self.regular, encoding="unicode")
        self.assertNotIn("rbxassetid://", xml)
        self.assertNotIn("http://www.roblox.com/asset", xml)

    def test_24_no_dynamic_code_or_external_network(self):
        source = "\n".join(f.read_text() for f in (ROOT / "src").rglob("*.luau"))
        for forbidden in ("loadstring(", "HttpGet(", "GetAsync(", "InsertService", "MarketplaceService", "DataStoreService"):
            self.assertNotIn(forbidden, source)

    def test_25_environment_has_normal_gravity_and_void_limit(self):
        workspace = resolve(self.regular, "Workspace")
        self.assertEqual(workspace.findtext("Properties/float[@name='Gravity']"), "196.2")
        self.assertEqual(workspace.findtext("Properties/float[@name='FallenPartsDestroyHeight']"), "-160")

    def test_26_optional_rojo_project_points_to_real_sources(self):
        project = json.loads((ROOT / "default.project.json").read_text())
        def walk(tree):
            if isinstance(tree, dict):
                if "$path" in tree:
                    self.assertTrue((ROOT / tree["$path"]).exists())
                for value in tree.values():
                    walk(value)
        walk(project)
        self.assertEqual(project["tree"]["$className"], "DataModel")

    def test_27_geometry_is_finite_and_positive(self):
        for p in WORLD["Parts"]:
            for component in p["Position"] + p["Size"] + p["Rotation"]:
                self.assertTrue(math.isfinite(component))
            self.assertTrue(all(v > 0 for v in p["Size"]))

    def test_28_generated_files_below_one_megabyte_each(self):
        for place in (ROOT / "places").glob("*.rbxlx"):
            self.assertLess(place.stat().st_size, 1_000_000)


if __name__ == "__main__":
    unittest.main(verbosity=2)
