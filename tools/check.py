"""Check the exported Roblox place and the current Luau sources.

Run from any directory: python tools/check.py
Use --require-luau in CI to fail rather than skip when Luau tools are unavailable.
The gameplay harness uses current sources, not copies stored inside the tests.
These checks complement a Play test in Roblox Studio; they do not emulate its UI.
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
PLACE = ROOT / "Taller Tycoon.rbxlx"
SCRIPTS = (
    (("ReplicatedStorage", "MidnightGarage", "Config"), "ModuleScript", "src/shared/Config.luau"),
    (("ReplicatedStorage", "MidnightGarage", "Economy"), "ModuleScript", "src/shared/Economy.luau"),
    (("ServerScriptService", "MidnightGarage", "TycoonWorld"), "ModuleScript", "src/server/TycoonWorld.luau"),
    (("ServerScriptService", "MidnightGarage", "PlayerData"), "ModuleScript", "src/server/PlayerData.luau"),
    (("ServerScriptService", "MidnightGarage", "Main"), "Script", "src/server/Main.server.luau"),
    (("StarterPlayer", "StarterPlayerScripts", "MidnightGarageClient"), "LocalScript", "src/client/Main.client.luau"),
)
ANCHORS = tuple(f"Plot{index}Origin" for index in range(1, 5))
VEHICLES = ("Sedan", "SportsCar", "Pickup", "Supercar")
PART_CLASSES = ("Part", "MeshPart", "WedgePart")


def check(condition, message):
    if not condition:
        raise ValueError(message)


def property_text(item, tag, name):
    element = item.find(f"Properties/{tag}[@name='{name}']")
    return None if element is None else element.text


def item_name(item):
    return property_text(item, "string", "Name")


def child_named(parent, name):
    matches = [item for item in parent.findall("Item") if item_name(item) == name]
    check(len(matches) == 1, f"Expected exactly one child named {name}; found {len(matches)}.")
    return matches[0]


def item_at(root, names):
    item = root
    for name in names:
        item = child_named(item, name)
    return item


def source_at(relative):
    return (ROOT / relative).read_text(encoding="utf-8-sig")


def check_vehicles(root):
    templates = item_at(root, ("ServerStorage", "VehicleTemplates"))
    check(templates.get("class") == "Folder", "VehicleTemplates must be a Folder.")
    models = templates.findall("Item")
    check(sorted(item_name(item) for item in models) == sorted(VEHICLES), "Expected four official vehicle templates.")
    report = []
    for name in VEHICLES:
        model = child_named(templates, name)
        check(model.get("class") == "Model", f"Vehicle template {name} must be a Model.")
        descendants = list(model.iter("Item"))
        forbidden = [item for item in descendants if item.get("class") in ("Script", "LocalScript", "ModuleScript")]
        check(not forbidden, f"Vehicle template {name} contains executable scripts.")
        pivot = child_named(model, "VehicleRoot")
        check(pivot.get("class") == "Part", f"{name} needs a VehicleRoot Part.")
        check(property_text(model, "Ref", "PrimaryPart") == pivot.get("referent"), f"{name} PrimaryPart must reference VehicleRoot.")
        transparency = property_text(pivot, "float", "Transparency")
        check(transparency is not None and float(transparency) == 1, f"{name} VehicleRoot must be invisible.")
        body = child_named(model, "Body")
        check(body.get("class") == "Model", f"{name} Body must be a Model.")
        for wheel_name in ("FL", "FR", "RL", "RR"):
            wheel = child_named(body, wheel_name)
            check(wheel.get("class") == "Model", f"{name}/{wheel_name} must be a wheel Model.")
            wheel_meshes = [item for item in wheel.iter("Item") if item.get("class") == "MeshPart"]
            check(len(wheel_meshes) >= 3, f"{name}/{wheel_name} has incomplete wheel geometry.")
        meshes = [item for item in descendants if item.get("class") == "MeshPart"]
        check(len(meshes) >= 20, f"Vehicle template {name} has insufficient detailed geometry.")
        check(any(item_name(item) == "light_white" or item_name(item).lower().startswith("headlight") for item in meshes),
              f"Vehicle template {name} has no recognizable headlights.")
        markers = [item for item in descendants if item.get("class") == "BoolValue" and item_name(item) == "Paintable"]
        check(markers and all(property_text(item, "bool", "Value") == "true" for item in markers),
              f"Vehicle template {name} needs enabled Paintable markers.")
        for mesh in meshes:
            mesh_id = mesh.findtext("Properties/Content[@name='MeshId']/url", "")
            check(re.fullmatch(r"rbxassetid://[1-9][0-9]*", mesh_id) is not None,
                  f"{name}/{item_name(mesh)} has no valid Content MeshId asset URL.")
        z_low, z_high = math.inf, -math.inf
        for part in (item for item in descendants if item.get("class") in PART_CLASSES):
            title = f"{name}/{item_name(part)}"
            check(property_text(part, "bool", "Anchored") == "true", f"{title} is not anchored.")
            check(property_text(part, "bool", "CanCollide") == "false", f"{title} would block the workshop.")
            frame = part.find("Properties/CoordinateFrame[@name='CFrame']")
            size = part.find("Properties/Vector3[@name='size']")
            check(frame is not None and size is not None, f"{title} has incomplete geometry properties.")
            position = [float(frame.findtext(axis, "nan")) for axis in "XYZ"]
            dimensions = [float(size.findtext(axis, "nan")) for axis in "XYZ"]
            rotation = [float(frame.findtext(f"R{row}{col}", "nan")) for row in range(3) for col in range(3)]
            check(all(math.isfinite(value) for value in position + dimensions + rotation), f"{title} has invalid geometry values.")
            check(all(value > 0 for value in dimensions), f"{title} has a nonpositive size.")
            # The rotated box's Z extent includes all eight corners; checking the
            # part center or raw size alone misses rotated wheels and trim.
            half_z = sum(abs(rotation[6 + axis]) * dimensions[axis] / 2 for axis in range(3))
            z_low = min(z_low, position[2] - half_z)
            z_high = max(z_high, position[2] + half_z)
        check(z_high - z_low <= 12.01, f"{name} is too long for the bay: {z_high - z_low:.3f} studs.")
        report.append(f"{name} {len(meshes)} meshes/{z_high - z_low:.2f} studs")
    print("PASS sanitized vehicle templates: " + ", ".join(report) + ".")


def check_place():
    check(PLACE.is_file(), "Place file is missing. Run python tools/build.py first.")
    root = ET.parse(PLACE).getroot()
    check(root.tag == "roblox" and root.get("version") == "4", "Unexpected Roblox XML format.")
    instances = list(root.iter("Item"))
    referents = [item.get("referent") for item in instances]
    check(all(referents) and len(set(referents)) == len(referents), "Instance references must be unique.")
    workshop = item_at(root, ("Workspace", "MidnightGarage"))
    check(workshop.get("class") == "Model", "Workshop must be a Model.")
    for name in ANCHORS:
        anchor = child_named(workshop, name)
        check(anchor.get("class") == "Part", f"Interaction anchor {name} must be a Part.")
        check(property_text(anchor, "bool", "Anchored") == "true", f"Anchor {name} is not anchored.")
        check(property_text(anchor, "bool", "CanCollide") == "false", f"Anchor {name} would block players.")
        frame = anchor.find("Properties/CoordinateFrame[@name='CFrame']")
        check(frame is not None, f"Anchor {name} has no CFrame.")
        for axis in "XYZ":
            value = frame.findtext(axis)
            check(value is not None and math.isfinite(float(value)), f"Anchor {name} has an invalid position.")
    spawn = child_named(workshop, "EmployeeSpawn")
    check(spawn.get("class") == "SpawnLocation", "EmployeeSpawn must be a SpawnLocation.")
    check(property_text(spawn, "bool", "Enabled") == "true", "Employee spawn is disabled.")
    check(property_text(spawn, "bool", "Neutral") == "true", "Employee spawn must accept all players.")

    for location, class_name, relative in SCRIPTS:
        script = item_at(root, location)
        check(script.get("class") == class_name, f"Incorrect script class at {'/'.join(location)}.")
        embedded = property_text(script, "ProtectedString", "Source")
        check(embedded == source_at(relative), f"Exported {relative} is stale. Run python tools/build.py.")
        if class_name != "ModuleScript":
            check(property_text(script, "bool", "Disabled") == "false", f"Script {relative} is disabled.")

    remotes = item_at(root, ("ReplicatedStorage", "MidnightGarage", "Remotes"))
    for name in ("State", "Notify", "Action"):
        check(child_named(remotes, name).get("class") == "RemoteEvent", f"Remote {name} has the wrong class.")
    scripts = [item for item in instances if item.get("class") in ("Script", "LocalScript", "ModuleScript")]
    check(len(scripts) == len(SCRIPTS), "Unexpected executable scripts found in place.")
    check_vehicles(root)
    previews = item_at(root, ("ReplicatedStorage", "MidnightGarage", "CarTemplates"))
    check(sorted(item_name(item) for item in previews.findall("Item")) == sorted(VEHICLES), "Car previews are incomplete.")
    check(PLACE.read_bytes() == (ROOT / "Taller de medianoche.rbxlx").read_bytes(), "The legacy filename is stale.")
    print(f"PASS place XML: {len(instances)} instances, {len(ANCHORS)} plots, spawn, remotes and {len(SCRIPTS)} current scripts.")


def find_luau_tool(name):
    for filename in (name + ".exe", name):
        local = ROOT / ".tools" / "luau" / filename
        if local.is_file():
            return str(local)
    return shutil.which(name) or shutil.which(name + ".exe")


def run(command):
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if result.returncode:
        raise RuntimeError((result.stdout + result.stderr).strip() or f"Command failed: {command[0]}")
    return result.stdout


def check_luau(require_tools):
    compiler = find_luau_tool("luau-compile")
    interpreter = find_luau_tool("luau")
    missing = [name for name, path in (("luau-compile", compiler), ("luau", interpreter)) if not path]
    if require_tools:
        check(not missing, "Missing Luau tools: " + ", ".join(missing) + ". Install in .tools/luau or PATH.")
    if compiler:
        for _, _, relative in SCRIPTS:
            run([compiler, "--null", str(ROOT / relative)])
        print(f"PASS all {len(SCRIPTS)} Luau scripts compile.")
    else:
        print("SKIP Luau compilation: luau-compile is not in .tools/luau or PATH.")

    if interpreter:
        substitutions = {
            "__CONFIG_SOURCE__": source_at("src/shared/Config.luau"),
            "__ECONOMY_SOURCE__": source_at("src/shared/Economy.luau"),
            "__SERVER_SOURCE__": source_at("src/server/Main.server.luau"),
            "__DATA_SOURCE__": source_at("src/server/PlayerData.luau"),
        }
        for template_name in ("economy.template.luau", "player_data.template.luau"):
            template_path = ROOT / "tests" / template_name
            check(template_path.is_file(), f"Missing test template {template_name}.")
            harness = template_path.read_text(encoding="utf-8")
            for placeholder, content in substitutions.items():
                if placeholder in harness:
                    check(harness.count(placeholder) == 1, f"Expected one {placeholder} in {template_name}.")
                    harness = harness.replace(placeholder, content)
            with tempfile.TemporaryDirectory(prefix="tycoon-tests-") as temporary:
                script = Path(temporary) / "test.luau"
                script.write_text(harness, encoding="utf-8")
                output = run([interpreter, str(script)])
                print(output, end="" if output.endswith("\n") else "\n")
    else:
        print("SKIP server gameplay tests: luau is not in .tools/luau or PATH.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--require-luau", action="store_true", help="Fail if the Luau compiler or interpreter is unavailable.")
    args = parser.parse_args()
    try:
        check_place()
        check_luau(args.require_luau)
    except (OSError, ValueError, RuntimeError, ET.ParseError) as error:
        print(f"FAIL {error}", file=sys.stderr)
        return 1
    print("Checks completed. Verify graphics and real input with Play in Roblox Studio.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
