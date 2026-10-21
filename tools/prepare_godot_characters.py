"""Convert the starter roster's SDP animations to standard animated GLBs."""
import json
import math
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
ROSTER = ("c010_00", "c011_00", "c012_00", "c013_00", "c020_00", "c022_00")
CLIPS = ("idle", "run", "walk", "shot", "death")


def convert(model_id):
    folder = ROOT / "assets/nkas-chibi" / model_id
    pack = (folder / f"{model_id}.sdp").read_bytes()
    assert pack[:4] == b"SDP1"
    header_size = struct.unpack_from("<I", pack, 4)[0]
    header = json.loads(pack[8:8 + header_size])
    pack_base = 8 + header_size
    offset, length = header["glb"]
    glb = pack[pack_base + offset:pack_base + offset + length]
    json_size = struct.unpack_from("<I", glb, 12)[0]
    doc = json.loads(glb[20:20 + json_size])
    binary_size = struct.unpack_from("<I", glb, 20 + json_size)[0]
    binary = bytearray(glb[28 + json_size:28 + json_size + binary_size])
    paths = {}

    def walk(index, path):
        node = doc["nodes"][index]
        path = path + "/" + node.get("name", "")
        paths[path] = index
        for child in node.get("children", []):
            walk(child, path)

    for root in doc["scenes"][doc.get("scene", 0)]["nodes"]:
        walk(root, "")
    bone_nodes = {}
    for bone in header["bones"]:
        matches = [node for path, node in paths.items() if path.endswith("/" + bone)]
        assert len(matches) == 1, (model_id, bone, matches)
        bone_nodes[bone] = matches[0]

    # A wrapper keeps every clip facing the same direction as the viewer.
    wrapper = len(doc["nodes"])
    scene = doc["scenes"][doc.get("scene", 0)]
    doc["nodes"].append({"name": "Facing", "children": scene["nodes"]})
    scene["nodes"] = [wrapper]

    def accessor(values, kind, components, bounds=False):
        while len(binary) % 4:
            binary.append(0)
        start = len(binary)
        binary.extend(struct.pack("<" + "f" * len(values), *values))
        view = len(doc["bufferViews"])
        doc["bufferViews"].append({"buffer": 0, "byteOffset": start,
                                   "byteLength": len(values) * 4})
        result = {"bufferView": view, "componentType": 5126,
                  "count": len(values) // components, "type": kind}
        if bounds:
            result.update(min=[min(values)], max=[max(values)])
        index = len(doc["accessors"])
        doc["accessors"].append(result)
        return index

    doc["animations"] = []
    for name in CLIPS:
        if name not in header["clips"]:
            continue
        clip = header["clips"][name]
        start = pack_base + clip["off"]
        floats = struct.unpack("<" + "f" * (clip["len"] // 4), pack[start:start + clip["len"]])
        times = [frame / clip["fps"] for frame in range(clip["frames"])]
        time_full = accessor(times, "SCALAR", 1, True)
        time_constant = accessor([0.0, times[-1]], "SCALAR", 1, True)
        animation = {"name": name, "samplers": [], "channels": []}

        def channel(node, prop, values, constant=False):
            components = 4 if prop == "rotation" else 3
            if constant:
                values = values * 2
            output = accessor(values, "VEC4" if components == 4 else "VEC3", components)
            sampler = len(animation["samplers"])
            animation["samplers"].append({"input": time_constant if constant else time_full,
                                           "output": output, "interpolation": "LINEAR"})
            animation["channels"].append({"sampler": sampler, "target": {"node": node, "path": prop}})

        for bone_id, prop_id, constant, off in clip["channels"]:
            prop = ("translation", "rotation", "scale")[prop_id]
            count = 4 if prop_id == 1 else 3
            samples = 1 if constant else clip["frames"]
            values = list(floats[off:off + samples * count])
            assert len(values) == samples * count
            # SDP stores Unity coordinates; these match the site's viewer conversion.
            for sample in range(samples):
                base = sample * count
                if prop_id == 0:
                    values[base] *= -1
                elif prop_id == 1:
                    values[base + 1] *= -1
                    values[base + 2] *= -1
            channel(bone_nodes[header["bones"][bone_id]], prop, values, bool(constant))
        yaw = math.radians(clip.get("frontYaw") or header.get("frontYaw") or 0)
        channel(wrapper, "rotation", [0, math.sin(yaw / 2), 0, math.cos(yaw / 2)], True)
        doc["animations"].append(animation)

    doc["buffers"][0]["byteLength"] = len(binary)
    json_chunk = json.dumps(doc, separators=(",", ":")).encode()
    json_chunk += b" " * (-len(json_chunk) % 4)
    binary += b"\0" * (-len(binary) % 4)
    total = 12 + 8 + len(json_chunk) + 8 + len(binary)
    result = (struct.pack("<III", 0x46546C67, 2, total)
              + struct.pack("<II", len(json_chunk), 0x4E4F534A) + json_chunk
              + struct.pack("<II", len(binary), 0x004E4942) + binary)
    output = ROOT / "game/assets/characters" / f"{model_id}.glb"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(result)
    print(f"{model_id}: {len(doc['animations'])} clips, {len(result):,} bytes")


if __name__ == "__main__":
    for variant in ROSTER:
        convert(variant)
