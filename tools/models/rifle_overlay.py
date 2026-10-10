#!/usr/bin/env python3
"""Grundtextur für Farb-Skins am Sturmgewehr (Skins/Farbe, siehe tools/models/skins.luau).

Nimmt die Farb-Textur aus art/sources/Rifle.glb und macht die gleichmäßigen Farbflächen teilweise durchsichtig:
Grundfläche ~22 % deckend (Schattierung bleibt), Kanten, Kratzer, Schrift, tiefe Fugen und helle Kanten deckend.
Mit AlphaMode Overlay scheint dort die Skin-Farbe des Teils durch (Lava orange, Galaxie lila ...).
Ergebnis 1024 x 1024 RGBA: art/sources/Rifle_Texturen/Skin_Body_Overlay.png

Aufruf: python3 tools/models/rifle_overlay.py   (braucht Pillow und numpy)
"""
import io
import json
import os
import struct

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GLB = os.path.join(ROOT, "art", "sources", "Rifle.glb")
OUT = os.path.join(ROOT, "art", "sources", "Rifle_Texturen", "Skin_Body_Overlay.png")


def base_color_image(path):
    data = open(path, "rb").read()
    length = struct.unpack("<I", data[12:16])[0]
    gltf = json.loads(data[20:20 + length])
    offset = 20 + length
    binary = data[offset + 8:offset + 8 + struct.unpack("<I", data[offset:offset + 4])[0]]
    material = gltf["materials"][0]["pbrMetallicRoughness"]
    image = gltf["images"][gltf["textures"][material["baseColorTexture"]["index"]]["source"]]
    view = gltf["bufferViews"][image["bufferView"]]
    start = view.get("byteOffset", 0)
    return Image.open(io.BytesIO(binary[start:start + view["byteLength"]]))


def main():
    color = base_color_image(GLB).convert("RGB").resize((1024, 1024), Image.LANCZOS)
    rgb = np.asarray(color).astype(np.float32) / 255
    lum = rgb @ np.array([0.299, 0.587, 0.114], np.float32)
    blurred = np.asarray(Image.fromarray((lum * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(4)))
    detail = lum - blurred.astype(np.float32) / 255
    base = np.median(lum[(lum > 0.12) & (lum < 0.45)])
    alpha = (0.22 + 3.2 * np.abs(detail) + 2.0 * np.clip(base * 0.55 - lum, 0, None)
             + 1.2 * np.clip(lum - base * 1.6, 0, None))
    alpha = np.clip(alpha, 0, 0.95)
    alpha[lum < 0.02] = 1.0  # ungenutzte Flächen im Atlas
    rgba = np.dstack([rgb, alpha])
    Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA").save(OUT)
    print("geschrieben:", os.path.relpath(OUT, ROOT), "mittlere Deckkraft %.2f" % alpha.mean())


if __name__ == "__main__":
    main()
