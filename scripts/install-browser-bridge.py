#!/usr/bin/env python3
"""Register an unpacked companion extension. No administrator privileges required."""
import argparse
import json
import pathlib
import re
import shlex

parser = argparse.ArgumentParser()
parser.add_argument("extension_id", help="ID shown by your browser's extensions page")
parser.add_argument("--browser", choices=["chrome", "edge", "brave"], default="chrome")
parser.add_argument("--app", type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[1] / ".build/ConstellationBar.app")
args = parser.parse_args()
if not re.fullmatch(r"[a-p]{32}", args.extension_id):
    parser.error("extension_id must be the 32-letter ID from the browser")
binary = args.app.resolve() / "Contents/MacOS/ConstellationBar"
if not binary.is_file():
    parser.error("Build or select ConstellationBar.app first")
support = pathlib.Path.home() / "Library/Application Support"
bridge = support / "ConstellationBar/BrowserMedia"
bridge.mkdir(parents=True, exist_ok=True, mode=0o700)
launcher = bridge / "native-host"
launcher.write_text("#!/bin/sh\nexec " + shlex.quote(str(binary)) + " --browser-host\n")
launcher.chmod(0o700)
locations = {"chrome": "Google/Chrome", "edge": "Microsoft Edge", "brave": "BraveSoftware/Brave-Browser"}
folder = support / locations[args.browser] / "NativeMessagingHosts"
folder.mkdir(parents=True, exist_ok=True)
manifest = folder / "dev.constellation.browser_media.json"
manifest.write_text(json.dumps({"name": "dev.constellation.browser_media", "description": "ConstellationBar media bridge", "path": str(launcher), "type": "stdio", "allowed_origins": [f"chrome-extension://{args.extension_id}/"]}, indent=2) + "\n")
manifest.chmod(0o600)
print(f"Registered {args.browser}: {manifest}")
