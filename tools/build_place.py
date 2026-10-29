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

ROOT = Path(__file__).resolve().parents[1]
MATERIAL = {"SmoothPlastic": 272, "Neon": 288}
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
    prop(obj, "bool", "CastShadow", spec["Material"] != "Neon")
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
    if spec["Name"] == "ChaosAccent_BeaconTop":
        light = item(obj, "PointLight", "BeaconLight")
        color(light, "Color", [255, 130, 221])
        prop(light, "float", "Brightness", 1.5)
        prop(light, "float", "Range", 28)
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
        prop(label, "token", "Font", 19)
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


def generate_world_module(world):
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
    prop(camera, "CoordinateFrame", "CFrame", look_at([126, 117, 150], [0, 21, 57]))
    prop(camera, "CoordinateFrame", "Focus", cframe([0, 21, 57]))
    prop(camera, "float", "FieldOfView", 70)
    prop(workspace, "Ref", "CurrentCamera", camera.attrib["referent"])
    world_model = item(workspace, "Model", "BrainrotWorld")
    map_parts = {spec["Name"]: world_item(world_model, spec) for spec in world["Parts"]}
    for sign in world["Signs"]:
        world_sign(map_parts[sign["Part"]], sign)
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
    prop(lighting, "float", "Brightness", 2.5)
    prop(lighting, "float", "ClockTime", 14.2)
    prop(lighting, "bool", "GlobalShadows", True)
    color(lighting, "Ambient", [135, 122, 185])
    color(lighting, "OutdoorAmbient", [153, 177, 211])
    color(lighting, "FogColor", [151, 213, 255])
    prop(lighting, "float", "FogEnd", 700)
    prop(lighting, "float", "FogStart", 160)
    prop(lighting, "float", "EnvironmentDiffuseScale", .7)
    prop(lighting, "float", "EnvironmentSpecularScale", .5)
    sky = item(lighting, "Sky", "DaySky")
    for face, suffix in (("Bk", "bk"), ("Dn", "dn"), ("Ft", "ft"), ("Lf", "lf"), ("Rt", "rt"), ("Up", "up")):
        prop(sky, "Content", f"Skybox{face}", f"rbxasset://textures/sky/sky512_{suffix}.tex")
    prop(sky, "bool", "CelestialBodiesShown", True)
    atmosphere = item(lighting, "Atmosphere", "SoftDistance")
    prop(atmosphere, "float", "Density", .25)
    prop(atmosphere, "float", "Offset", .15)
    color(atmosphere, "Color", [188, 225, 255])
    color(atmosphere, "Decay", [133, 117, 193])
    prop(atmosphere, "float", "Haze", 1)
    bloom = item(lighting, "BloomEffect", "NeonBloom")
    prop(bloom, "float", "Intensity", .3)
    prop(bloom, "float", "Size", 24)
    prop(bloom, "float", "Threshold", 1.2)
    correction = item(lighting, "ColorCorrectionEffect", "CandyColor")
    prop(correction, "float", "Saturation", .12)
    prop(correction, "float", "Contrast", .04)
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
    if not args.world_only:
        build(world)
        build(world, fast=True)
    print(f"World: {len(world['Parts'])} static parts, {len(world['PickupPositions'])} pickup slots, 8 arena spawns")


if __name__ == "__main__":
    main()
