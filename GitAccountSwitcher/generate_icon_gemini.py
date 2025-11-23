#!/usr/bin/env python3
"""
Generate Git Account Switcher icon using Gemini AI
"""

import os
import sys
from pathlib import Path

# Find API key from skill directory
skill_env = Path(__file__).parent.parent / '.claude/skills/gemini-image-gen/.env'
if skill_env.exists():
    with open(skill_env) as f:
        for line in f:
            if line.startswith('GEMINI_API_KEY='):
                os.environ['GEMINI_API_KEY'] = line.strip().split('=', 1)[1].strip('"\'')
                break

try:
    from google import genai
    from google.genai import types
except ImportError:
    print("Installing google-genai...")
    os.system(f"{sys.executable} -m pip install google-genai")
    from google import genai
    from google.genai import types

def main():
    api_key = os.getenv('GEMINI_API_KEY')
    if not api_key:
        print("Error: GEMINI_API_KEY not found")
        sys.exit(1)

    print("Initializing Gemini client...")
    client = genai.Client(api_key=api_key)

    prompt = """Create a minimalist macOS app icon for a "Git Account Switcher" application.

Design requirements:
- A stylized cat silhouette (inspired by GitHub's Octocat) in dark charcoal gray (#24292f) in the center
- The cat should be simple and iconic, with recognizable pointed ears
- Two curved arrows encircling the cat figure representing "switching":
  - One arrow in bright green (#2ea043) curving on the right side, pointing clockwise
  - One arrow in bright blue (#2f81f7) curving on the left side, pointing counterclockwise
- The arrows should have clean, modern arrowheads
- CRITICAL: The background MUST be completely transparent (alpha channel = 0)
- No background color, no gradient background - pure transparency
- Clean vector-style flat design
- Square 1:1 aspect ratio suitable for app icons
- High contrast, professional quality
- Modern, minimal aesthetic"""

    print("Generating icon with Gemini 2.5 Flash...")
    print(f"Prompt: {prompt[:100]}...")

    try:
        response = client.models.generate_content(
            model='gemini-2.5-flash-image',
            contents=prompt,
            config=types.GenerateContentConfig(
                response_modalities=['image']
            )
        )

        # Save generated image
        output_dir = Path(__file__).parent
        for i, part in enumerate(response.candidates[0].content.parts):
            if hasattr(part, 'inline_data') and part.inline_data:
                output_path = output_dir / 'AppIcon_AI.png'
                with open(output_path, 'wb') as f:
                    f.write(part.inline_data.data)
                print(f"✓ Saved: {output_path}")
                return str(output_path)

        print("No image generated in response")
        if response.candidates[0].content.parts:
            for part in response.candidates[0].content.parts:
                if hasattr(part, 'text'):
                    print(f"Text response: {part.text}")
        return None

    except Exception as e:
        print(f"Error: {e}")
        return None

if __name__ == '__main__':
    main()
