#!/usr/bin/env python3
"""Build two Studio-openable XML places using only the Python standard library.
The .rbxlx embeds every script and a baked editable map. Rojo is optional.
"""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
import xml.etree.ElementTree as ET
from world import make_world
import creatures
import theme

ROOT = Path(__file__).resolve().parents[1]
# Roblox material tokens: take them from the pinned API fixture so the export can
# never drift from the engine enum.
SCHEMA = json.loads((ROOT / "tests/fixtures/roblox-api.json").read_text())
MATERIAL = SCHEMA["Enums"]["Material"]
SHAPE = {"Ball": 0, "Block": 1, "Cylinder": 2}
_counter = 0


def item(parent, cls, name):
    global _counter
    _counter += 1
    obj = ET.SubElement(parent, "Item", {"class": cls, "referent": f"RBX{_counter:06}"})
    ET.SubElement(obj, "Properties")
    prop(obj, "string", "Name", name)
    return obj


def prop(obj, tag, name, value):
    element = ET.SubElement(obj.find("Properties"), tag, {"name": name})
    if tag in ("Vector3", "Vector2", "Color3"):
        keys = {"Vector3": "XYZ", "Vector2": "XY", "Color3": "RGB"}[tag]
        for key, component in zip(keys, value):
            ET.SubElement(element, key).text = f"{component:.8g}"
    elif tag == "CoordinateFrame":
        for key, component in zip(("X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"), value):
            ET.SubElement(element, key).text = f"{component:.9g}"
    elif tag == "bool":
        element.text = "true" if value else "false"
    elif tag == "Content":
        ET.SubElement(element, "url").text = str(value)
    else:
        element.text = str(value)
    return element


def cframe(position, rotation=(0, 0, 0)):
    x, y, z = (math.radians(v) for v in rotation)
    cx, cy, cz, sx, sy, sz = math.cos(x), math.cos(y), math.cos(z), math.sin(x), math.sin(y), math.sin(z)
    # CFrame.Angles / fromEulerAnglesXYZ: Rx * Ry * Rz.
    return list(position) + [cy*cz, -cy*sz, sy,
                            cx*sz+sx*sy*cz, cx*cz-sx*sy*sz, -sx*cy,
                            sx*sz-cx*sy*cz, sx*cz+cx*sy*sz, cx*cy]


def look_at(eye, target):
    def unit(v):
        mag = math.sqrt(sum(x*x for x in v))
        return [x/mag for x in v]
    def cross(a, b):
        return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]
    back = unit([eye[i]-target[i] for i in range(3)])
    right = unit(cross([0, 1, 0], back))
    up = cross(back, right)
    return list(eye) + [right[0], up[0], back[0], right[1], up[1], back[1], right[2], up[2], back[2]]


def color(obj, name, rgb):
    prop(obj, "Color3", name, [c/255 for c in rgb])


def world_item(parent, spec):
    obj = item(parent, spec["Class"], spec["Name"])
    prop(obj, "Vector3", "size", spec["Size"])
    prop(obj, "CoordinateFrame", "CFrame", cframe(spec["Position"], spec["Rotation"]))
    color(obj, "Color", spec["Color"])
    prop(obj, "token", "Material", MATERIAL[spec["Material"]])
    prop(obj, "bool", "Anchored", True)
    prop(obj, "bool", "CanCollide", spec["Collide"])
    prop(obj, "bool", "CanTouch", spec["Class"] == "SpawnLocation")
    prop(obj, "bool", "CanQuery", spec["Collide"])
    prop(obj, "bool", "CastShadow", spec["CastShadow"])
    prop(obj, "float", "Transparency", spec["Transparency"])
    prop(obj, "token", "TopSurface", 0)
    prop(obj, "token", "BottomSurface", 0)
    if spec["Class"] in ("Part", "SpawnLocation"):
        prop(obj, "token", "shape", SHAPE[spec["Shape"]])
    if spec["Class"] == "SpawnLocation":
        prop(obj, "bool", "Neutral", True)
        prop(obj, "bool", "Enabled", True)
        prop(obj, "bool", "AllowTeamChangeOnTouch", False)
        prop(obj, "int", "Duration", 0)
    light_spec = theme.LIGHTS.get(spec["Name"])
    if light_spec:
        light = item(obj, "PointLight", light_spec["Name"])
        color(light, "Color", theme.rgb(light_spec["Color"]))
        prop(light, "float", "Brightness", light_spec["Brightness"])
        prop(light, "float", "Range", light_spec["Range"])
        prop(light, "bool", "Shadows", light_spec["Shadows"])
    return obj


def world_sign(part_obj, spec):
    gui = item(part_obj, "SurfaceGui", "Sign")
    prop(gui, "token", "Face", 5)
    size = part_obj.find("Properties/Vector3[@name='size']")
    width, height = float(size.findtext("X")), float(size.findtext("Y"))
    prop(gui, "Vector2", "CanvasSize", [1200, max(100, math.floor(1200 * height / width))])
    prop(gui, "float", "LightInfluence", 0)
    prop(gui, "bool", "AlwaysOnTop", False)
    total = sum(line["Fraction"] for line in spec["Lines"])
    y = 0.04
    for index, line in enumerate(spec["Lines"]):
        label = item(gui, "TextLabel", f"Line{index+1}")
        height = .92 * line["Fraction"] / total
        # UDim2 has dedicated sub-elements, not a Vector4.
        for name, value in (("Position", (.04, 0, y, 0)), ("Size", (.92, 0, height, 0))):
            element = ET.SubElement(label.find("Properties"), "UDim2", {"name": name})
            for key, component in zip(("XS", "XO", "YS", "YO"), value):
                ET.SubElement(element, key).text = str(component)
        prop(label, "float", "BackgroundTransparency", 1)
        prop(label, "string", "Text", line["Text"])
        color(label, "TextColor3", line["Color"])
        prop(label, "bool", "TextScaled", True)
        prop(label, "bool", "TextWrapped", True)
        prop(label, "token", "Font", SCHEMA["Enums"]["Font"][line.get("Font", "GothamBold")])
        prop(label, "float", "TextStrokeTransparency", .8)
        y += height


def lua(value):
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, (int, float)):
        return str(round(value, 5))
    if isinstance(value, list):
        return "{" + ", ".join(lua(v) for v in value) + "}"
    if isinstance(value, dict):
        import re
        reserved = set("and break do else elseif end false for function if in local nil not or repeat return then true until while".split())
        def key(k):
            return k if isinstance(k, str) and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", k) and k not in reserved else f"[{lua(k)}]"
        return "{" + ", ".join(f"{key(k)} = {lua(v)}" for k, v in value.items()) + "}"
    raise TypeError(type(value))


# Only these fields are needed by WorldService at runtime. Art-direction metadata
# (Role/Layer/Island/MaterialToken) stays in tools/world.py where the exporter and
# the verification suite read it, so the shipped module stays small.
RUNTIME_PART_KEYS = ("Name", "Position", "Size", "Color", "Rotation", "Material",
                     "CastShadow", "Collide", "Shape", "Class", "Transparency")


def runtime_world(world):
    trimmed = dict(world)
    trimmed["Parts"] = [{key: part[key] for key in RUNTIME_PART_KEYS} for part in world["Parts"]]
    trimmed["Signs"] = [
        {"Part": sign["Part"], "Face": sign["Face"], "Lines": sign["Lines"]}
        for sign in world["Signs"]
    ]
    return trimmed


def generate_world_module(world):
    world = runtime_world(world)
    lines = ["--!nocheck", "-- GENERATED by tools/build_place.py from tools/world.py. Do not edit by hand.", "return {"]
    for key, value in world.items():
        if isinstance(value, list):
            lines.append(f"\t{key} = {{")
            lines.extend("\t\t" + lua(v) + "," for v in value)
            lines.append("\t},")
        else:
            lines.append(f"\t{key} = {lua(value)},")
    lines.append("}\n")
    path = ROOT / "src/server/WorldData.luau"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8")


def generate_art_module():
    """Emit src/shared/ArtDirection.luau from tools/theme.py (runtime lighting rig)."""
    def rgb(values):
        return "{" + ", ".join(str(c) for c in values) + "}"
    lines = [
        "--!nocheck",
        "-- GENERATED by tools/build_place.py from tools/theme.py. Do not edit by hand.",
        "-- Runtime mirror of the art direction so Rojo builds and the baked place match.",
        "return {",
        "\tLighting = {",
    ]
    for key, value in theme.LIGHTING.items():
        rendered = rgb(value) if isinstance(value, tuple) else (
            "true" if value is True else "false" if value is False else repr(float(value)))
        lines.append(f"\t\t{key} = {rendered},")
    lines.append("\t},")
    lines.append("\tEffects = {")
    for class_name, properties in theme.LIGHTING_EFFECTS:
        lines.append(f"\t\t{class_name} = {{")
        lines.append(f"\t\t\tName = {json.dumps(theme.EFFECT_NAMES[class_name])},")
        lines.append("\t\t\tProperties = {")
        for key, value in properties.items():
            rendered = rgb(value) if isinstance(value, tuple) else (
                "true" if value is True else "false" if value is False else repr(float(value)))
            lines.append(f"\t\t\t\t{key} = {rendered},")
        lines.append("\t\t\t},")
        lines.append("\t\t},")
    lines.append("\t},")
    lines.append("\tSkybox = {")
    for face, url in theme.SKYBOX.items():
        lines.append(f"\t\t{face} = {json.dumps(url)},")
    lines.append("\t},")
    lines.append("\tLights = {")
    for part_name, spec in theme.LIGHTS.items():
        lines.append(f"\t\t[\"{part_name}\"] = {{")
        lines.append(f"\t\t\tName = {json.dumps(spec['Name'])},")
        lines.append(f"\t\t\tColor = {rgb(theme.rgb(spec['Color']))},")
        lines.append(f"\t\t\tBrightness = {repr(float(spec['Brightness']))},")
        lines.append(f"\t\t\tRange = {repr(float(spec['Range']))},")
        lines.append(f"\t\t\tShadows = {'true' if spec['Shadows'] else 'false'},")
        lines.append("\t\t},")
    lines.append("\t},")
    lines.append(f"\tEventAccent = {rgb(theme.EVENT_ACCENT)},")
    lines.append(f"\tEventLight = {rgb(theme.EVENT_LIGHT)},")
    lines.append("\tEventRest = {")
    for name, color_name in theme.EVENT_REST.items():
        lines.append(f"\t\t{name} = {rgb(theme.rgb(color_name))},")
    lines.append("\t},")
    lines.append("}")
    path = ROOT / "src/shared/ArtDirection.luau"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def generate_creature_module():
    """Emit src/client/CreatureData.luau from tools/creatures.py (collectible cast)."""
    problems = creatures.validate()
    if problems:
        raise SystemExit("Creature specification invalid:\n" + "\n".join(problems))
    lines = [
        "--!nocheck",
        "-- GENERATED by tools/build_place.py from tools/creatures.py. Do not edit by hand.",
        "-- Original collectible cast: shaped by rarity, coloured by the server's value.",
        "return {",
        "\tFixed = {",
    ]
    for role, values in creatures.FIXED_COLORS.items():
        lines.append(f"\t\t{role} = {{{values[0]}, {values[1]}, {values[2]}}},")
    lines.append("\t},")
    lines.append("\tFamily = {")
    for value in (1, 5, 10):
        names = creatures.FAMILY[value]
        rendered = ", ".join(json.dumps(name) for name in names)
        lines.append(f"\t\t[{value}] = {{{rendered}}},")
    lines.append("\t},")
    lines.append("\tMark = {")
    for value in (1, 5, 10):
        lines.append(f"\t\t[{value}] = {json.dumps(creatures.MARK[value])},")
    lines.append("\t},")
    halo = creatures.HOVER_RING
    lines.append("\tHalo = {")
    lines.append(f"\t\tName = {json.dumps(halo['Name'])},")
    lines.append(f"\t\tSize = {lua(halo['Size'])},")
    lines.append(f"\t\tShape = {json.dumps(halo['Shape'])},")
    lines.append(f"\t\tMaterial = {json.dumps(halo['Material'])},")
    lines.append("\t},")
    lines.append("\tCreatures = {")
    for name, spec in creatures.CREATURES.items():
        lines.append(f"\t\t{name} = {{")
        lines.append(f"\t\t\tLabel = {json.dumps(spec['Label'])},")
        lines.append(f"\t\t\tBlurb = {json.dumps(spec['Blurb'])},")
        lines.append("\t\t\tParts = {")
        for part in spec["Parts"]:
            fields = (
                f"Name = {json.dumps(part['Name'])}, "
                f"Size = {lua(part['Size'])}, "
                f"Offset = {lua(part['Offset'])}, "
                f"Rotation = {lua(part['Rotation'])}, "
                f"Shape = {json.dumps(part['Shape'])}, "
                f"Role = {json.dumps(part['Role'])}, "
                f"Material = {json.dumps(part['Material'])}"
            )
            lines.append(f"\t\t\t\t{{ {fields} }},")
        lines.append("\t\t\t},")
        lines.append("\t\t},")
    lines.append("\t},")
    lines.append("}")
    path = ROOT / "src/client/CreatureData.luau"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def embed_sources(parent, path, fast):
    for child in sorted(path.iterdir()):
        if child.is_dir():
            embed_sources(item(parent, "Folder", child.name), child, fast)
        elif child.suffix == ".luau":
            name = child.name.removesuffix(".luau")
            cls = "ModuleScript"
            if name.endswith(".server"):
                cls, name = "Script", name.removesuffix(".server")
            elif name.endswith(".client"):
                cls, name = "LocalScript", name.removesuffix(".client")
            obj = item(parent, cls, name)
            source = child.read_text(encoding="utf-8")
            if fast and child.name == "Config.luau":
                assert source.count("StudioFastMode = false,") == 1
                source = source.replace("StudioFastMode = false,", "StudioFastMode = true,")
            prop(obj, "ProtectedString", "Source", source)
            if cls != "ModuleScript":
                prop(obj, "bool", "Disabled", False)


def build(world, fast=False):
    global _counter
    _counter = 0
    root = ET.Element("roblox", {"version": "4"})
    ET.SubElement(root, "External").text = "null"
    ET.SubElement(root, "External").text = "nil"
    workspace = item(root, "Workspace", "Workspace")
    prop(workspace, "float", "Gravity", 196.2)
    prop(workspace, "float", "FallenPartsDestroyHeight", -160)
    prop(workspace, "bool", "StreamingEnabled", False)
    camera = item(workspace, "Camera", "Camera")
    prop(camera, "CoordinateFrame", "CFrame", look_at(list(theme.CAMERA_EYE), list(theme.CAMERA_FOCUS)))
    prop(camera, "CoordinateFrame", "Focus", cframe(list(theme.CAMERA_FOCUS)))
    prop(camera, "float", "FieldOfView", 70)
    prop(workspace, "Ref", "CurrentCamera", camera.attrib["referent"])
    world_model = item(workspace, "Model", "BrainrotWorld")
    map_parts = {spec["Name"]: world_item(world_model, spec) for spec in world["Parts"]}
    for sign in world["Signs"]:
        # A thin, non-colliding front layer carries the SurfaceGui, so the sign
        # text sits slightly proud of the panel and can never z-fight it.
        board = next(spec for spec in world["Parts"] if spec["Name"] == sign["Part"])
        yaw = math.radians(board["Rotation"][1])
        offset = [board["Position"][0] - math.sin(yaw) * (board["Size"][2] / 2 + .01),
                  board["Position"][1],
                  board["Position"][2] - math.cos(yaw) * (board["Size"][2] / 2 + .01)]
        face = dict(board, Name=sign["Part"] + "_Sign", Position=offset,
                    Size=[board["Size"][0], board["Size"][1], .02], Collide=False,
                    Material="SmoothPlastic", CastShadow=False)
        world_sign(world_item(world_model, face), sign)
    replicated = item(root, "ReplicatedStorage", "ReplicatedStorage")
    embed_sources(item(replicated, "Folder", "BrainrotShared"), ROOT / "src/shared", fast)
    servers = item(root, "ServerScriptService", "ServerScriptService")
    embed_sources(item(servers, "Folder", "BrainrotServer"), ROOT / "src/server", fast)
    starter = item(root, "StarterPlayer", "StarterPlayer")
    for name, value in (("CharacterWalkSpeed", 22), ("CharacterJumpPower", 50), ("CameraMaxZoomDistance", 80), ("CameraMinZoomDistance", 8)):
        prop(starter, "float", name, value)
    prop(starter, "bool", "CharacterUseJumpPower", True)
    scripts = item(starter, "StarterPlayerScripts", "StarterPlayerScripts")
    embed_sources(item(scripts, "Folder", "BrainrotClient"), ROOT / "src/client", fast)
    lighting = item(root, "Lighting", "Lighting")
    for key, value in theme.LIGHTING.items():
        if isinstance(value, (tuple, list)):
            color(lighting, key, value)
        elif isinstance(value, bool):
            prop(lighting, "bool", key, value)
        else:
            prop(lighting, "float", key, value)
    sky_props = dict(theme.LIGHTING_EFFECTS[0][1])
    sky = item(lighting, "Sky", theme.EFFECT_NAMES["Sky"])
    for face in ("Bk", "Dn", "Ft", "Lf", "Rt", "Up"):
        prop(sky, "Content", f"Skybox{face}", theme.SKYBOX[face])
    for key in ("CelestialBodiesShown",):
        prop(sky, "bool", key, sky_props[key])
    for key in ("SunAngularSize", "MoonAngularSize"):
        prop(sky, "float", key, sky_props[key])
    prop(sky, "float", "StarCount", sky_props["StarCount"])
    for class_name, properties in theme.LIGHTING_EFFECTS[1:]:
        effect = item(lighting, class_name, theme.EFFECT_NAMES[class_name])
        for key, value in properties.items():
            if isinstance(value, (tuple, list)):
                color(effect, key, value)
            elif isinstance(value, bool):
                prop(effect, "bool", key, value)
            elif isinstance(value, float):
                prop(effect, "float", key, value)
            else:
                prop(effect, "float", key, float(value))
    players = item(root, "Players", "Players")
    prop(players, "float", "RespawnTime", 2)
    prop(players, "bool", "CharacterAutoLoads", True)
    sound = item(root, "SoundService", "SoundService")
    prop(sound, "bool", "RespectFilteringEnabled", True)
    ET.indent(root, space="  ")
    name = "BrainrotArena-QuickTest.rbxlx" if fast else "BrainrotArena.rbxlx"
    output = ROOT / "places" / name
    output.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(root).write(output, encoding="utf-8", xml_declaration=True)
    print(f"Built {output.relative_to(ROOT)} ({output.stat().st_size:,} bytes)")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--world-only", action="store_true", help="Only regenerate the runtime world module")
    args = parser.parse_args()
    world = make_world()
    generate_world_module(world)
    generate_art_module()
    generate_creature_module()
    if not args.world_only:
        build(world)
        build(world, fast=True)
    print(f"World: {len(world['Parts'])} static parts, {len(world['PickupPositions'])} pickup slots, 8 arena spawns")


if __name__ == "__main__":
    main()
