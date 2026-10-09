"""Rebuild the original pixel-art combat placeholders without touching world art."""

from pathlib import Path

from PIL import Image, ImageDraw


ASSETS = Path(__file__).resolve().parent.parent / "assets"
OUTLINE = (26, 29, 39, 255)


def longsword() -> Image.Image:
    image = Image.new("RGBA", (44, 14))
    draw = ImageDraw.Draw(image)
    draw.polygon([(10, 3), (35, 3), (43, 7), (35, 11), (10, 11)], fill=OUTLINE)
    draw.polygon([(12, 4), (34, 4), (40, 7), (34, 10), (12, 10)], fill="#9eb5c7")
    draw.polygon([(12, 4), (34, 4), (40, 7), (12, 7)], fill="#e6f5f6")
    draw.line([(13, 8), (34, 8), (38, 7)], fill="#668596")
    draw.rectangle((3, 5, 10, 9), fill=OUTLINE)
    draw.rectangle((4, 6, 9, 8), fill="#804452")
    draw.point((5, 6), fill="#c88176")
    draw.point((7, 6), fill="#c88176")
    draw.rectangle((9, 1, 12, 12), fill=OUTLINE)
    draw.rectangle((10, 2, 11, 11), fill="#dab65e")
    draw.rectangle((1, 5, 3, 9), fill=OUTLINE)
    draw.rectangle((2, 6, 3, 8), fill="#dab65e")
    return image


def long_staff() -> Image.Image:
    image = Image.new("RGBA", (32, 5))
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 1, 31, 3), fill=OUTLINE)
    draw.line([(1, 1), (30, 1)], fill="#d2ad75")
    draw.line([(1, 2), (30, 2)], fill="#916540")
    for x in (1, 29):
        draw.rectangle((x, 1, x + 1, 3), fill="#819599")
        draw.point((x, 1), fill="#d7e3df")
    draw.rectangle((5, 1, 11, 3), fill="#496957")
    for x in (5, 8, 11):
        draw.line([(x, 1), (x, 2)], fill="#afc29f")
    return image


def training_dummy() -> Image.Image:
    image = Image.new("RGBA", (24, 32))
    draw = ImageDraw.Draw(image)
    draw.ellipse((2, 27, 22, 31), fill=(16, 24, 22, 95))
    draw.rectangle((10, 19, 13, 29), fill=OUTLINE)
    draw.rectangle((11, 20, 12, 28), fill="#866447")
    draw.rectangle((5, 29, 19, 30), fill=OUTLINE)
    draw.rectangle((2, 11, 21, 14), fill=OUTLINE)
    draw.rectangle((3, 12, 20, 13), fill="#c5a06a")
    draw.rectangle((6, 8, 17, 23), fill=OUTLINE)
    draw.rectangle((7, 9, 16, 22), fill="#d6be81")
    draw.rectangle((8, 0, 15, 7), fill=OUTLINE)
    draw.rectangle((9, 1, 14, 6), fill="#e5d19e")
    draw.line([(10, 2), (10, 3)], fill="#564f3c")
    draw.line([(13, 2), (13, 3)], fill="#564f3c")
    draw.line([(10, 5), (13, 5)], fill="#866447")
    draw.ellipse((8, 12, 15, 19), fill="#984851")
    draw.ellipse((10, 14, 13, 17), fill="#eed4ab")
    draw.line([(7, 21), (16, 21)], fill="#866447")
    return image


def main() -> None:
    (ASSETS / "weapons").mkdir(parents=True, exist_ok=True)
    (ASSETS / "combat").mkdir(parents=True, exist_ok=True)
    longsword().save(ASSETS / "weapons" / "longsword.png")
    long_staff().save(ASSETS / "weapons" / "long_staff.png")
    training_dummy().save(ASSETS / "combat" / "training_dummy.png")
    print("Generated longsword.png, long_staff.png and training_dummy.png")


if __name__ == "__main__":
    main()
