#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""AntiDot uygulama simgesini (1024x1024) üretir."""
from pathlib import Path
from PIL import Image, ImageDraw

S = 1024
out = Path(__file__).resolve().parent.parent / "AntiDot/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
img = Image.new("RGB", (S, S))
d = ImageDraw.Draw(img)
top, bottom = (16, 120, 110), (8, 48, 72)
for y in range(S):
    t = y / S
    d.line([(0, y), (S, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
# Kalkan
shield = [(512, 170), (800, 280), (780, 560), (512, 860), (244, 560), (224, 280)]
d.polygon(shield, fill=(240, 250, 248))
# Üstü çizili nokta (anti-"dot")
d.ellipse([402, 400, 622, 620], outline=(16, 120, 110), width=46)
d.line([(370, 670), (654, 350)], fill=(16, 120, 110), width=46)
img.save(out)
print(out)
