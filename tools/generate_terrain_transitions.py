"""Build feathered pixel edges from the existing terrain and road atlases.

Rows: base * 19 + neighbour. Columns: 16 cardinal masks, 4 corner masks,
then 4 strengths for the approach to a neighbouring region. No terrain data
or collision rules are changed by this visual atlas.
"""
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
TILE = 16
KINDS = 19
MASKS = 24


def weights(mask):
    y, x = np.mgrid[:TILE, :TILE].astype(float)
    # Small regular scallops break the ruler-straight edge without adding
    # isolated terrain cells. The feather extends six pixels into each tile.
    scallop_y = np.array([0, 1, 1, 0, -1, 0, 1, 0, 0, -1, 0, 1, 1, 0, -1, 0])[y.astype(int)]
    scallop_x = np.array([0, 0, 1, 0, -1, 0, 1, 1, 0, -1, 0, 0, 1, 0, -1, 0])[x.astype(int)]
    if mask >= 20:
        return np.full((TILE, TILE), (mask - 19) * 0.125)
    if mask >= 16:
        corners = [(0, 0), (15, 0), (15, 15), (0, 15)]
        cx, cy = corners[mask - 16]
        distance = np.sqrt((x - cx) ** 2 + (y - cy) ** 2)
        return np.clip((7.0 - distance) / 7.0, 0, 1) * 0.55
    result = np.zeros((TILE, TILE))
    distances = [y, TILE - 1 - x, TILE - 1 - y, x]
    for side, distance in enumerate(distances):
        if mask & (1 << side):
            scallop = scallop_y if side % 2 else scallop_x
            feather = np.clip((6.0 + scallop * 0.65 - distance) / 6.0, 0, 1)
            result = np.maximum(result, feather * 0.55)
    return result


def main():
    terrain = Image.open(ROOT / 'assets/terrain_tiles.png').convert('RGB')
    roads = Image.open(ROOT / 'assets/road_tiles.png').convert('RGB')
    tiles = [np.asarray(terrain.crop((0, i * TILE, TILE, (i + 1) * TILE)), dtype=float) for i in range(16)]
    tiles += [np.asarray(roads.crop((0, i * TILE, TILE, (i + 1) * TILE)), dtype=float) for i in range(3)]
    atlas = Image.new('RGB', (MASKS * TILE, KINDS * KINDS * TILE))
    masks = [weights(mask)[..., None] for mask in range(MASKS)]
    for base in range(KINDS):
        for other in range(KINDS):
            row = base * KINDS + other
            for mask, alpha in enumerate(masks):
                pixels = np.rint(tiles[base] * (1 - alpha) + tiles[other] * alpha).astype('uint8')
                atlas.paste(Image.fromarray(pixels), (mask * TILE, row * TILE))
    output = ROOT / 'assets/terrain_transitions.png'
    atlas.save(output, optimize=True)
    print(f'{output.name}: {atlas.width}x{atlas.height}, {output.stat().st_size:,} bytes')


if __name__ == '__main__':
    main()
