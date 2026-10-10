#!/usr/bin/env python3
"""Build a standalone source trial ZIP from an explicit public-file allowlist."""
from pathlib import Path
import hashlib
import json
import subprocess
import zipfile

root = Path(__file__).resolve().parents[1]
prefix = "RayNeoWorkspace-v0.10.1-source-trial"
output = root / "build" / "exports" / (prefix + ".zip")
files = [root / "build.sh", root / "README.md", root / "README.zh-CN.md"]
for folder in ("Sources", "Assets", "Tests", "scripts"):
    files += [p for p in (root / folder).rglob("*")
              if p.is_file() and not p.is_symlink()
              and "AppIcon.iconset" not in p.parts and "__pycache__" not in p.parts
              and p.name != ".DS_Store"]
for name in ("FRIEND_TRIAL.md", "ARCHITECTURE.md", "PERFORMANCE.md", "SIGNING.md", "TESTING.md"):
    files.append(root / "docs" / name)
payload = {p.relative_to(root).as_posix(): p.read_bytes() for p in sorted(set(files))}
payload["构建体验版.command"] = b'#!/bin/bash\nset -euo pipefail\ncd "$(dirname "$0")"\nSIGNING_IDENTITY=- bash build.sh\nprintf "\\nBuild complete. Open build/dev/RayNeoWorkspace-Dev.app to start.\\n"\n'
revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
manifest = {"version": "0.10.1-dev", "source_commit": revision, "files": {
    name: hashlib.sha256(data).hexdigest() for name, data in sorted(payload.items())}}
payload["SOURCE-MANIFEST.json"] = json.dumps(manifest, indent=2, ensure_ascii=False).encode("utf-8")
output.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
    for name, data in sorted(payload.items()):
        info = zipfile.ZipInfo(prefix + "/" + name)
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = ((0o100755 if name.endswith((".sh", ".command")) else 0o100644) << 16)
        archive.writestr(info, data)
with zipfile.ZipFile(output) as archive:
    assert archive.testzip() is None
    for name, data in payload.items():
        assert archive.read(prefix + "/" + name) == data
print(output)
print("SHA256 " + hashlib.sha256(output.read_bytes()).hexdigest())
print(f"{len(payload)} files; {output.stat().st_size} bytes")
