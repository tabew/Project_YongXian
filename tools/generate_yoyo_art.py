"""Generate pixel-art yoyo variants using the combat placeholder palette."""
from pathlib import Path
from PIL import Image, ImageDraw

DEST = Path(__file__).resolve().parent.parent / "assets" / "weapons"


def main():
    for name, fill in (("thunder_yoyo", "#348fc4"), ("hive_yoyo", "#e5ad38")):
        image = Image.new("RGBA", (14, 14))
        draw = ImageDraw.Draw(image)
        draw.ellipse((0, 0, 13, 13), fill="#1a1d27")
        draw.ellipse((1, 1, 12, 12), fill=fill)
        if name == "thunder_yoyo":
            draw.arc((2, 2, 11, 11), 110, 290, fill="#9ceafa", width=1)
            draw.polygon([(7, 2), (4, 7), (7, 7), (6, 11), (10, 5), (7, 5)], fill="#ecffff")
        else:
            for x, y in ((4, 4), (9, 4), (6, 8)):
                draw.polygon([(x-2, y), (x-1, y-2), (x+1, y-2), (x+2, y), (x+1, y+2), (x-1, y+2)], fill="#795226")
                draw.point((x, y-1), fill="#ffe392")
        image.save(DEST / (name + ".png"))
    image = Image.new("RGBA", (8, 8))
    draw = ImageDraw.Draw(image)
    draw.ellipse((1, 0, 3, 4), fill="#dcf5ff")
    draw.ellipse((4, 0, 6, 4), fill="#dcf5ff")
    draw.rectangle((1, 3, 6, 6), fill="#25222b")
    draw.rectangle((2, 3, 3, 6), fill="#f8c649")
    draw.point((6, 4), fill="#ffffff")
    image.save(DEST / "yoyo_bee.png")


if __name__ == "__main__":
    main()
