"""Build the complete Roblox place with Python's standard library.

Run: python tools/build.py
The source stays editable; Roblox Studio can open the resulting .rbxlx directly.
"""
from __future__ import annotations

import itertools
import math
from copy import deepcopy
from pathlib import Path
import xml.etree.ElementTree as ET

from scene import create_scene

ROOT = Path(__file__).resolve().parents[1]
IDS = itertools.count(1)


def item(parent, kind, name):
    element = ET.SubElement(parent, "Item", {"class": kind, "referent": f"RBX{next(IDS):08X}"})
    properties = ET.SubElement(element, "Properties")
    prop(properties, "string", "Name", name)
    return element, properties


def prop(parent, tag, name, value):
    element = ET.SubElement(parent, tag, {"name": name})
    element.text = str(value).lower() if isinstance(value, bool) else str(value)
    return element


def vec(parent, name, xyz):
    element = ET.SubElement(parent, "Vector3", {"name": name})
    for axis, value in zip("XYZ", xyz):
        ET.SubElement(element, axis).text = str(value)


def color(parent, name, rgb):
    element = ET.SubElement(parent, "Color3", {"name": name})
    for channel, value in zip("RGB", rgb):
        ET.SubElement(element, channel).text = str(value / 255)


def cframe(parent, name, xyz, rotation=(0, 0, 0), matrix=None):
    element = ET.SubElement(parent, "CoordinateFrame", {"name": name})
    if matrix is None:
        rx, ry, rz = map(math.radians, rotation)
        cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
        matrix = (
            cy*cz, -cy*sz, sy,
            cx*sz+sx*sy*cz, cx*cz-sx*sy*sz, -sx*cy,
            sx*sz-cx*sy*cz, sx*cz+cx*sy*sz, cx*cy,
        )
    for axis, value in zip("XYZ", xyz):
        ET.SubElement(element, axis).text = str(value)
    for index, value in enumerate(matrix):
        ET.SubElement(element, f"R{index // 3}{index % 3}").text = str(value)


def camera_frame(properties, name, position, target):
    # CFrame.lookAt: right, up and back are the matrix columns.
    def norm(v):
        length = math.sqrt(sum(n*n for n in v))
        return tuple(n / length for n in v)
    def cross(a, b):
        return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
    back = norm(tuple(a-b for a, b in zip(position, target)))
    right = norm(cross((0, 1, 0), back))
    up = cross(back, right)
    matrix = tuple((right, up, back)[col][row] for row in range(3) for col in range(3))
    cframe(properties, name, position, matrix=matrix)


MATERIALS = {"Plastic": 256, "SmoothPlastic": 272, "Neon": 288, "Wood": 512,
             "WoodPlanks": 528, "Concrete": 816, "Brick": 848, "Slate": 800,
             "Asphalt": 1376, "Metal": 1088, "DiamondPlate": 1056,
             "Glass": 1568, "Grass": 1280, "Sand": 1296, "Fabric": 1312,
             "Cobblestone": 880, "CorrodedMetal": 1040, "Foil": 1072}
FACES = {"Right": 0, "Top": 1, "Back": 2, "Left": 3, "Bottom": 4, "Front": 5}


def make_surface(part, spec):
    surface, properties = item(part, "SurfaceGui", "Sign")
    prop(properties, "token", "Face", FACES.get(spec.get("face", "Front"), 5))
    prop(properties, "token", "SizingMode", 1)
    prop(properties, "float", "PixelsPerStud", 40)
    prop(properties, "bool", "AlwaysOnTop", False)
    prop(properties, "float", "LightInfluence", 0)
    label, p = item(surface, "TextLabel", "Lettering")
    udim = ET.SubElement(p, "UDim2", {"name": "Size"})
    for key, val in (("XS", 1), ("XO", 0), ("YS", 1), ("YO", 0)):
        ET.SubElement(udim, key).text = str(val)
    prop(p, "float", "BackgroundTransparency", 0 if "backgroundColor" in spec else 1)
    color(p, "BackgroundColor3", spec.get("backgroundColor", [16, 25, 32]))
    color(p, "TextColor3", spec.get("textColor", [225, 240, 238]))
    prop(p, "string", "Text", spec["text"])
    prop(p, "bool", "TextScaled", True)
    prop(p, "bool", "TextWrapped", True)
    prop(p, "int", "BorderSizePixel", 0)
    prop(p, "token", "Font", 20)  # GothamBold


def make_part(parent, spec, kind="Part"):
    part, p = item(parent, kind, spec["name"])
    vec(p, "size", spec["size"])
    cframe(p, "CFrame", spec["position"], spec.get("rotation", [0, 0, 0]))
    rgb = spec.get("color", [100, 110, 120])
    prop(p, "Color3uint8", "Color3uint8", 0xFF000000 | (int(rgb[0]) << 16) | (int(rgb[1]) << 8) | int(rgb[2]))
    prop(p, "bool", "Anchored", True)
    prop(p, "bool", "CanCollide", spec.get("canCollide", True))
    prop(p, "bool", "CanTouch", False)
    prop(p, "float", "Transparency", spec.get("transparency", 0))
    prop(p, "float", "Reflectance", spec.get("reflectance", 0))
    prop(p, "bool", "CastShadow", spec.get("castShadow", True))
    prop(p, "token", "Material", MATERIALS.get(spec.get("material", "SmoothPlastic"), 272))
    prop(p, "token", "TopSurface", 0)
    prop(p, "token", "BottomSurface", 0)
    if kind == "Part":
        prop(p, "token", "shape", {"Ball": 0, "Block": 1, "Cylinder": 2}.get(spec.get("shape", "Block"), 1))
    for key, cls in (("pointLight", "PointLight"), ("spotLight", "SpotLight"), ("surfaceLight", "SurfaceLight")):
        if key in spec:
            ls = spec[key]
            light, lp = item(part, cls, cls)
            color(lp, "Color", ls.get("color", [255, 224, 175]))
            prop(lp, "float", "Brightness", ls.get("brightness", 1))
            prop(lp, "float", "Range", ls.get("range", 18))
            prop(lp, "bool", "Shadows", False)
            if cls != "PointLight":
                prop(lp, "token", "Face", FACES.get(ls.get("face", "Bottom"), 4))
                prop(lp, "float", "Angle", ls.get("angle", 100))
    for surface in spec.get("surfaces", []):
        make_surface(part, surface)
    return part, p


def script(parent, kind, name, source_path):
    element, p = item(parent, kind, name)
    source = (ROOT / source_path).read_text(encoding="utf-8-sig")
    prop(p, "ProtectedString", "Source", source)
    if kind != "ModuleScript":
        prop(p, "bool", "Disabled", False)
    return element


def model_asset(parent, relative_path):
    asset = ET.parse(ROOT / relative_path).getroot()
    models = [deepcopy(node) for node in asset.findall("Item")]
    replacements = {}
    for model in models:
        for instance in model.iter("Item"):
            previous = instance.attrib["referent"]
            replacements[previous] = f"RBX{next(IDS):08X}"
            instance.attrib["referent"] = replacements[previous]
    for model in models:
        for reference in model.iter("Ref"):
            reference.text = replacements.get(reference.text, "null")
        parent.append(model)


def root_xml():
    root = ET.Element("roblox", {"version": "4"})
    ET.SubElement(root, "External").text = "null"
    ET.SubElement(root, "External").text = "nil"
    return root


def write_xml(root, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(root, space="  ")
    ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=True)


def main():
    scene = create_scene()
    root = root_xml()
    workspace, wp = item(root, "Workspace", "Workspace")
    prop(wp, "float", "Gravity", 196.2)
    prop(wp, "float", "FallenPartsDestroyHeight", -60)
    prop(wp, "bool", "StreamingEnabled", False)
    camera, cp = item(workspace, "Camera", "Camera")
    camera_frame(cp, "CFrame", [143, 125, -175], [0, 2, 0])
    camera_frame(cp, "Focus", [0, 2, 0], [0, 2, 1])
    prop(cp, "token", "CameraType", 5)
    prop(cp, "float", "FieldOfView", 70)
    prop(wp, "Ref", "CurrentCamera", camera.attrib["referent"])
    model, mp = item(workspace, "Model", "MidnightGarage")
    for spec in scene["parts"]:
        make_part(model, spec)
    spawn_spec = {"name": "EmployeeSpawn", "size": [5, 0.3, 5], "color": [43, 76, 78],
                  "material": "SmoothPlastic", "transparency": 1, **scene["spawn"]}
    spawn, sp = make_part(model, spawn_spec, "SpawnLocation")
    prop(sp, "bool", "Neutral", True)
    prop(sp, "bool", "Enabled", True)
    prop(sp, "bool", "AllowTeamChangeOnTouch", False)
    prop(sp, "float", "Duration", 0)
    lights, lp = item(root, "Lighting", "Lighting")
    ls = {key[0].upper() + key[1:]: value for key, value in scene.get("lighting", {}).items()}
    for name, val in {"ClockTime": 0.7, "Brightness": 2.2, "ExposureCompensation": 0.1,
                      "FogStart": 90, "FogEnd": 340, "EnvironmentDiffuseScale": 0.5,
                      "EnvironmentSpecularScale": 0.5, **{k:v for k,v in ls.items() if isinstance(v, (int,float))}}.items():
        prop(lp, "float", name, val)
    for name, val in {"Ambient": [65, 75, 94], "OutdoorAmbient": [64, 73, 94],
                      "FogColor": [22, 33, 49], **{k:v for k,v in ls.items() if isinstance(v, list)}}.items():
        color(lp, name, val)
    prop(lp, "bool", "GlobalShadows", True)
    prop(lp, "token", "Technology", 4)
    bloom, bp = item(lights, "BloomEffect", "NeonGlow")
    prop(bp, "float", "Intensity", 0.25)
    prop(bp, "float", "Size", 24)
    prop(bp, "float", "Threshold", 1.6)
    correction, ccp = item(lights, "ColorCorrectionEffect", "NightPalette")
    prop(ccp, "float", "Saturation", -0.08)
    prop(ccp, "float", "Contrast", 0.08)
    rep, _ = item(root, "ReplicatedStorage", "ReplicatedStorage")
    shared, _ = item(rep, "Folder", "MidnightGarage")
    script(shared, "ModuleScript", "Config", "src/shared/Config.luau")
    script(shared, "ModuleScript", "Economy", "src/shared/Economy.luau")
    previews, _ = item(shared, "Folder", "CarTemplates")
    for kind in ("Sedan", "SportsCar", "Pickup", "Supercar"):
        model_asset(previews, f"assets/vehicles/{kind}.rbxmx")
    remotes, _ = item(shared, "Folder", "Remotes")
    for name in ("State", "Notify", "Action"):
        item(remotes, "RemoteEvent", name)
    sss, _ = item(root, "ServerScriptService", "ServerScriptService")
    server, _ = item(sss, "Folder", "MidnightGarage")
    script(server, "ModuleScript", "TycoonWorld", "src/server/TycoonWorld.luau")
    script(server, "ModuleScript", "PlayerData", "src/server/PlayerData.luau")
    script(server, "Script", "Main", "src/server/Main.server.luau")
    storage, _ = item(root, "ServerStorage", "ServerStorage")
    templates, _ = item(storage, "Folder", "VehicleTemplates")
    for kind in ("Sedan", "SportsCar", "Pickup", "Supercar"):
        model_asset(templates, f"assets/vehicles/{kind}.rbxmx")
    starter, stp = item(root, "StarterPlayer", "StarterPlayer")
    prop(stp, "float", "CameraMaxZoomDistance", 65)
    prop(stp, "float", "CameraMinZoomDistance", 6)
    prop(stp, "float", "CharacterWalkSpeed", 19)
    scripts, _ = item(starter, "StarterPlayerScripts", "StarterPlayerScripts")
    script(scripts, "LocalScript", "MidnightGarageClient", "src/client/Main.client.luau")
    item(root, "StarterGui", "StarterGui")
    item(root, "SoundService", "SoundService")
    chat, chatp = item(root, "TextChatService", "TextChatService")
    prop(chatp, "token", "ChatVersion", 1)
    prop(chatp, "bool", "CreateDefaultTextChannels", True)
    prop(chatp, "bool", "CreateDefaultCommands", True)
    write_xml(root, ROOT / "Taller Tycoon.rbxlx")
    write_xml(root, ROOT / "Taller de medianoche.rbxlx")
    model_root = root_xml()
    model_root.append(model)
    write_xml(model_root, ROOT / "assets/Workshop.rbxmx")
    total = len(root.findall(".//Item"))
    print(f"Built Taller Tycoon.rbxlx: {total} instances, {len(scene['parts'])} scene parts. Legacy filename updated too.")


if __name__ == "__main__":
    main()
