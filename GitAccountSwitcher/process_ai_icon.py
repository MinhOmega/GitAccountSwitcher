#!/usr/bin/env python3
"""
Process AI-generated icon to make background transparent and generate all sizes
"""

from PIL import Image
import os
from pathlib import Path

def make_transparent(img, tolerance=30):
    """Make white/near-white pixels transparent"""
    img = img.convert('RGBA')
    data = img.getdata()

    new_data = []
    for item in data:
        # Check if pixel is white or near-white
        if item[0] > 255 - tolerance and item[1] > 255 - tolerance and item[2] > 255 - tolerance:
            # Make transparent
            new_data.append((255, 255, 255, 0))
        else:
            new_data.append(item)

    img.putdata(new_data)
    return img

def apply_macos_rounding(img, size):
    """Apply macOS-style continuous corners (squircle)"""
    from PIL import ImageDraw

    mask = Image.new('L', (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)

    # macOS uses ~22.37% corner radius
    corner_radius = int(size * 0.2237)
    mask_draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=corner_radius, fill=255)

    # Apply mask to alpha channel
    r, g, b, a = img.split()
    new_alpha = Image.new('L', (size, size), 0)

    for y in range(size):
        for x in range(size):
            orig_alpha = a.getpixel((x, y))
            mask_alpha = mask.getpixel((x, y))
            new_alpha.putpixel((x, y), min(orig_alpha, mask_alpha))

    img.putalpha(new_alpha)
    return img

def main():
    script_dir = Path(__file__).parent
    ai_icon_path = script_dir / 'AppIcon_AI.png'

    if not ai_icon_path.exists():
        print(f"Error: {ai_icon_path} not found")
        return

    print("Loading AI-generated icon...")
    img = Image.open(ai_icon_path)

    print("Making background transparent...")
    img = make_transparent(img, tolerance=40)

    # Resize to 1024x1024 if needed
    if img.size != (1024, 1024):
        print(f"Resizing from {img.size} to 1024x1024...")
        img = img.resize((1024, 1024), Image.Resampling.LANCZOS)

    # Apply macOS rounding
    print("Applying macOS-style rounding...")
    img = apply_macos_rounding(img, 1024)

    # Save master icon
    master_path = script_dir / 'AppIcon.png'
    img.save(master_path, 'PNG')
    print(f"Saved: {master_path}")

    # Generate sizes for asset catalog
    assets_dir = script_dir / 'GitAccountSwitcher' / 'Assets.xcassets' / 'AppIcon.appiconset'
    if assets_dir.exists():
        sizes_1x = [16, 32, 128, 256, 512]

        for size in sizes_1x:
            # 1x version
            icon = img.resize((size, size), Image.Resampling.LANCZOS)
            filename = f'icon_{size}x{size}.png'
            icon.save(assets_dir / filename, 'PNG')
            print(f"Saved: {filename}")

            # 2x version
            size_2x = size * 2
            if size_2x <= 1024:
                icon_2x = img.resize((size_2x, size_2x), Image.Resampling.LANCZOS)
                filename_2x = f'icon_{size}x{size}@2x.png'
                icon_2x.save(assets_dir / filename_2x, 'PNG')
                print(f"Saved: {filename_2x}")

    print("\nIcon generation complete!")

if __name__ == '__main__':
    main()
