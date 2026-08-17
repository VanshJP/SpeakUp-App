#!/usr/bin/env python3
"""
Creative App Store slide composer for Big Talk.

Renders 1290x2796 slides on a graphite ground with a per-slide accent glow,
matching the app's own "colour only in data" language: each slide's accent is
the colour that screen already uses for its data, so the set reads as one
system without repeating a flat backdrop.

Uses the device frame asset from the aso-appstore-screenshots skill.
"""

import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

# iPhone 6.5" slot. App Store Connect rejects anything that is not an exact
# match for the display size it is uploaded under.
CANVAS_W, CANVAS_H = 1242, 2688

# The whole device sits on the canvas, so its screen is sized to the capture's
# own aspect (1320x2868) rather than the skill's deliberately over-tall bleed
# frame. Height leaves room for a two-line headline and a two-line subhead.
BEZEL = 13
SCREEN_H = 1900
SCREEN_W = round(SCREEN_H * 1320 / 2868)
DEVICE_W = SCREEN_W + 2 * BEZEL
DEVICE_H = SCREEN_H + 2 * BEZEL
DEVICE_Y = 700
DEVICE_CORNER_R = 76
SCREEN_CORNER_R = 62
FONT_BLACK = "/Library/Fonts/SF-Pro-Display-Black.otf"
FONT_MED = "/Library/Fonts/SF-Pro-Display-Medium.otf"

GRAPHITE = (14, 18, 24)


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


def _screen(a, b):
    """Screen blend — lifts the glow without washing the graphite to grey."""
    from PIL import ImageChops
    return ImageChops.screen(a, b)


def rings(canvas, accent):
    layer = Image.new("RGB", (CANVAS_W, CANVAS_H), (0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = CANVAS_W // 2, 430
    for r in range(300, 720, 70):
        d.ellipse([cx - r, cy - r, cx + r, cy + r],
                  outline=tuple(int(c * 0.13) for c in accent), width=3)
    layer = layer.filter(ImageFilter.GaussianBlur(2))
    return _screen(canvas, layer)


def fit(text, max_w, size_max, size_min, path=FONT_BLACK):
    probe = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    for size in range(size_max, size_min - 1, -3):
        f = ImageFont.truetype(path, size)
        if probe.textlength(text, font=f) <= max_w:
            return f
    return ImageFont.truetype(path, size_min)


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


def compose(accent_hex, headline, sub, shot_path, out_path, shot_offset=0):
    accent = hex_rgb(accent_hex)

    canvas = gradient(accent).convert("RGB")
    canvas = rings(canvas, accent)
    canvas = _screen(canvas, _bloom(accent))
    canvas = canvas.convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    # Headline — wraps at 84% so it never crowds the edges.
    max_w = int(CANVAS_W * 0.84)
    h_font = fit(headline, max_w, 116, 84)
    lines = wrap(draw, headline, h_font, max_w)
    y = 175
    for line in lines:
        bb = draw.textbbox((0, 0), line, font=h_font)
        draw.text((CANVAS_W // 2, y - bb[1]), line, font=h_font, fill="white", anchor="mt")
        y += (bb[3] - bb[1]) + 22

    # Accent rule between headline and subhead.
    y += 18
    draw.rounded_rectangle([CANVAS_W // 2 - 54, y, CANVAS_W // 2 + 54, y + 8], radius=4, fill=accent)
    y += 46

    s_font = ImageFont.truetype(FONT_MED, 50)
    for line in wrap(draw, sub, s_font, max_w):
        bb = draw.textbbox((0, 0), line, font=s_font)
        draw.text((CANVAS_W // 2, y - bb[1]), line, font=s_font, fill=(168, 180, 196), anchor="mt")
        y += (bb[3] - bb[1]) + 16

    # Device — whole phone on canvas, entire screen visible.
    dx = (CANVAS_W - DEVICE_W) // 2
    sx, sy = dx + BEZEL, DEVICE_Y + BEZEL

    canvas = Image.alpha_composite(canvas, _shadow(dx, DEVICE_Y))

    body = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    bd = ImageDraw.Draw(body)
    bd.rounded_rectangle([dx, DEVICE_Y, dx + DEVICE_W, DEVICE_Y + DEVICE_H],
                         radius=DEVICE_CORNER_R, fill=(26, 27, 30, 255))
    bd.rounded_rectangle([dx, DEVICE_Y, dx + DEVICE_W, DEVICE_Y + DEVICE_H],
                         radius=DEVICE_CORNER_R, outline=(78, 82, 90, 255), width=3)
    canvas = Image.alpha_composite(canvas, body)

    # The capture fills the screen exactly; a shot_offset crops a band off its
    # top for screens where the translucent nav bar overlaps scrolled content.
    shot = Image.open(shot_path).convert("RGBA")
    if shot_offset:
        shot = shot.crop((0, shot_offset, shot.width, shot.height))
    shot = shot.resize((SCREEN_W, SCREEN_H), Image.LANCZOS)

    mask = Image.new("L", canvas.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [sx, sy, sx + SCREEN_W, sy + SCREEN_H], radius=SCREEN_CORNER_R, fill=255)

    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    layer.paste(shot, (sx, sy))
    layer.putalpha(mask)
    canvas = Image.alpha_composite(canvas, layer)

    # No Dynamic Island is drawn here — the simulator capture already contains
    # one, and painting a second produced a wide black blob across the notch.

    canvas.convert("RGB").save(out_path)
    print(f"✓ {out_path}")


def _shadow(dx, dy):
    """Soft drop shadow so the device sits above the ground, not on it."""
    layer = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(
        [dx + 10, dy + 26, dx + DEVICE_W - 10, dy + DEVICE_H + 30],
        radius=DEVICE_CORNER_R, fill=(0, 0, 0, 150))
    return layer.filter(ImageFilter.GaussianBlur(38))


def _bloom(accent):
    layer = Image.new("RGB", (CANVAS_W, CANVAS_H), (0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = CANVAS_W // 2, DEVICE_Y + 180
    d.ellipse([cx - 640, cy - 480, cx + 640, cy + 380],
              fill=tuple(int(c * 0.38) for c in accent))
    return layer.filter(ImageFilter.GaussianBlur(200))


SLIDES = [
    ("#0FB3AE", "Practice Public Speaking",
     "Build confidence with feedback on clarity, pace & more",
     "01-breakdown.png", "01-practice.png", 0),
    ("#E8A33D", "Stop Saying “Um” & “Like”",
     "Catch filler words and speak with more confidence",
     "02-transcript.png", "02-fillers.png", 560),
    ("#E4587A", "Practice Speeches & Interviews",
     "Rehearse presentations, pitches, toasts & more",
     "04-story.png", "03-speeches.png", 0),
    ("#7C6CF0", "430 Public Speaking Prompts",
     "Always know what to say next",
     "10-prompts.png", "04-prompts.png", 0),
    ("#0FB3AE", "Build Speaking Confidence Daily",
     "Short, focused practice that adds up",
     "00-today.png", "05-daily.png", 0),
    ("#34C77B", "Track Your Speaking Progress",
     "See your scores improve over time",
     "05-progress.png", "06-progress.png", 0),
    ("#3D7DF6", "Private AI Speech Coaching",
     "Your voice stays on your iPhone",
     "11-ondevice.png", "07-private.png", 0),
]

if __name__ == "__main__":
    src = os.path.expanduser("~/SpeakUp/simulator-screenshots")
    dst = os.path.expanduser("~/SpeakUp/screenshots/final")
    os.makedirs(dst, exist_ok=True)
    for accent, head, sub, shot, out, offset in SLIDES:
        compose(accent, head, sub, os.path.join(src, shot),
                os.path.join(dst, out), shot_offset=offset)
