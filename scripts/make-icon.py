"""Draws Verbatim's app icon (Support/AppIcon.icns): ink waveform bars on warm
paper turning into lines of text, the same idea as the start screen.
Run: python3 scripts/make-icon.py  (needs Pillow). Re-run if the design changes."""
from PIL import Image, ImageDraw
import os

S = 4  # draw big, scale down for smooth edges
W = 1024 * S
PAPER, INK, LINE = (252, 251, 248), (31, 29, 26), (196, 191, 182)

img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
# macOS icon grid: 824 px rounded square centred in 1024, radius ~185.
m, r = 100 * S, 185 * S
d.rounded_rectangle([m, m, W - m, W - m], r, fill=PAPER)

cy = W // 2
bar_w, gap = 26 * S, 22 * S
heights = [40, 120, 230, 330, 210, 280, 150, 70]
lines = [(200, -110), (240, 0), (150, 110)]
total = len(heights) * bar_w // S + (len(heights) - 1) * gap // S + 40 + max(l for l, _ in lines)
x = (1024 - total) // 2 * S
for h in heights:
    h *= S
    d.rounded_rectangle([x, cy - h // 2, x + bar_w, cy + h // 2], bar_w // 2, fill=INK)
    x += bar_w + gap
# words: three lines of "text" on the right
x0 = x - gap + 40 * S
for i, (length, y) in enumerate(lines):
    y = cy + y * S
    t = 26 * S
    d.rounded_rectangle([x0, y - t // 2, x0 + length * S, y + t // 2], t // 2, fill=INK if i < 2 else LINE)

icon = img.resize((1024, 1024), Image.LANCZOS)
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
icon.save(os.path.join(root, "Support", "AppIcon.png"))
icon.save(os.path.join(root, "Support", "AppIcon.icns"),
          sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
print("wrote Support/AppIcon.icns")
