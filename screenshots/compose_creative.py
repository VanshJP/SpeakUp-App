#!/usr/bin/env python3
"""
App Store slide composer for Big Talk.

Renders the 6.9" iPhone slot (1320x2868) on a graphite ground with a per-slide
accent glow, matching the app's own "colour only in data" language: each slide's
accent is the colour that screen already uses for its data, so the set reads as
one system without repeating a flat backdrop.

6.9" is the only iPhone size App Store Connect requires — it scales that set
down for every smaller device — so there is nothing else to export.

    python3 screenshots/compose_creative.py

Reads raw captures from simulator-screenshots/, writes screenshots/final/.
Needs SF Pro Display Black + Medium in /Library/Fonts/ and Pillow.
"""

import os
import sys
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

# iPhone 6.9". App Store Connect rejects anything that is not an exact match
# for the display size it is uploaded under.
CANVAS_W, CANVAS_H = 1320, 2868

# Captures come off a 6.9" simulator, so a shot fills the drawn screen exactly.
# Anything else would have to be squashed to fit, so it is rejected instead.
NATIVE_W, NATIVE_H = 1320, 2868

BEZEL = 15
DEVICE_Y = 530
DEVICE_H = CANVAS_H - 46 - DEVICE_Y
SCREEN_H = DEVICE_H - 2 * BEZEL
SCREEN_W = round(SCREEN_H * NATIVE_W / NATIVE_H)
DEVICE_W = SCREEN_W + 2 * BEZEL
DEVICE_X = (CANVAS_W - DEVICE_W) // 2
DEVICE_CORNER_R = 91
SCREEN_CORNER_R = 75

# The text sits in a fixed slot and is centred inside it, so a slide whose
# headline wraps to two lines still puts the device at the same y as every
# other slide. A carousel where the phone jumps between swipes reads as broken.
TEXT_TOP, TEXT_BOTTOM = 170, 470
TEXT_MAX_W = int(CANVAS_W * 0.86)

FONT_BLACK = "/Library/Fonts/SF-Pro-Display-Black.otf"
FONT_MED = "/Library/Fonts/SF-Pro-Display-Medium.otf"

GRAPHITE = (14, 18, 24)
SUBHEAD_GREY = (168, 180, 196)


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def gradient(accent):
    """Vertical wash: accent-tinted at the top, graphite by mid-canvas."""
    base = Image.new("RGB", (1, CANVAS_H))
    px = base.load()
    top = tuple(int(GRAPHITE[i] + (accent[i] - GRAPHITE[i]) * 0.24) for i in range(3))
    for y in range(CANVAS_H):
        t = min(1.0, (y / CANVAS_H) * 1.9)
        px[0, y] = tuple(int(top[i] + (GRAPHITE[i] - top[i]) * t) for i in range(3))
    return base.resize((CANVAS_W, CANVAS_H))


def rings(accent):
    layer = Image.new("RGB", (CANVAS_W, CANVAS_H), (0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = CANVAS_W // 2, 360
    for r in range(320, 780, 74):
        d.ellipse([cx - r, cy - r, cx + r, cy + r],
                  outline=tuple(int(c * 0.13) for c in accent), width=3)
    return layer.filter(ImageFilter.GaussianBlur(2))


def bloom(accent):
    """Glow behind the device, so the phone reads as lit rather than pasted on."""
    layer = Image.new("RGB", (CANVAS_W, CANVAS_H), (0, 0, 0))
    cx, cy = CANVAS_W // 2, DEVICE_Y + 190
    ImageDraw.Draw(layer).ellipse(
        [cx - 680, cy - 510, cx + 680, cy + 400],
        fill=tuple(int(c * 0.38) for c in accent))
    return layer.filter(ImageFilter.GaussianBlur(200))


def shadow():
    layer = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(
        [DEVICE_X + 12, DEVICE_Y + 28, DEVICE_X + DEVICE_W - 12, DEVICE_Y + DEVICE_H + 32],
        radius=DEVICE_CORNER_R, fill=(0, 0, 0, 150))
    return layer.filter(ImageFilter.GaussianBlur(40))


def wrap(draw, text, font, max_w):
    lines, cur = [], ""
    for w in text.split():
        t = f"{cur} {w}".strip()
        if draw.textlength(t, font=font) <= max_w:
            cur = t
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def fit_headline(draw, text):
    """Largest size that keeps the headline on one line.

    One line every time is the point: each headline then fills the same
    measure, so the sizes reading 92-100 across the set look deliberate rather
    than uneven. Copy that cannot make the floor wraps instead — treat that as
    a signal to shorten the copy, not to accept a smaller headline.
    """
    for size in range(110, 77, -2):
        font = ImageFont.truetype(FONT_BLACK, size)
        if draw.textlength(text, font=font) <= TEXT_MAX_W:
            return font, [text]
    font = ImageFont.truetype(FONT_BLACK, 78)
    return font, wrap(draw, text, font, TEXT_MAX_W)


def _block(draw, headline, sub):
    """Lay the text out as (y_offset, text, font) rows plus a rule marker."""
    h_font, h_lines = fit_headline(draw, headline)
    s_font = ImageFont.truetype(FONT_MED, 52)
    s_lines = wrap(draw, sub, s_font, TEXT_MAX_W)

    rows, y = [], 0
    for line in h_lines:
        bb = draw.textbbox((0, 0), line, font=h_font)
        rows.append((y - bb[1], line, h_font))
        y += (bb[3] - bb[1]) + 24
    y += 20
    rows.append((y, None, None))          # accent rule
    y += 9 + 46
    for line in s_lines:
        bb = draw.textbbox((0, 0), line, font=s_font)
        rows.append((y - bb[1], line, s_font))
        y += (bb[3] - bb[1]) + 16
    return rows, y - 16


def compose(accent_hex, headline, sub, shot_path, out_path):
    accent = hex_rgb(accent_hex)

    shot = Image.open(shot_path).convert("RGBA")
    if shot.size != (NATIVE_W, NATIVE_H):
        raise SystemExit(
            f"{os.path.basename(shot_path)} is {shot.width}x{shot.height}; "
            f"expected {NATIVE_W}x{NATIVE_H}. Re-capture on a 6.9\" simulator "
            f"(iPhone 17 Pro Max) rather than scaling — scaling squashes the UI.")

    canvas = gradient(accent).convert("RGB")
    canvas = ImageChops.screen(canvas, rings(accent))
    canvas = ImageChops.screen(canvas, bloom(accent))
    canvas = canvas.convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    rows, height = _block(draw, headline, sub)
    top = TEXT_TOP + ((TEXT_BOTTOM - TEXT_TOP) - height) // 2
    for dy, text, font in rows:
        if text is None:
            draw.rounded_rectangle(
                [CANVAS_W // 2 - 58, top + dy, CANVAS_W // 2 + 58, top + dy + 9],
                radius=5, fill=accent)
        else:
            draw.text((CANVAS_W // 2, top + dy), text, font=font,
                      fill="white" if font.path == FONT_BLACK else SUBHEAD_GREY,
                      anchor="mt")

    canvas = Image.alpha_composite(canvas, shadow())

    body = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    bd = ImageDraw.Draw(body)
    bd.rounded_rectangle([DEVICE_X, DEVICE_Y, DEVICE_X + DEVICE_W, DEVICE_Y + DEVICE_H],
                         radius=DEVICE_CORNER_R, fill=(26, 27, 30, 255))
    bd.rounded_rectangle([DEVICE_X, DEVICE_Y, DEVICE_X + DEVICE_W, DEVICE_Y + DEVICE_H],
                         radius=DEVICE_CORNER_R, outline=(84, 89, 98, 255), width=3)
    canvas = Image.alpha_composite(canvas, body)

    sx, sy = DEVICE_X + BEZEL, DEVICE_Y + BEZEL
    mask = Image.new("L", canvas.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [sx, sy, sx + SCREEN_W, sy + SCREEN_H], radius=SCREEN_CORNER_R, fill=255)

    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    layer.paste(shot.resize((SCREEN_W, SCREEN_H), Image.LANCZOS), (sx, sy))
    layer.putalpha(mask)
    canvas = Image.alpha_composite(canvas, layer)

    # No Dynamic Island is drawn — the capture already contains one, and
    # painting a second produced a wide black blob across the notch.
    canvas.convert("RGB").save(out_path)
    print(f"✓ {out_path}")


# Headline copy is conversion copy only — screenshot text is not indexed by
# App Store search — so it is written for the person already on the page.
SLIDES = [
    ("#0FB3AE", "Practice Public Speaking",
     "Feedback on pace, clarity and fillers",
     "01-breakdown.png", "01-practice.png"),
    ("#E8A33D", "Stop Saying Um and Like",
     "Every filler marked where you said it",
     "02-transcript.png", "02-fillers.png"),
    ("#E4587A", "Rehearse Your Speech",
     "Toasts, interviews, pitches, presentations",
     "04-story.png", "03-speeches.png"),
    ("#7C6CF0", "430 Speaking Prompts",
     "Always know what to say next",
     "10-prompts.png", "04-prompts.png"),
    ("#0FB3AE", "Practice a Minute a Day",
     "Short sessions that actually add up",
     "00-today.png", "05-daily.png"),
    ("#34C77B", "Watch Your Scores Rise",
     "Every metric charted over time",
     "05-progress.png", "06-progress.png"),
    # Deliberately not "AI speech coaching" — APP_STORE_LISTING.md section 6
    # rules that claim out, and the privacy line converts better anyway.
    ("#3D7DF6", "It Stays On Your iPhone",
     "No account, no upload, no server",
     "11-ondevice.png", "07-private.png"),
]

if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    src = os.path.join(root, "simulator-screenshots")
    dst = os.path.join(root, "screenshots", "final")
    os.makedirs(dst, exist_ok=True)
    for accent, head, sub, shot, out in SLIDES:
        path = os.path.join(src, shot)
        if not os.path.exists(path):
            sys.exit(f"missing capture: {path}")
        compose(accent, head, sub, path, os.path.join(dst, out))
