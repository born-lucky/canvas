"""Package only versioned Canvas sources and the Godot addon."""
from pathlib import Path
import subprocess
import zipfile

root = Path(__file__).resolve().parents[1]
output = root / "dist"
output.mkdir(exist_ok=True)
files = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")
for name, addon_only in [("canvas-godot-v0.2.0.zip", True), ("canvas-framework-v0.2.0.zip", False)]:
    with zipfile.ZipFile(output / name, "w", zipfile.ZIP_DEFLATED) as archive:
        for relative in files:
            if not relative or not (root / relative).is_file(): continue
            if addon_only and not (relative.startswith("addons/") or relative in {"INSTALL.md", "LICENSE", "CHANGELOG.md"}): continue
            archive.write(root / relative, relative)
    print(output / name)
