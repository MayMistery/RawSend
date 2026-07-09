#!/usr/bin/env python3
"""Generate RawSend app icon PNGs at multiple sizes for macOS .icns creation."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SCRIPT_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SCRIPT_DIR / "AppIcon.iconset"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


def create_icon(size):
    """Create a single icon at the given size."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    scale = size / 512.0
    
    # --- Draw rounded rectangle background with gradient ---
    # Create gradient background
    for y in range(size):
        # Gradient from #1a1a2e (top-left) to #16213e (bottom-right)
        t = y / max(size - 1, 1)
        r = int(26 + (22 - 26) * t)
        g = int(26 + (33 - 26) * t)
        b = int(46 + (62 - 46) * t)
        draw.line([(0, y), (size - 1, y)], fill=(r, g, b, 255))
    
    # Create a rounded rect mask (squircle approximation)
    mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    margin = int(12 * scale)
    radius = int(110 * scale)
    mask_draw.rounded_rectangle(
        [margin, margin, size - margin - 1, size - margin - 1],
        radius=radius,
        fill=255
    )
    
    # Apply mask to make squircle shape
    bg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    img.putalpha(mask)
    bg.paste(img, (0, 0), img)
    img = bg
    draw = ImageDraw.Draw(img)
    
    # --- Draw subtle border glow ---
    border_color = (79, 195, 247, 38)  # #4fc3f7 at 15% opacity
    draw.rounded_rectangle(
        [int(12 * scale), int(12 * scale), 
         size - int(12 * scale) - 1, size - int(12 * scale) - 1],
        radius=radius,
        outline=border_color,
        width=max(1, int(2 * scale))
    )
    
    # --- Draw motion trail lines ---
    trail_color = (79, 195, 247, 160)
    trail_width = max(1, int(3 * scale))
    draw.line(
        [(int(100 * scale), int(320 * scale)), (int(220 * scale), int(260 * scale))],
        fill=trail_color, width=trail_width
    )
    trail_color2 = (79, 195, 247, 100)
    draw.line(
        [(int(120 * scale), int(350 * scale)), (int(200 * scale), int(310 * scale))],
        fill=trail_color2, width=max(1, int(2 * scale))
    )
    trail_color3 = (79, 195, 247, 65)
    draw.line(
        [(int(140 * scale), int(375 * scale)), (int(210 * scale), int(345 * scale))],
        fill=trail_color3, width=max(1, int(2 * scale))
    )
    
    # --- Draw paper plane ---
    # Main body triangle (white to light blue)
    plane_points1 = [
        (int(380 * scale), int(140 * scale)),
        (int(160 * scale), int(240 * scale)),
        (int(220 * scale), int(270 * scale)),
    ]
    draw.polygon(plane_points1, fill=(255, 255, 255, 242))
    
    # Bottom wing
    plane_points2 = [
        (int(380 * scale), int(140 * scale)),
        (int(220 * scale), int(270 * scale)),
        (int(250 * scale), int(340 * scale)),
    ]
    draw.polygon(plane_points2, fill=(168, 216, 255, 217))
    
    # Shadow fold
    plane_points3 = [
        (int(220 * scale), int(270 * scale)),
        (int(250 * scale), int(340 * scale)),
        (int(240 * scale), int(285 * scale)),
    ]
    draw.polygon(plane_points3, fill=(123, 184, 224, 178))
    
    # --- Draw code symbols and text ---
    # Only draw text elements on larger icons where they'll be legible
    if size >= 64:
        try:
            font_size = max(10, int(48 * scale))
            text_font_size = max(8, int(28 * scale))
            # Try to use a monospace font
            try:
                font = ImageFont.truetype("/System/Library/Fonts/SFNSMono.ttf", font_size)
                text_font = ImageFont.truetype("/System/Library/Fonts/SFNSMono.ttf", text_font_size)
            except (OSError, IOError):
                try:
                    font = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", font_size)
                    text_font = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", text_font_size)
                except (OSError, IOError):
                    font = ImageFont.load_default()
                    text_font = font
            
            brace_color = (79, 195, 247, 178)
            # Left brace "{"
            draw.text((int(130 * scale), int(395 * scale)), "{", fill=brace_color, font=font)
            # Right brace "}"
            draw.text((int(350 * scale), int(395 * scale)), "}", fill=brace_color, font=font)
            
            # "HTTP" text
            http_color = (79, 195, 247, 140)
            draw.text((int(195 * scale), int(405 * scale)), "HTTP", fill=http_color, font=text_font)
        except Exception:
            pass  # Skip text if fonts fail
    
    # --- Small send arrow indicator ---
    arrow_points = [
        (int(240 * scale), int(420 * scale)),
        (int(280 * scale), int(410 * scale)),
        (int(270 * scale), int(430 * scale)),
    ]
    if size >= 64:
        draw.polygon(arrow_points, fill=(79, 195, 247, 127))
    
    return img


# macOS .iconset requires specific filenames
icon_sizes = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}

for filename, size in icon_sizes.items():
    icon = create_icon(size)
    output_path = OUTPUT_DIR / filename
    icon.save(output_path, "PNG")
    print(f"Generated: {filename} ({size}x{size})")

print(f"\nAll icons generated in: {OUTPUT_DIR}")
print("Ready for: iconutil -c icns AppIcon.iconset")
