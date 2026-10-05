"""生成项目使用的占位美术资源。

输出到 assets/：
  - terrain_tiles.png      16x256 图集，16 种地形竖向排列，顺序必须与 Terrain.Kind 一致
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


# ---------------------------------------------------------------- 绘制辅助

def speckle(img, color, count, size=1):
    """撒点 / 小方块。"""
    draw = ImageDraw.Draw(img)
    for _ in range(count):
        x = random.randint(0, TILE - size)
        y = random.randint(0, TILE - size)
        if size <= 1:
            draw.point((x, y), fill=color)
        else:
            draw.rectangle([x, y, x + size - 1, y + size - 1], fill=color)


def streaks(img, color, start=1, step=4, dash=3, gap=3):
    """错开的横向短划线，用来表现水波。"""
    draw = ImageDraw.Draw(img)
    row = 0
    for y in range(start, TILE, step):
        offset = 2 if row % 2 else 0
        row += 1
        x = offset
        while x < TILE:
            draw.line([(x, y), (min(x + dash - 1, TILE - 1), y)], fill=color, width=1)
            x += dash + gap


def cracks(img, color, count):
    draw = ImageDraw.Draw(img)
    for _ in range(count):
        x = random.randint(1, TILE - 6)
        y = random.randint(1, TILE - 6)
        draw.line([(x, y), (x + 3, y + 1), (x + 5, y + 3)], fill=color, width=1)


def tufts(img, color, count):
    """草簇。"""
    draw = ImageDraw.Draw(img)
    for _ in range(count):
        x = random.randint(0, TILE - 1)
        y = random.randint(3, TILE - 1)
        draw.line([(x, y), (x, y - 2)], fill=color, width=1)
        if x + 1 < TILE:
            draw.point((x + 1, y - 1), fill=color)


def blobs(img, color, count, radius):
    draw = ImageDraw.Draw(img)
    for _ in range(count):
        x = random.randint(radius, TILE - radius - 1)
        y = random.randint(radius, TILE - radius - 1)
        draw.ellipse([x - radius, y - radius, x + radius, y + radius], fill=color)


def spikes(img, color, count, min_h=4, max_h=6):
    """三角形，用来表现针叶树冠或山峰。"""
    draw = ImageDraw.Draw(img)
    for _ in range(count):
        width = random.randint(3, 5)
        if width >= TILE:
            continue
        x = random.randint(0, TILE - width)
        base = random.randint(TILE // 2, TILE - 1)
        height = random.randint(min_h, max_h)
        draw.polygon(
            [(x, base), (x + width // 2, base - height), (x + width, base)],
            fill=color,
        )


def puddles(img, color, count):
    draw = ImageDraw.Draw(img)
    for _ in range(count):
        x = random.randint(1, TILE - 5)
        y = random.randint(1, TILE - 5)
        draw.ellipse([x, y, x + 3, y + 1], fill=color)


def dunes(img, color, count):
    draw = ImageDraw.Draw(img)
    for _ in range(count):
        x = random.randint(0, 5)
        y = random.randint(2, TILE - 4)
        draw.arc([x, y, x + 12, y + 6], 180, 360, fill=color)


def add_noise(img, intensity=10):
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


def tile(base, noise=10):
    return Image.new("RGB", (TILE, TILE), base), noise


# ---------------------------------------------------------------- 16 种地形
# 顺序必须与 resources/world/terrain.gd 里的 Terrain.Kind 完全一致

def make_deep_water():
    img, n = tile((26, 62, 122), 8)
    streaks(img, (34, 74, 138), start=2, step=5)
    speckle(img, (20, 50, 104), 12)
    add_noise(img, n)
    return img


def make_water():
    img, n = tile((46, 100, 162), 8)
    streaks(img, (78, 140, 200), start=1, step=4)
    speckle(img, (104, 162, 216), 8)
    add_noise(img, n)
    return img


def make_ice():
    img, n = tile((196, 222, 240), 6)
    speckle(img, (172, 202, 226), 14)
    cracks(img, (152, 184, 210), 3)
    speckle(img, (238, 250, 255), 10)
    add_noise(img, n)
    return img


def make_sand():
    img, n = tile((216, 198, 152), 9)
    speckle(img, (196, 176, 130), 26)
    speckle(img, (238, 224, 184), 14)
    add_noise(img, n)
    return img


def make_grass():
    img, n = tile((76, 120, 50), 10)
    tufts(img, (98, 148, 64), 14)
    speckle(img, (62, 102, 42), 10)
    add_noise(img, n)
    return img


def make_forest():
    img, n = tile((48, 92, 46), 9)
    blobs(img, (30, 70, 34), 5, 2)
    blobs(img, (60, 118, 56), 4, 1)
    speckle(img, (86, 62, 42), 5)
    add_noise(img, n)
    return img


def make_taiga():
    img, n = tile((40, 74, 58), 9)
    spikes(img, (26, 54, 42), 4)
    speckle(img, (62, 100, 78), 10)
    add_noise(img, n)
    return img


def make_rainforest():
    img, n = tile((30, 98, 52), 9)
    blobs(img, (20, 74, 38), 6, 2)
    blobs(img, (58, 136, 68), 5, 1)
    add_noise(img, n)
    return img


def make_swamp():
    img, n = tile((74, 86, 54), 9)
    blobs(img, (56, 70, 44), 4, 2)
    puddles(img, (58, 84, 74), 3)
    speckle(img, (98, 110, 68), 10)
    add_noise(img, n)
    return img


def make_savanna():
    img, n = tile((150, 152, 78), 9)
    tufts(img, (178, 176, 96), 13)
    speckle(img, (120, 122, 60), 9)
    add_noise(img, n)
    return img


def make_desert():
    img, n = tile((206, 178, 112), 9)
    dunes(img, (186, 156, 92), 4)
    speckle(img, (228, 206, 148), 16)
    add_noise(img, n)
    return img


def make_tundra():
    img, n = tile((138, 136, 118), 9)
    speckle(img, (114, 112, 96), 20)
    speckle(img, (164, 162, 142), 12)
    add_noise(img, n)
    return img


def make_stone():
    img, n = tile((122, 122, 128), 9)
    blobs(img, (102, 102, 108), 4, 2)
    speckle(img, (146, 146, 152), 12)
    add_noise(img, n)
    return img


def make_mountain():
    img, n = tile((98, 98, 104), 10)
    spikes(img, (74, 74, 80), 4, 5, 7)
    speckle(img, (130, 130, 136), 10)
    add_noise(img, n)
    return img


def make_snow():
    img, n = tile((222, 232, 242), 6)
    blobs(img, (202, 216, 230), 4, 2)
    speckle(img, (246, 252, 255), 12)
    add_noise(img, n)
    return img


def make_snow_peak():
    img, n = tile((240, 247, 253), 5)
    spikes(img, (204, 220, 236), 4, 5, 7)
    speckle(img, (170, 190, 212), 8)
    add_noise(img, n)
    return img


# 索引 = Terrain.Kind，名字只用于打印校对
TERRAINS = [
    ("DEEP_WATER", make_deep_water),
    ("WATER", make_water),
    ("ICE", make_ice),
    ("SAND", make_sand),
    ("GRASS", make_grass),
    ("FOREST", make_forest),
    ("TAIGA", make_taiga),
    ("RAINFOREST", make_rainforest),
    ("SWAMP", make_swamp),
    ("SAVANNA", make_savanna),
    ("DESERT", make_desert),
    ("TUNDRA", make_tundra),
    ("STONE", make_stone),
    ("MOUNTAIN", make_mountain),
    ("SNOW", make_snow),
    ("SNOW_PEAK", make_snow_peak),
]


# ---------------------------------------------------------------- 主角占位图

def build_player_placeholder():
    """16x20 的小人占位图，最后描一圈深色轮廓。"""
    img = Image.new("RGBA", (TILE, 20), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    skin = (238, 205, 165)
    hair = (92, 58, 36)
    tunic = (62, 96, 186)
    belt = (120, 88, 48)
    pants = (58, 52, 62)
    boots = (40, 36, 44)
    eye = (40, 35, 45)

    draw.rectangle([5, 2, 10, 7], fill=skin)
    draw.rectangle([5, 1, 10, 3], fill=hair)
    draw.rectangle([4, 2, 4, 4], fill=hair)
    draw.rectangle([11, 2, 11, 4], fill=hair)
    draw.point((6, 5), fill=eye)
    draw.point((9, 5), fill=eye)

    draw.rectangle([5, 8, 10, 14], fill=tunic)
    draw.rectangle([5, 13, 10, 13], fill=belt)

    draw.rectangle([3, 8, 4, 10], fill=tunic)
    draw.rectangle([11, 8, 12, 10], fill=tunic)
    draw.rectangle([3, 11, 4, 12], fill=skin)
    draw.rectangle([11, 11, 12, 12], fill=skin)

    draw.rectangle([5, 15, 7, 17], fill=pants)
    draw.rectangle([8, 15, 10, 17], fill=pants)
    draw.rectangle([5, 18, 7, 19], fill=boots)
    draw.rectangle([8, 18, 10, 19], fill=boots)

    return add_outline(img, OUTLINE_COLOR)


def add_outline(img, color):
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

    atlas = Image.new("RGB", (TILE, TILE * len(TERRAINS)))
    for index, (name, builder) in enumerate(TERRAINS):
        atlas.paste(builder(), (0, index * TILE))
        print("  tile %2d = %s" % (index, name))
    atlas.save(os.path.join(OUTPUT_DIR, "terrain_tiles.png"))

    build_player_placeholder().save(os.path.join(OUTPUT_DIR, "player_placeholder.png"))

    print("生成完毕 ->", OUTPUT_DIR)


if __name__ == "__main__":
    main()
