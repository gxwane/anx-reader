# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "pillow>=10.0.0",
#     "numpy>=1.24.0",
# ]
# ///

import os
import math
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import numpy as np

def generate_gx_icons():
    base = Image.open('assets/icon/Anx-logo.png').convert('RGBA')
    w, h = base.size

    orig_np = np.array(base)
    # The book area is white/light (> 180, 180, 180)
    book_mask_np = ((orig_np[:, :, 0] > 180) & (orig_np[:, :, 1] > 180) & (orig_np[:, :, 2] > 180))

    # Badge geometry:
    # Top edge of book at y=414, right edge at x=1677
    cut_x = 1160
    cut_y = 931
    font_size = 170
    text_offset_ratio = 0.47

    dx = 1677 - cut_x
    dy = cut_y - 414

    # Polygon for badge corner
    poly = [(cut_x, 414), (1700, 414), (1700, cut_y + 50), (1677, cut_y)]
    poly_mask = Image.new('L', (w, h), 0)
    ImageDraw.Draw(poly_mask).polygon(poly, fill=255)
    poly_mask_np = np.array(poly_mask) > 0

    combined_mask_np = poly_mask_np & book_mask_np
    combined_mask = Image.fromarray((combined_mask_np.astype(np.uint8) * 255), mode='L')

    # Gradient background for badge
    y_coords, x_coords = np.mgrid[0:h, 0:w]
    t = ((x_coords - cut_x) + (y_coords - 414)) / (dx + dy)
    t = np.clip(t, 0, 1)

    r = (255 * (1 - t * 0.15)).astype(np.uint8)
    g = (95 * (1 - t * 0.55)).astype(np.uint8)
    b = (40 * (1 - t * 0.75)).astype(np.uint8)
    a = np.ones_like(r) * 255

    rgba = np.stack([r, g, b, a], axis=-1)
    badge_bg = Image.fromarray(rgba, mode='RGBA')

    # Calculate center for rotated text
    mid_x = (cut_x + 1677) / 2.0
    mid_y = (414 + cut_y) / 2.0
    vcx = 1677.0 - mid_x
    vcy = 414.0 - mid_y

    center_x = mid_x + vcx * text_offset_ratio
    center_y = mid_y + vcy * text_offset_ratio

    # Render 'GX' text
    font = ImageFont.truetype('C:/Windows/Fonts/ariblk.ttf', font_size)
    temp_size = int(font_size * 5)
    temp_txt = Image.new('RGBA', (temp_size, temp_size), (0, 0, 0, 0))
    temp_draw = ImageDraw.Draw(temp_txt)
    bbox = temp_draw.textbbox((0, 0), 'GX', font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = (temp_size - tw) / 2.0 - bbox[0]
    ty = (temp_size - th) / 2.0 - bbox[1]
    temp_draw.text((tx, ty), 'GX', font=font, fill=(255, 255, 255, 255))

    rotated_txt = temp_txt.rotate(-45, resample=Image.BICUBIC)
    paste_x = int(round(center_x - temp_size / 2.0))
    paste_y = int(round(center_y - temp_size / 2.0))

    full_text_layer = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    full_text_layer.paste(rotated_txt, (paste_x, paste_y))

    # Composite badge layer
    badge_layer = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    badge_layer.paste(badge_bg, (0, 0), mask=combined_mask)

    text_alpha = np.array(full_text_layer.split()[-1])
    final_text_alpha = ((text_alpha > 0) & combined_mask_np).astype(np.uint8) * text_alpha
    text_masked = full_text_layer.copy()
    text_masked.putalpha(Image.fromarray(final_text_alpha, mode='L'))
    badge_layer.alpha_composite(text_masked)

    # Fold inner line
    fold_line = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    fold_draw = ImageDraw.Draw(fold_line)
    fold_draw.line([(cut_x - 1, 414 - 1), (1677 + 1, cut_y + 1)], fill=(255, 255, 255, 160), width=4)
    fold_draw.line([(cut_x - 3, 414 - 3), (1677 + 3, cut_y + 3)], fill=(180, 180, 180, 90), width=3)

    # Master 2000x2000 icon
    master_icon = base.copy()
    master_icon.paste(badge_layer, (0, 0), mask=combined_mask)
    master_icon.alpha_composite(fold_line)
    master_icon_rgb = master_icon.convert('RGB')
    master_icon_rgb.save('assets/icon/Anx-logo-gx-preview.png', 'PNG')
    print('Saved assets/icon/Anx-logo-gx-preview.png')

    # Master foreground for adaptive icon
    # Extract book + badge (transparent outside book)
    # Find background color ~[35, 78, 134]
    # In base image, non-background has book + shadow
    # Let's create foreground by masking master_icon with alpha from book & shadow
    fg_mask_np = ((orig_np[:, :, 0] > 100) | (orig_np[:, :, 1] > 100) | (orig_np[:, :, 2] > 150)).astype(np.uint8) * 255
    # Better yet, load the original foreground shape or create it
    # Scale master_icon down to ~274x274 and center in 432x432
    # In adaptive icon spec: 108dp canvas, 72dp viewport (center 66.6% contains the icon)
    # The book itself in 432x432 should fit in center
    book_crop = master_icon.crop((300, 390, 1700, 1550)) # Book area with shadow
    # Let's make transparent background: replace blue with alpha
    book_np = np.array(book_crop)
    # Blue background condition: r < 60, g < 100, b > 100
    is_bg = (book_np[:, :, 0] < 60) & (book_np[:, :, 1] < 100) & (book_np[:, :, 2] > 100)
    # Book alpha: 255 where not bg, smooth transition
    book_rgba = book_crop.copy()
    alpha_channel = Image.fromarray((~is_bg).astype(np.uint8) * 255, mode='L')
    alpha_channel = alpha_channel.filter(ImageFilter.GaussianBlur(1))
    book_rgba.putalpha(alpha_channel)

    # Create 432x432 master foreground
    fg_432 = Image.new('RGBA', (432, 432), (0, 0, 0, 0))
    # Target book width ~190 in 432
    bw, bh = book_rgba.size
    scale = 190.0 / bw
    scaled_book = book_rgba.resize((int(round(bw * scale)), int(round(bh * scale))), Image.LANCZOS)
    sbw, sbh = scaled_book.size
    fg_432.paste(scaled_book, ((432 - sbw) // 2, (432 - sbh) // 2 + 5), mask=scaled_book.split()[-1])
    fg_432.save('assets/icon/Anx-logo-gx-preview-foreground.png', 'PNG')
    print('Saved assets/icon/Anx-logo-gx-preview-foreground.png')

    # Android mipmaps
    densities = {
        'mdpi': (48, 108),
        'hdpi': (72, 162),
        'xhdpi': (96, 216),
        'xxhdpi': (144, 324),
        'xxxhdpi': (192, 432),
    }

    for density, (icon_sz, fg_sz) in densities.items():
        dir_path = f'android/app/src/main/res/mipmap-{density}'
        os.makedirs(dir_path, exist_ok=True)

        # 1. ic_launcher.png (squircle / rounded rect)
        cur_l = Image.open(f'{dir_path}/ic_launcher.png')
        mask_l = cur_l.split()[-1]
        resized_l = master_icon.resize((icon_sz, icon_sz), Image.LANCZOS)
        out_l = Image.new('RGBA', (icon_sz, icon_sz), (0, 0, 0, 0))
        out_l.paste(resized_l, (0, 0), mask=mask_l)
        out_l.save(f'{dir_path}/ic_launcher.png', 'PNG')

        # 2. ic_launcher_round.png (circle)
        cur_r = Image.open(f'{dir_path}/ic_launcher_round.png')
        mask_r = cur_r.split()[-1]
        resized_r = master_icon.resize((icon_sz, icon_sz), Image.LANCZOS)
        out_r = Image.new('RGBA', (icon_sz, icon_sz), (0, 0, 0, 0))
        out_r.paste(resized_r, (0, 0), mask=mask_r)
        out_r.save(f'{dir_path}/ic_launcher_round.png', 'PNG')

        # 3. ic_launcher_foreground.png
        out_fg = fg_432.resize((fg_sz, fg_sz), Image.LANCZOS)
        out_fg.save(f'{dir_path}/ic_launcher_foreground.png', 'PNG')

    print('Updated all Android mipmap icons!')

    # Windows ICO
    ico_img = master_icon_rgb.copy()
    ico_img.save('windows/runner/resources/app_icon.ico', format='ICO', sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print('Updated windows app_icon.ico!')

if __name__ == '__main__':
    generate_gx_icons()
