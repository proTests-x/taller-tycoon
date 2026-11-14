"""Prepare the visual geometry of Roblox's free endorsed vehicles.

Input: official models converted with rbxmk under .tools/asset-candidates.
Output: small, normalized, script-free templates checked into assets/vehicles.
This command is needed only when updating the vehicle assets, not to build.
"""
from __future__ import annotations

from copy import deepcopy
import itertools
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
REFERENTS = itertools.count(1)


def name(item):
    return item.findtext("Properties/string[@name='Name']", "")


def add(props, tag, key, value):
    item = ET.SubElement(props, tag, {"name": key})
    item.text = str(value).lower() if isinstance(value, bool) else str(value)
    return item


def new_item(parent, cls, title):
    item = ET.SubElement(parent, "Item", {"class": cls, "referent": f"VEHICLE{next(REFERENTS):08X}"})
    props = ET.SubElement(item, "Properties")
    add(props, "string", "Name", title)
    return item, props


def vector(props, key, values):
    item = ET.SubElement(props, "Vector3", {"name": key})
    for axis, value in zip("XYZ", values):
        ET.SubElement(item, axis).text = f"{value:.8g}"


def frame_values(part):
    cf = part.find("Properties/CoordinateFrame[@name='CFrame']")
    return [float(cf.findtext(axis, "0")) for axis in ("X", "Y", "Z")], [float(cf.findtext(f"R{i}{j}", "0")) for i in range(3) for j in range(3)]


def frame(props, position, rotation):
    item = ET.SubElement(props, "CoordinateFrame", {"name": "CFrame"})
    for key, val in zip(("X", "Y", "Z") + tuple(f"R{i}{j}" for i in range(3) for j in range(3)), position + rotation):
        ET.SubElement(item, key).text = f"{val:.9g}"


def prepare(kind):
    raw = (ROOT / ".tools/asset-candidates" / f"{kind}.rbxmx").read_text(encoding="utf-8")
    # rbxmk v0.9 encodes unrecognized binary attributes as XML strings. They are
    # controller settings and never belong in a stationary geometry template.
    raw = re.sub(r'<string name="AttributesSerialize">.*?</string>', "", raw, flags=re.S)
    raw = re.sub(r"&#(\d+);", lambda match: match[0] if int(match[1]) >= 32 or int(match[1]) in (9, 10, 13) else "", raw)
    source = ET.fromstring(raw)
    variant = source.find("Item")
    body = next(child for child in variant.findall("Item") if name(child) == "Body")
    parts = [part for part in body.iter("Item") if part.get("class") in ("Part", "MeshPart", "WedgePart")]
    bounds = []
    for part in parts:
        position, rotation = frame_values(part)
        size = [float(part.findtext(f"Properties/Vector3[@name='size']/{axis}")) for axis in "XYZ"]
        half = [sum(abs(rotation[row*3+col]) * size[col] / 2 for col in range(3)) for row in range(3)]
        bounds.append(([position[i]-half[i] for i in range(3)], [position[i]+half[i] for i in range(3)]))
    low = [min(bound[0][i] for bound in bounds) for i in range(3)]
    high = [max(bound[1][i] for bound in bounds) for i in range(3)]
    center = [(low[0]+high[0])/2, low[1], (low[2]+high[2])/2]
    scale = min(6.6/(high[0]-low[0]), 12/(high[2]-low[2]))
    root = ET.Element("roblox", {"version": "4"})
    ET.SubElement(root, "External").text = "null"
    ET.SubElement(root, "External").text = "nil"
    model, mp = new_item(root, "Model", kind)
    pivot, pp = new_item(model, "Part", "VehicleRoot")
    vector(pp, "size", [0.2, 0.2, 0.2])
    frame(pp, [0, 0, 0], [1, 0, 0, 0, 1, 0, 0, 0, 1])
    add(pp, "bool", "Anchored", True)
    add(pp, "bool", "CanCollide", False)
    add(pp, "bool", "CanTouch", False)
    add(pp, "bool", "CanQuery", False)
    add(pp, "float", "Transparency", 1)
    add(mp, "Ref", "PrimaryPart", pivot.get("referent"))

    def clone_geometry(source_item, parent, in_wheel=False):
        cls, title = source_item.get("class"), name(source_item)
        if cls not in ("Model", "Part", "MeshPart", "WedgePart"):
            return
        target, props = new_item(parent, cls, title)
        in_wheel = in_wheel or title in ("FL", "FR", "RL", "RR")
        if cls != "Model":
            position, rotation = frame_values(source_item)
            frame(props, [(position[i]-center[i])*scale for i in range(3)], rotation)
            original = source_item.find("Properties")
            for prop in original:
                key = prop.get("name")
                if key in ("Color3uint8", "Material", "Transparency", "Reflectance", "DoubleSided", "CastShadow", "InitialSize", "shape"):
                    props.append(deepcopy(prop))
                elif key == "size":
                    vector(props, "size", [float(prop.findtext(axis))*scale for axis in "XYZ"])
            for key in ("MeshId", "TextureID"):
                value = original.findtext(f"string[@name='{key}']")
                if not value and key == "MeshId":
                    value = original.findtext("string[@name='MeshID']")
                if value:
                    content = ET.SubElement(props, "Content", {"name": key})
                    ET.SubElement(content, "url").text = value
            for key in ("Anchored", "CanCollide", "CanTouch", "CanQuery"):
                add(props, "bool", key, key == "Anchored")
            color = int(original.findtext("Color3uint8[@name='Color3uint8']", "0"))
            rgb = [(color >> shift) & 255 for shift in (16, 8, 0)]
            exclude = ("glass", "light", "trim", "grill", "interior", "mirror", "_int", "tire", "wheel")
            if not in_wheel and not any(word in title.lower() for word in exclude) and max(rgb)-min(rgb) > 30:
                marker, markerp = new_item(target, "BoolValue", "Paintable")
                add(markerp, "bool", "Value", True)
        for child in source_item.findall("Item"):
            clone_geometry(child, target, in_wheel)

    clone_geometry(body, model)
    out = ROOT / "assets/vehicles" / f"{kind}.rbxmx"
    out.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(root, space="  ")
    ET.ElementTree(root).write(out, encoding="utf-8", xml_declaration=True)
    size = [(high[i]-low[i])*scale for i in range(3)]
    print(f"{kind}: {len(parts)} visual meshes, normalized {size[0]:.2f} x {size[1]:.2f} x {size[2]:.2f}; no scripts/controllers.")


if __name__ == "__main__":
    for vehicle in ("Sedan", "SportsCar", "Pickup", "Supercar"):
        prepare(vehicle)
