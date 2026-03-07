from io import BytesIO
from PIL import Image
from .screenai import ScreenAiOcr
import json
import subprocess
import sys
import time

ocr = ScreenAiOcr()

captures = {}

def scan(x, y, w, h, X, Y, monitor, japanese):
    grim_result = subprocess.run(
        ["grim", "-g", f"{x},{y} {w}x{h}", "-"],
        capture_output=True,
        stdin=subprocess.DEVNULL
    )
    if grim_result.returncode != 0:
        print('{"unchanged":true}\0', flush=True)
        return
    if grim_result.stdout == captures.get(monitor):
        print('{"unchanged":true}\0', flush=True)
        return
    captures[monitor] = grim_result.stdout

    image = Image.open(BytesIO(grim_result.stdout))
    text = ocr.scan(image, (X, Y, w, h), japanese)

    j = json.dumps({ "lines": text, "monitor": monitor, "region": { "x": x, "y": y, "w": w, "h": h, "X": X, "Y": Y } }, ensure_ascii=False)
    print(j)
    print('\0', flush=True)

for line in sys.stdin:
    line = line.strip()
    parts = line.split()
    if len(parts) < 1:
        continue
    if parts[0] == "rescan":
        if len(parts) < 9:
            continue

        japanese = parts[1].lower() == "true"
        x, y, w, h, X, Y = map(int, parts[2:8])
        monitor = parts[8]
        scan(x, y, w, h, X, Y, monitor, japanese)

    elif parts[0] == "scan":
        fullscreen = False
        if len(parts) < 2:
            continue
        japanese = parts[1].lower() == "true"
        if len(parts) >= 3:
            fullscreen = parts[2].lower() == "true"

        slurp_result = subprocess.run(
            ["slurp"] + (["-o"] if fullscreen else []) + ["-f", "%x %y %w %h %X %Y %o"],
            capture_output=True,
            stdin=subprocess.DEVNULL
        )

        if slurp_result.returncode != 0:
            continue

        slurp_output = slurp_result.stdout.strip().split()
        x, y, w, h, X, Y = map(int, slurp_output[:6])
        monitor = slurp_output[6].decode()
        scan(x, y, w, h, X, Y, monitor, japanese)
