"""生成项目使用的占位美术资源（与参考项目 generate_terrains.py 同思路）。

输出到 assets/：
  - terrain_tiles.png      16x96 图集，6 种地形竖向排列，供 TileSet 使用
  - player_placeholder.png 16x20 主角占位图，带透明通道

用法：python tools/generate_art.py
"""

from PIL import Image, ImageDraw
import os
import random

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "assets"))

TILE = 16
random.seed(20260415)

OUTLINE_COLOR = (28, 24, 34)


def add_noise(img, intensity=12):
    """给整张图叠加轻微噪点，避免纯色块看起来太平。"""
    pixels = img.load()
    for x in range(img.width):
        for y in range(img.height):
            r, g, b = pixels[x, y][:3]
            noise = random.randint(-intensity, intensity)
            pixels[x, y] = (
                max(0, min(255, r + noise)),
                max(0, min(255, g + noise)),
                max(0, min(255, b + noise)),
            )


def draw_grass():
    img = Image.new("RGB", (TILE, TILE), (76, 120, 50))
    draw = ImageDraw.Draw(img)
    for _ in range(10):
        x, y = random.randint(0, TILE - 1), random.randint(0, TILE - 1)
        draw.point((x, y), fill=(96, 146, 62))
    for _ in range(14):
        x, y = random.randint(0, TILE - 2), random.randint(1, TILE - 1)
        draw.line([(x, y), (x, y - 1)], fill=(88, 134, 56), width=1)
    for _ in range(4):
        x, y = random.randint(0, TILE - 3), random.randint(0, TILE - 3)
        draw.rectangle([x, y, x + 1, y + 1], fill=(64, 104, 42))
    add_noise(img, 10)
    return img


def draw_water():
    img = Image.new("RGB", (TILE, TILE), (46, 100, 162))
    draw = ImageDraw.Draw(img)
    for y in range(1, TILE, 4):
        offset = 2 if (y // 4) % 2 else 0
        for x in range(offset, TILE, 6):
            draw.line([(x, y), (min(x + 3, TILE - 1), y)], fill=(78, 142, 202), width=1)
    for _ in range(6):
        x, y = random.randint(0, TILE - 2), random.randint(0, TILE - 1)
        draw.point((x, y), fill=(110, 176, 224))
    add_noise(img, 8)
    return img


def draw_mountain():
    img = Image.new("RGB", (TILE, TILE), (104, 104, 108))
    draw = ImageDraw.Draw(img)
    for _ in range(5):
        x = random.randint(0, TILE - 6)
        y = random.randint(0, TILE - 6)
        size = random.randint(2, 4)
        draw.polygon(
            [(x, y + size), (x + size, y), (x + size * 2, y + size)],
            fill=(126, 126, 130),
        )
    for _ in range(4):
        x, y = random.randint(0, TILE - 2), random.randint(0, TILE - 2)
        draw.rectangle([x, y, x + 1, y + 1], fill=(80, 80, 86))
    add_noise(img, 14)
    return img


def draw_forest():
    img = Image.new("RGB", (TILE, TILE), (48, 92, 46))
    draw = ImageDraw.Draw(img)
    for _ in range(6):
        x, y = random.randint(1, TILE - 5), random.randint(1, TILE - 6)
        draw.ellipse([x, y, x + 4, y + 4], fill=(32, 74, 34))
    for _ in range(4):
        x, y = random.randint(1, TILE - 4), random.randint(1, TILE - 5)
        draw.ellipse([x, y, x + 3, y + 3], fill=(58, 116, 54))
    for _ in range(3):
        x = random.randint(3, TILE - 3)
        draw.rectangle([x, TILE - 5, x, TILE - 2], fill=(86, 62, 42))
    add_noise(img, 10)
    return img


def draw_beach():
    img = Image.new("RGB", (TILE, TILE), (196, 174, 118))
    draw = ImageDraw.Draw(img)
    for y in range(TILE):
        for x in range(TILE):
            if (x + y * 2) % 7 < 2:
                draw.point((x, y), fill=(178, 156, 102))
            elif (x * 2 + y) % 9 > 6:
                draw.point((x, y), fill=(216, 196, 142))
    for _ in range(16):
        x, y = random.randint(0, TILE - 1), random.randint(0, TILE - 1)
        draw.point((x, y), fill=(226, 208, 158))
    add_noise(img, 10)
    return img


def draw_snow():
    img = Image.new("RGB", (TILE, TILE), (206, 224, 238))
    draw = ImageDraw.Draw(img)
    for _ in range(6):
        x, y = random.randint(0, TILE - 5), random.randint(0, TILE - 4)
        draw.ellipse([x, y, x + 4, y + 3], fill=(186, 206, 226))
    for _ in range(5):
        x, y = random.randint(0, TILE - 4), random.randint(0, TILE - 3)
        draw.ellipse([x, y, x + 3, y + 2], fill=(236, 248, 255))
    add_noise(img, 6)
    return img


def build_player_placeholder():
    """16x20 的小人占位图：头发、脸、衣服、手臂、腿，最后描一圈深色轮廓。"""
    img = Image.new("RGBA", (TILE, 20), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    skin = (238, 205, 165)
    hair = (92, 58, 36)
    tunic = (62, 96, 186)
    belt = (120, 88, 48)
    pants = (58, 52, 62)
    boots = (40, 36, 44)
    eye = (40, 35, 45)

    # 头与头发
    draw.rectangle([5, 2, 10, 7], fill=skin)
    draw.rectangle([5, 1, 10, 3], fill=hair)
    draw.rectangle([4, 2, 4, 4], fill=hair)
    draw.rectangle([11, 2, 11, 4], fill=hair)
    draw.point((6, 5), fill=eye)
    draw.point((9, 5), fill=eye)

    # 身体与腰带
    draw.rectangle([5, 8, 10, 14], fill=tunic)
    draw.rectangle([5, 13, 10, 13], fill=belt)

    # 手臂（袖子 + 手）
    draw.rectangle([3, 8, 4, 10], fill=tunic)
    draw.rectangle([11, 8, 12, 10], fill=tunic)
    draw.rectangle([3, 11, 4, 12], fill=skin)
    draw.rectangle([11, 11, 12, 12], fill=skin)

    # 腿与鞋
    draw.rectangle([5, 15, 7, 17], fill=pants)
    draw.rectangle([8, 15, 10, 17], fill=pants)
    draw.rectangle([5, 18, 7, 19], fill=boots)
    draw.rectangle([8, 18, 10, 19], fill=boots)

    return add_outline(img, OUTLINE_COLOR)


def add_outline(img, color):
    """给所有不透明像素的外侧补一圈 1px 描边。"""
    width, height = img.size
    source = img.load()
    outline_pixels = []
    for y in range(height):
        for x in range(width):
            if source[x, y][3] != 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < width and 0 <= ny < height and source[nx, ny][3] != 0:
                    outline_pixels.append((x, y))
                    break

    draw = ImageDraw.Draw(img)
    for x, y in outline_pixels:
        draw.point((x, y), fill=color + (255,))
    return img


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    terrains = [
        ("grass", draw_grass()),
        ("water", draw_water()),
        ("mountain", draw_mountain()),
        ("forest", draw_forest()),
        ("beach", draw_beach()),
        ("snow", draw_snow()),
    ]

    atlas = Image.new("RGB", (TILE, TILE * len(terrains)))
    for index, (_name, tile) in enumerate(terrains):
        atlas.paste(tile, (0, index * TILE))
    atlas.save(os.path.join(OUTPUT_DIR, "terrain_tiles.png"))

    player = build_player_placeholder()
    player.save(os.path.join(OUTPUT_DIR, "player_placeholder.png"))

    print("生成完毕 ->", OUTPUT_DIR)
    for name in ["terrain_tiles.png", "player_placeholder.png"]:
        print("  ", name)


if __name__ == "__main__":
    main()
