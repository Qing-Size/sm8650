"""Generate a Repo overlay or verify the pinned YARP projects after sync.

sources.json schema:
  manifest: {url, revision}            repo manifest (TWRP-Test twrp-16.0)
  projects: [{name, path, revision}]   pinned platform projects
  device:   {owner, name, path, revision}
        owner    GitHub user or organization hosting the device tree
        revision commit SHA (recommended) or branch name
"""

import json
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

SHA_LENGTH = 40
HEX_DIGITS = set("0123456789abcdef")


def is_sha(revision):
    return len(revision) == SHA_LENGTH and set(revision) <= HEX_DIGITS


def main():
    command, lock_path, source_path = sys.argv[1:]
    lock = json.loads(Path(lock_path).read_text(encoding="utf-8"))
    source = Path(source_path)
    device = lock["device"]
    if command == "overlay":
        manifest = ET.Element("manifest")
        for project in lock["projects"]:
            ET.SubElement(manifest, "extend-project", {
                **project, "upstream": "refs/heads/twrp-16.0"
            })
        ET.SubElement(manifest, "remote", {
            "name": "yarp-device",
            "fetch": "https://github.com/" + device.get("owner", "TWRP-Test"),
        })
        ET.SubElement(manifest, "project", {
            "name": device["name"],
            "path": device["path"],
            "revision": device.get("revision", "main"),
            "remote": "yarp-device",
        })
        target = source / ".repo/local_manifests/yarp-pins.xml"
        target.parent.mkdir(parents=True, exist_ok=True)
        ET.ElementTree(manifest).write(target, encoding="utf-8", xml_declaration=True)
        print(f"Wrote {target}")
    elif command == "verify":
        projects = [{"path": ".repo/manifests", **lock["manifest"]}]
        projects += lock["projects"]
        revision = device.get("revision", "main")
        if is_sha(revision):
            projects.append({"path": device["path"], "revision": revision})
        else:
            print(f"WARN: device tree pinned to branch {revision!r}; "
                  "pin a commit SHA in sources.json for reproducible builds")
        for project in projects:
            actual = subprocess.check_output(
                ["git", "-C", str(source / project["path"]), "rev-parse", "HEAD"],
                text=True,
            ).strip()
            if actual != project["revision"]:
                raise RuntimeError(f"Source mismatch: {project['path']}: {actual}")
            print(f"Verified {project['path']}: {actual}")
    else:
        raise ValueError(f"Unknown command: {command}")


if __name__ == "__main__":
    main()
