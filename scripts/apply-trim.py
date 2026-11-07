"""Install a safe source-tree trim before repo sync.

Reads the official remove-minimal.xml shipped inside the pinned manifest
(.repo/manifests/remove-minimal.xml) plus an optional extra candidate file,
matches every entry against the RESOLVED manifest, and writes only the
matches to .repo/local_manifests/yarp-trim.xml. Entries that do not exist in
the manifest are skipped instead of aborting repo, so the candidate lists can
safely span manifest revisions.

Usage: apply-trim.py <source-root> [extra-candidates.xml ...]
"""

import sys
from pathlib import Path
import xml.etree.ElementTree as ET


def load_manifest_projects(source):
    # Every project the pinned manifest defines (default.xml + its includes,
    # e.g. twrp-default.xml which swaps in the TWRP-Test forks).
    projects = {}
    for manifest_file in sorted((source / ".repo/manifests").glob("*.xml")):
        try:
            root = ET.parse(manifest_file).getroot()
        except ET.ParseError:
            continue
        for node in root.iter("project"):
            name = node.get("name", "")
            path = node.get("path", name)
            if name:
                projects[name] = path
    return projects


def load_candidates(file):
    root = ET.parse(file).getroot()
    for node in root.iter("remove-project"):
        yield node.get("name", ""), node.get("path", "")


def main():
    source = Path(sys.argv[1])
    extra_files = [Path(p) for p in sys.argv[2:]]
    projects = load_manifest_projects(source)
    by_path = {path: name for name, path in projects.items()}

    candidates = []
    official = source / ".repo/manifests/remove-minimal.xml"
    if official.is_file():
        candidates.append(official)
    else:
        print(f"WARN: {official} not found; trimming with extras only")
    candidates += [f for f in extra_files if f.is_file()]

    wanted = {}
    missing = []
    for file in candidates:
        for name, path in load_candidates(file):
            if name and name in projects:
                wanted[name] = path
            elif path and path in by_path:
                wanted[by_path[path]] = path
            else:
                missing.append(name or path)

    out = ET.Element("manifest")
    for name in sorted(wanted):
        ET.SubElement(out, "remove-project", {"name": name})
    target = source / ".repo/local_manifests/yarp-trim.xml"
    target.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(out).write(target, encoding="utf-8", xml_declaration=True)

    print(f"trim: {len(projects)} manifest projects, removing {len(wanted)}, "
          f"{len(missing)} candidate(s) not in manifest")
    if missing:
        print("trim: skipped (not in manifest): " + ", ".join(missing[:20]))


if __name__ == "__main__":
    main()
