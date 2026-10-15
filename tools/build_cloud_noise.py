#!/usr/bin/env python3
"""Generate the tileable 3D noise volumes used by the cloud renderer.

Writes two PNG atlases under assets/clouds/. Each stacks the Z slices of a
cube vertically: an N x N x N volume becomes an N-wide, N*N-tall image in
which slice z occupies rows z*N to z*N + N - 1.

  shape_noise.png  64^3 RGBA
    R  Perlin-Worley: Perlin fBm whose low values are eaten by Worley fBm,
       giving rounded, billowing cloud masses with clean gaps.
    G  Worley fBm, cell frequencies 4/8/16: lumpy cauliflower structure.
    B  Perlin fBm, frequency 2: broad variation (cloud heights, weather).
    A  Perlin fBm, frequency 3, independent of B: broad variation.

  detail_noise.png  32^3 RGBA
    R  Worley fBm, cell frequencies 4/8/16: small billows for erosion.
    G  Worley fBm, cell frequencies 8/16/32: finer billows.
    B  Perlin fBm, frequency 4: wisps.
    A  255.

Every channel repeats with the cube's period on all three axes, so the
renderer can tile it across a planet without seams. The generator is
deterministic: the same seed always produces identical files. Pure Python
with no dependencies; the default sizes take a minute or two.

Usage: python3 tools/build_cloud_noise.py [--seed N]
"""

import argparse
import math
import os
import random
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(ROOT, "assets", "clouds")


def write_png(path, width, height, rows):
    """Minimal RGBA8 PNG encoder. rows yields one bytes object per row."""
    raw = bytearray()
    for row in rows:
        raw.append(0)
        raw.extend(row)

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    with open(path, "wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n")
        handle.write(chunk(b"IHDR", header))
        handle.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        handle.write(chunk(b"IEND", b""))


class Perlin:
    """Gradient noise on a lattice that repeats every `period` cells."""

    def __init__(self, rng, period):
        self.period = period
        count = period ** 3
        self.gradients = []
        for _ in range(count):
            # Uniform directions on the sphere.
            z = rng.uniform(-1.0, 1.0)
            angle = rng.uniform(0.0, math.tau)
            r = math.sqrt(1.0 - z * z)
            self.gradients.append((r * math.cos(angle), r * math.sin(angle), z))

    def value(self, x, y, z):
        """x, y, z in lattice units. Result roughly in [-1, 1]."""
        p = self.period
        ix, iy, iz = math.floor(x), math.floor(y), math.floor(z)
        fx, fy, fz = x - ix, y - iy, z - iz
        # Quintic fade keeps second derivatives continuous across cells.
        ux = fx * fx * fx * (fx * (fx * 6.0 - 15.0) + 10.0)
        uy = fy * fy * fy * (fy * (fy * 6.0 - 15.0) + 10.0)
        uz = fz * fz * fz * (fz * (fz * 6.0 - 15.0) + 10.0)
        g = self.gradients
        total = 0.0
        for cz in (0, 1):
            wz = uz if cz else 1.0 - uz
            dz = fz - cz
            kz = ((iz + cz) % p) * p * p
            for cy in (0, 1):
                wy = uy if cy else 1.0 - uy
                dy = fy - cy
                ky = kz + ((iy + cy) % p) * p
                for cx in (0, 1):
                    wx = ux if cx else 1.0 - ux
                    gx, gy, gz = g[ky + (ix + cx) % p]
                    total += wx * wy * wz * (gx * (fx - cx) + gy * dy + gz * dz)
        # The extreme of 3D gradient noise is about sqrt(3)/2.
        return total * 1.1547


class Worley:
    """One feature point per cell; cells repeat every `period` along each axis."""

    def __init__(self, rng, period):
        self.period = period
        self.points = [(rng.random(), rng.random(), rng.random()) for _ in range(period ** 3)]
        # For every cell, the 27 surrounding feature points relative to its origin.
        self.neighbours = []
        p = period
        for cz in range(p):
            for cy in range(p):
                for cx in range(p):
                    around = []
                    for dz in (-1, 0, 1):
                        for dy in (-1, 0, 1):
                            for dx in (-1, 0, 1):
                                px, py, pz = self.points[((cz + dz) % p) * p * p + ((cy + dy) % p) * p + (cx + dx) % p]
                                around.append((dx + px, dy + py, dz + pz))
                    self.neighbours.append(around)

    def value(self, x, y, z):
        """Inverted distance to the nearest feature: 1 at a point, 0 far away."""
        p = self.period
        ix, iy, iz = math.floor(x), math.floor(y), math.floor(z)
        lx, ly, lz = x - ix, y - iy, z - iz
        best = 9.0
        for px, py, pz in self.neighbours[(iz % p) * p * p + (iy % p) * p + ix % p]:
            ex, ey, ez = px - lx, py - ly, pz - lz
            d = ex * ex + ey * ey + ez * ez
            if d < best:
                best = d
        return 1.0 - min(math.sqrt(best), 1.0)


def perlin_fbm(rng, base, octaves):
    layers = [Perlin(rng, base * (2 ** i)) for i in range(octaves)]

    def value(u, v, w):
        total = 0.0
        amplitude = 1.0
        norm = 0.0
        for layer in layers:
            f = layer.period
            total += layer.value(u * f, v * f, w * f) * amplitude
            norm += amplitude
            amplitude *= 0.5
        return total / norm

    return value


def worley_fbm(rng, frequencies):
    layers = [Worley(rng, f) for f in frequencies]
    weights = [0.625, 0.25, 0.125][: len(layers)]
    norm = sum(weights)

    def value(u, v, w):
        total = 0.0
        for layer, weight in zip(layers, weights):
            f = layer.period
            total += layer.value(u * f, v * f, w * f) * weight
        return total / norm

    return value


def remap(value, low, high, new_low, new_high):
    return new_low + (value - low) / (high - low) * (new_high - new_low)


def to_byte(value):
    return max(0, min(255, int(round(value * 255.0))))


def build_volume(size, channels):
    """channels: four functions of (u, v, w) in [0, 1) returning [0, 1]."""
    rows = []
    for z in range(size):
        w = (z + 0.5) / size
        for y in range(size):
            v = (y + 0.5) / size
            row = bytearray(size * 4)
            for x in range(size):
                u = (x + 0.5) / size
                for c in range(4):
                    row[x * 4 + c] = to_byte(channels[c](u, v, w))
            rows.append(bytes(row))
        print(f"  slice {z + 1}/{size}", end="\r", flush=True)
    print()
    return rows


def stretch(rows, size, channel):
    """Linearly expand a channel to span the full byte range."""
    low = min(row[x * 4 + channel] for row in rows for x in range(size))
    high = max(row[x * 4 + channel] for row in rows for x in range(size))
    if high <= low:
        return rows
    scaled = []
    for row in rows:
        row = bytearray(row)
        for x in range(size):
            row[x * 4 + channel] = to_byte((row[x * 4 + channel] - low) / (high - low))
        scaled.append(bytes(row))
    return scaled


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--seed", type=int, default=20261014)
    parser.add_argument("--shape-size", type=int, default=64)
    parser.add_argument("--detail-size", type=int, default=32)
    arguments = parser.parse_args()
    os.makedirs(OUTPUT, exist_ok=True)
    rng = random.Random(arguments.seed)

    print("Shape volume")
    shape_perlin = perlin_fbm(rng, 4, 3)
    shape_worley = worley_fbm(rng, [4, 8, 16])
    lumps = worley_fbm(rng, [4, 8, 16])
    broad = perlin_fbm(rng, 2, 3)
    broad2 = perlin_fbm(rng, 3, 2)

    def perlin_worley(u, v, w):
        perlin = shape_perlin(u, v, w) * 0.5 + 0.5
        worley = shape_worley(u, v, w)
        # Worley acts as the floor: where cells are far from a feature point
        # the Perlin billows are cut away, leaving rounded masses.
        return max(0.0, min(1.0, remap(perlin, worley - 1.0, 1.0, 0.0, 1.0)))

    size = arguments.shape_size
    rows = build_volume(size, [
        perlin_worley,
        lumps,
        lambda u, v, w: broad(u, v, w) * 0.5 + 0.5,
        lambda u, v, w: broad2(u, v, w) * 0.5 + 0.5,
    ])
    for channel in range(4):
        rows = stretch(rows, size, channel)
    write_png(os.path.join(OUTPUT, "shape_noise.png"), size, size * size, rows)

    print("Detail volume")
    fine = worley_fbm(rng, [4, 8, 16])
    finer = worley_fbm(rng, [8, 16, 32])
    wisps = perlin_fbm(rng, 4, 3)
    size = arguments.detail_size
    rows = build_volume(size, [
        fine,
        finer,
        lambda u, v, w: wisps(u, v, w) * 0.5 + 0.5,
        lambda u, v, w: 1.0,
    ])
    for channel in range(3):
        rows = stretch(rows, size, channel)
    write_png(os.path.join(OUTPUT, "detail_noise.png"), size, size * size, rows)
    print("Wrote", OUTPUT)


if __name__ == "__main__":
    main()
