"""Download NKAS chibi packs and extract their original GLB models."""
import concurrent.futures
import json
from pathlib import Path
import struct
import subprocess

BASE = "https://nkas-chibis.pages.dev/"
OUT = Path(__file__).resolve().parents[1] / "assets" / "nkas-chibi"


def fetch(path):
    return subprocess.run(
        ["curl", "--fail", "--location", "--silent", "--show-error",
         "--retry", "3", "--max-time", "120", BASE + path],
        check=True, capture_output=True,
    ).stdout


def extract(item):
    model_id, entry = item
    target = OUT / model_id
    target.mkdir(exist_ok=True)
    pack = target / (model_id + ".sdp")
    if not pack.exists() or pack.stat().st_size != entry["packBytes"]:
        data = fetch(entry["pack"])
        assert len(data) == entry["packBytes"], model_id
        pack.write_bytes(data)
    data = pack.read_bytes()
    assert data[:4] == b"SDP1", model_id
    header_length = struct.unpack_from("<I", data, 4)[0]
    base = 8 + header_length
    header = json.loads(data[8:base])
    offset, length = header["glb"]
    glb = data[base + offset:base + offset + length]
    assert glb[:4] == b"glTF" and len(glb) == length, model_id
    assert struct.unpack_from("<I", glb, 8)[0] == length, model_id
    (target / (model_id + ".glb")).write_bytes(glb)
    (target / "pack-header.json").write_text(json.dumps(header, indent=2))
    return model_id


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    manifest_data = fetch("manifest.json")
    manifest = json.loads(manifest_data)
    (OUT / "manifest.json").write_bytes(manifest_data)
    entries = manifest["variants"]
    print(f"Downloading {len(entries)} variants", flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for count, model_id in enumerate(pool.map(extract, entries.items()), 1):
            if count % 20 == 0 or count == len(entries):
                print(f"{count}/{len(entries)} extracted; latest {model_id}", flush=True)
    print("Complete:", OUT, flush=True)


if __name__ == "__main__":
    main()
