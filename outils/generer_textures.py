#!/usr/bin/env python3
"""Génère les textures de l'interface de Négoce (Art/*.tga).

Des formes blanches dont seule la transparence varie : l'addon les teinte à la couleur voulue.
Elles sont symétriques, donc l'orientation du fichier n'a pas d'importance.
"""
import math
import os
import struct

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(RACINE, "Art")


def ecrire(nom, taille, alpha):
    """alpha(x, y) -> 0..1, coordonnées au centre du pixel."""
    entete = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, taille, taille, 32, 0x08)
    pixels = bytearray()
    for y in range(taille):
        for x in range(taille):
            a = max(0.0, min(1.0, alpha(x + 0.5, y + 0.5)))
            pixels += bytes((255, 255, 255, int(round(a * 255))))
    with open(os.path.join(ART, nom), "wb") as f:
        f.write(entete + pixels)


def distance_rectangle_arrondi(x, y, taille, marge, rayon):
    """Distance signée au bord d'un rectangle arrondi (négative à l'intérieur)."""
    demi = taille / 2 - marge - rayon
    dx = abs(x - taille / 2) - demi
    dy = abs(y - taille / 2) - demi
    dehors = math.hypot(max(dx, 0), max(dy, 0))
    dedans = min(max(dx, dy), 0)
    return dehors + dedans - rayon


def main():
    os.makedirs(ART, exist_ok=True)
    # Rectangle arrondi plein (coins de 10 px), à étirer en 9 tranches.
    ecrire("rond.tga", 64, lambda x, y: 0.5 - distance_rectangle_arrondi(x, y, 64, 0, 10))
    # Contour d'un pixel du même rectangle.
    ecrire("contour.tga", 64, lambda x, y: 1 - abs(distance_rectangle_arrondi(x, y, 64, 0, 10) + 1.0))
    # Petit rectangle arrondi (coins de 5 px) pour les pastilles et les boutons.
    ecrire("pastille.tga", 32, lambda x, y: 0.5 - distance_rectangle_arrondi(x, y, 32, 0, 5))
    # Ombre douce autour d'un rectangle arrondi.
    ecrire("ombre.tga", 128, lambda x, y: 0.55 * math.exp(-max(0.0, distance_rectangle_arrondi(x, y, 128, 28, 12)) ** 2 / 160.0))
    # Disque.
    ecrire("disque.tga", 32, lambda x, y: 15.0 - math.hypot(x - 16, y - 16))
    print("textures écrites dans", ART)


if __name__ == "__main__":
    main()
