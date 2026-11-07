"""Install a safe source-tree trim before repo sync.

Matched against the RESOLVED manifest (what repo would actually sync), so
entries that name projects which are absent -- or already removed by an
earlier manifest include such as twrp-default.xml -- are skipped instead of
aborting repo with "remove-project element specifies non-existent project".

Candidate sources:
  * the manifest's official remove-minimal.xml (.repo/manifests/remove-minimal.xml)
  * any extra candidate files passed on the command line

Usage: apply-trim.py <source-root> [extra-candidates.xml ...]
"""

import subprocess
import sys
from pathlib import Path
import xml.etree.ElementTree as ET


def load_resolved_projects(source):
    """Return {name: path} of projects repo will actually sync."""
    manifests = source / ".repo/manifests"
    try:
        xml_text = subprocess.check_output(
            ["repo", "manifest"], cwd=source, text=True)
        root = ET.fromstring(xml_text)
        projects = {}
        for node in root.iter("project"):
            name = node.get("name", "")
            if name:
                projects[name] = node.get("path", name)
        return projects
    except (OSError, subprocess.CalledProcessError, ET.ParseError) as exc:
        print(f"WARN: 'repo manifest' unavailable ({exc}); merging manifest files directly")

    # Fallback (no repo on this host): replay default.xml and its includes in
    # document order, applying remove-project as we go.
    projects = {}
    seen = set()

    def apply_manifest(file):
        if file.name in seen:
            return
        seen.add(file.name)
        root = ET.parse(file).getroot()
        for node in root:
            if node.tag == "include":
                included = manifests / node.get("name", "")
                if included.is_file():
                    apply_manifest(included)
            elif node.tag == "project":
                name = node.get("name", "")
                if name:
                    projects[name] = node.get("path", name)
            elif node.tag == "remove-project":
                key_name = node.get("name", "")
                key_path = node.get("path", "")
                for n, p in list(projects.items()):
                    if (key_name and n == key_name) or (key_path and p == key_path):
                        del projects[n]

    apply_manifest(manifests / "default.xml")
    return projects


def load_candidates(file):
    root = ET.parse(file).getroot()
    for node in root.iter("remove-project"):
        yield node.get("name", ""), node.get("path", "")


def main():
    source = Path(sys.argv[1])
    extra_files = [Path(p) for p in sys.argv[2:]]
    target = source / ".repo/local_manifests/yarp-trim.xml"
    target.unlink(missing_ok=True)  # stale trims must not affect resolution
    projects = load_resolved_projects(source)
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
    target.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(out).write(target, encoding="utf-8", xml_declaration=True)

    print(f"trim: {len(projects)} resolved manifest projects, removing {len(wanted)}, "
          f"{len(missing)} candidate(s) not in manifest")
    if missing:
        print("trim: skipped (not in manifest): " + ", ".join(missing[:20]))


if __name__ == "__main__":
    main()
