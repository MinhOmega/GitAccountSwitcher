#!/usr/bin/env python3
"""
Git Account Switcher - Transparent Background Icon
Clean, modern icon with GitHub octocat and switching arrows on transparent background
"""

from PIL import Image, ImageDraw, ImageFilter
import math
import os


def create_icon(size):
    """Create a transparent background icon with GitHub octocat and switching arrows"""

    # Create base image with full transparency
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    cx, cy = size // 2, size // 2
    scale = size / 1024

    # GitHub colors
    github_dark = (36, 41, 47, 255)      # #24292f - GitHub dark gray
    github_green = (46, 160, 67, 255)     # #2ea043 - GitHub green
    github_blue = (47, 129, 247, 255)     # #2f81f7 - GitHub blue

    # Step 1: Draw the octocat silhouette (GitHub mark style)
    head_radius = int(140 * scale)
    head_cx = cx
    head_cy = cy - int(10 * scale)

    # Main head circle - dark gray
    draw.ellipse([
        head_cx - head_radius, head_cy - head_radius,
        head_cx + head_radius, head_cy + head_radius
    ], fill=github_dark)

    # Cat ears
    ear_height = int(50 * scale)
    ear_width = int(45 * scale)

    # Left ear
    left_ear = [
        (head_cx - head_radius + int(25 * scale), head_cy - head_radius + int(35 * scale)),
        (head_cx - head_radius + int(50 * scale), head_cy - head_radius - ear_height),
        (head_cx - head_radius + int(80 * scale), head_cy - head_radius + int(25 * scale)),
    ]
    draw.polygon(left_ear, fill=github_dark)

    # Right ear
    right_ear = [
        (head_cx + head_radius - int(25 * scale), head_cy - head_radius + int(35 * scale)),
        (head_cx + head_radius - int(50 * scale), head_cy - head_radius - ear_height),
        (head_cx + head_radius - int(80 * scale), head_cy - head_radius + int(25 * scale)),
    ]
    draw.polygon(right_ear, fill=github_dark)

    # Body (rounded bottom)
    body_w = int(100 * scale)
    body_h = int(70 * scale)
    body_top = head_cy + head_radius - int(20 * scale)
    draw.ellipse([
        head_cx - body_w, body_top,
        head_cx + body_w, body_top + body_h * 2
    ], fill=github_dark)

    # Step 2: Draw face - white elements
    white = (255, 255, 255, 255)

    # Eyes - white circles
    eye_radius = int(28 * scale)
    eye_y = head_cy + int(10 * scale)
    eye_spacing = int(60 * scale)

    # Left eye
    draw.ellipse([
        head_cx - eye_spacing - eye_radius, eye_y - eye_radius,
        head_cx - eye_spacing + eye_radius, eye_y + eye_radius
    ], fill=white)

    # Right eye
    draw.ellipse([
        head_cx + eye_spacing - eye_radius, eye_y - eye_radius,
        head_cx + eye_spacing + eye_radius, eye_y + eye_radius
    ], fill=white)

    # Pupils - small dark circles
    pupil_radius = int(10 * scale)
    pupil_offset_x = int(5 * scale)
    pupil_offset_y = int(3 * scale)

    # Left pupil
    draw.ellipse([
        head_cx - eye_spacing + pupil_offset_x - pupil_radius,
        eye_y + pupil_offset_y - pupil_radius,
        head_cx - eye_spacing + pupil_offset_x + pupil_radius,
        eye_y + pupil_offset_y + pupil_radius
    ], fill=github_dark)

    # Right pupil
    draw.ellipse([
        head_cx + eye_spacing + pupil_offset_x - pupil_radius,
        eye_y + pupil_offset_y - pupil_radius,
        head_cx + eye_spacing + pupil_offset_x + pupil_radius,
        eye_y + pupil_offset_y + pupil_radius
    ], fill=github_dark)

    # Eye highlights
    highlight_r = int(6 * scale)
    draw.ellipse([
        head_cx - eye_spacing - int(8 * scale) - highlight_r,
        eye_y - int(8 * scale) - highlight_r,
        head_cx - eye_spacing - int(8 * scale) + highlight_r,
        eye_y - int(8 * scale) + highlight_r
    ], fill=white)

    draw.ellipse([
        head_cx + eye_spacing - int(8 * scale) - highlight_r,
        eye_y - int(8 * scale) - highlight_r,
        head_cx + eye_spacing - int(8 * scale) + highlight_r,
        eye_y - int(8 * scale) + highlight_r
    ], fill=white)

    # Step 3: Draw switching arrows around the octocat
    arc_radius = int(220 * scale)
    arc_width = int(26 * scale)

    # Green arc (top-right, clockwise) - "switch to"
    for angle in range(-70, 30, 1):
        rad = math.radians(angle)
        x = cx + arc_radius * math.cos(rad)
        y = cy + arc_radius * math.sin(rad)

        # Gradient effect
        t = (angle + 70) / 100
        r = int(46 - 10 * t)
        g = int(160 + 20 * (1 - t))
        b = int(67 + 30 * (1 - t))

        w = arc_width // 2
        draw.ellipse([x - w, y - w, x + w, y + w], fill=(r, g, b, 255))

    # Blue arc (bottom-left, counterclockwise) - "switch from"
    for angle in range(110, 210, 1):
        rad = math.radians(angle)
        x = cx + arc_radius * math.cos(rad)
        y = cy + arc_radius * math.sin(rad)

        t = (angle - 110) / 100
        r = int(47 + 20 * (1 - t))
        g = int(129 + 30 * (1 - t))
        b = int(247 - 20 * t)

        w = arc_width // 2
        draw.ellipse([x - w, y - w, x + w, y + w], fill=(r, g, b, 255))

    # Arrowheads
    arrow_size = int(45 * scale)

    # Green arrowhead
    angle1 = math.radians(30)
    ax1 = cx + arc_radius * math.cos(angle1)
    ay1 = cy + arc_radius * math.sin(angle1)

    tip_angle1 = math.radians(30 + 90)
    points1 = []
    for i, offset in enumerate([0, 135, 225]):
        a = tip_angle1 + math.radians(offset)
        dist = arrow_size if i == 0 else arrow_size * 0.55
        px = ax1 + dist * math.cos(a)
        py = ay1 + dist * math.sin(a)
        points1.append((px, py))
    draw.polygon(points1, fill=github_green)

    # Blue arrowhead
    angle2 = math.radians(210)
    ax2 = cx + arc_radius * math.cos(angle2)
    ay2 = cy + arc_radius * math.sin(angle2)

    tip_angle2 = math.radians(210 + 90)
    points2 = []
    for i, offset in enumerate([0, 135, 225]):
        a = tip_angle2 + math.radians(offset)
        dist = arrow_size if i == 0 else arrow_size * 0.55
        px = ax2 + dist * math.cos(a)
        py = ay2 + dist * math.sin(a)
        points2.append((px, py))
    draw.polygon(points2, fill=github_blue)

    return img


def apply_macos_rounding(img, size):
    """Apply macOS-style continuous corners (squircle) - keeps transparency"""
    # Create mask with rounded corners
    mask = Image.new('L', (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)

    # macOS uses ~22.37% corner radius
    corner_radius = int(size * 0.2237)
    mask_draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=corner_radius, fill=255)

    # Apply mask to alpha channel
    r, g, b, a = img.split()
    # Combine existing alpha with the rounded mask
    new_alpha = Image.new('L', (size, size), 0)
    for y in range(size):
        for x in range(size):
            orig_alpha = a.getpixel((x, y))
            mask_alpha = mask.getpixel((x, y))
            # Keep original alpha but clip to mask
            new_alpha.putpixel((x, y), min(orig_alpha, mask_alpha))

    img.putalpha(new_alpha)
    return img


def main():
    """Generate all required icon sizes"""
    sizes_1x = [16, 32, 128, 256, 512]

    output_dir = os.path.dirname(os.path.abspath(__file__))
    assets_dir = os.path.join(output_dir, 'GitAccountSwitcher', 'Assets.xcassets', 'AppIcon.appiconset')

    print("Creating transparent Git Account Switcher icon...")

    # Create high-res master at 1024x1024
    master = create_icon(1024)
    master = apply_macos_rounding(master, 1024)
    master.save(os.path.join(output_dir, 'AppIcon.png'), 'PNG')
    print(f"  Saved: AppIcon.png (1024x1024 master)")

    # Generate all sizes for asset catalog
    if os.path.exists(assets_dir):
        for size in sizes_1x:
            # 1x version
            icon = master.resize((size, size), Image.Resampling.LANCZOS)
            filename = f'icon_{size}x{size}.png'
            icon.save(os.path.join(assets_dir, filename), 'PNG')
            print(f"  Saved: {filename}")

            # 2x version
            size_2x = size * 2
            if size_2x <= 1024:
                icon_2x = master.resize((size_2x, size_2x), Image.Resampling.LANCZOS)
                filename_2x = f'icon_{size}x{size}@2x.png'
                icon_2x.save(os.path.join(assets_dir, filename_2x), 'PNG')
                print(f"  Saved: {filename_2x}")

    print("\nTransparent icon generation complete!")
    print(f"Master icon: {os.path.join(output_dir, 'AppIcon.png')}")


if __name__ == '__main__':
    main()
