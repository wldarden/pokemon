#!/usr/bin/env python3
"""
Fetch Pokémon data from pokeapi.co and generate Godot .tres resource files.

Usage:
    python3 tools/fetch_pokeapi.py

Run once during development. The app never calls PokéAPI at runtime.

Outputs:
    assets/sprites/pokemon/front_NNN.png, back_NNN.png   (Gen 3 FR/LG sprites)
    data/species/NNN_<name>.tres                         (Species Resource)
    data/moves/<name>.tres                                (Move Resource)
    data/type_chart.tres                                  (TypeChart Resource)

Network: ~10 GETs total for Phase 1 data. PokéAPI is unauthenticated and free.
"""

from __future__ import annotations
import json
import os
import ssl
import sys
import urllib.request
from pathlib import Path
from typing import Any, Dict, List, Tuple

REPO_ROOT = Path(__file__).resolve().parent.parent
SPRITES_DIR = REPO_ROOT / "assets" / "sprites" / "pokemon"
SPECIES_DIR = REPO_ROOT / "data" / "species"
MOVES_DIR = REPO_ROOT / "data" / "moves"
TYPE_CHART_PATH = REPO_ROOT / "data" / "type_chart.tres"

API = "https://pokeapi.co/api/v2"

# --- Phase 1 fetch targets.
SPECIES_IDS = [1, 4, 7]  # Bulbasaur, Charmander, Squirtle
MOVE_NAMES = ["tackle", "scratch", "vine-whip", "ember"]

# Map PokéAPI version_group names → generation number.
# PokéAPI past_values semantics: each entry's values applied UP TO AND INCLUDING
# that version_group's generation (and anything before it, back to the previous
# past_values entry). So a "black-white" (Gen 5) entry means "Gen 1-5 values"
# — we pick the first entry whose generation >= target_gen.
VERSION_GROUP_GEN = {
    "red-blue": 1, "yellow": 1,
    "gold-silver": 2, "crystal": 2,
    "ruby-sapphire": 3, "firered-leafgreen": 3, "emerald": 3,
    "diamond-pearl": 4, "platinum": 4, "heartgold-soulsilver": 4,
    "black-white": 5, "black-2-white-2": 5,
    "colosseum": 3, "xd": 3,
    "x-y": 6, "omega-ruby-alpha-sapphire": 6,
    "sun-moon": 7, "ultra-sun-ultra-moon": 7,
    "lets-go-pikachu-lets-go-eevee": 7,
    "sword-shield": 8, "brilliant-diamond-and-shining-pearl": 8,
    "legends-arceus": 8, "scarlet-violet": 9,
}
TARGET_GEN = 3

# Gen 3 splits physical vs special by TYPE, not per-move.
GEN3_PHYSICAL_TYPES = {
    "normal", "fighting", "flying", "ground", "rock",
    "bug", "ghost", "poison", "steel",
}

# Enums.Type values — must match scripts/data/enums.gd.
TYPE_ENUM = {
    "normal": 0, "fire": 1, "water": 2, "grass": 3, "electric": 4,
    "ice": 5, "fighting": 6, "poison": 7, "ground": 8, "flying": 9,
    "psychic": 10, "bug": 11, "rock": 12, "ghost": 13, "dragon": 14,
    "dark": 15, "steel": 16,
    # Fairy (Gen 6) is deliberately excluded — doesn't exist in our Gen 3 era.
}

# Enums.Category.
CATEGORY_ENUM = {"PHYSICAL": 0, "SPECIAL": 1, "STATUS": 2}

# Enums.GrowthRate.
GROWTH_RATE_ENUM = {
    "medium": 0,        # "medium" -> medium-fast canonically
    "medium-fast": 0,
    "erratic": 1,
    "fluctuating": 2,
    "medium-slow": 3,
    "fast": 4,
    "slow": 5,
}


# --------------------------------------------------------------------
# HTTP

_SSL_CTX = ssl.create_default_context(cafile="/etc/ssl/cert.pem")


def get_json(url: str) -> Dict[str, Any]:
    req = urllib.request.Request(url, headers={"User-Agent": "pokemon-gameboy-phase1/0.1"})
    with urllib.request.urlopen(req, context=_SSL_CTX, timeout=30) as resp:
        return json.load(resp)


def download_binary(url: str, dest: Path) -> None:
    req = urllib.request.Request(url, headers={"User-Agent": "pokemon-gameboy-phase1/0.1"})
    with urllib.request.urlopen(req, context=_SSL_CTX, timeout=30) as resp:
        dest.write_bytes(resp.read())


# --------------------------------------------------------------------
# Move data (with Gen 3 past-value overrides)

def fetch_move_gen3(name: str) -> Dict[str, Any]:
    data = get_json(f"{API}/move/{name}")
    power = data.get("power") or 0
    accuracy = data.get("accuracy") or 0  # 0 = never-miss in our schema
    pp = data.get("pp") or 0
    priority = data.get("priority", 0)

    # Pick the first past_values entry whose generation >= TARGET_GEN.
    # That entry represents the values that applied during TARGET_GEN.
    # If no such entry, current values apply (move was the same in Gen 3 as now).
    pvs_sorted = sorted(
        data.get("past_values", []),
        key=lambda pv: VERSION_GROUP_GEN.get(pv["version_group"]["name"], 999),
    )
    for pv in pvs_sorted:
        vg_gen = VERSION_GROUP_GEN.get(pv["version_group"]["name"], 999)
        if vg_gen >= TARGET_GEN:
            if pv.get("power") is not None:
                power = pv["power"]
            if pv.get("accuracy") is not None:
                accuracy = pv["accuracy"]
            if pv.get("pp") is not None:
                pp = pv["pp"]
            break

    type_name = data["type"]["name"]
    api_class = data["damage_class"]["name"]  # physical / special / status in Gen 4+ terms
    if api_class == "status":
        category = "STATUS"
    elif type_name in GEN3_PHYSICAL_TYPES:
        category = "PHYSICAL"
    else:
        category = "SPECIAL"

    return {
        "name": data["name"],
        "display_name": data["name"].replace("-", " ").title(),
        "type": type_name,
        "category": category,
        "power": power,
        "accuracy": accuracy,
        "pp": pp,
        "priority": priority,
    }


# --------------------------------------------------------------------
# Species data

def fetch_species(dex: int) -> Dict[str, Any]:
    pkmn = get_json(f"{API}/pokemon/{dex}")
    species = get_json(f"{API}/pokemon-species/{dex}")

    name = pkmn["name"]
    types = [t["type"]["name"] for t in sorted(pkmn["types"], key=lambda t: t["slot"])]
    base_stats = {s["stat"]["name"]: s["base_stat"] for s in pkmn["stats"]}

    frlg = (
        pkmn["sprites"]["versions"]
        .get("generation-iii", {})
        .get("firered-leafgreen", {})
    )
    front_url = frlg.get("front_default") or pkmn["sprites"].get("front_default")
    back_url = frlg.get("back_default") or pkmn["sprites"].get("back_default")
    if not front_url or not back_url:
        raise RuntimeError(f"missing sprite urls for dex {dex}")

    capture_rate = species["capture_rate"]
    growth_name = species["growth_rate"]["name"]

    return {
        "dex": dex,
        "name": name,
        "display_name": name.title(),
        "types": types,
        "base_stats": base_stats,
        "base_exp": pkmn.get("base_experience") or 0,
        "capture_rate": capture_rate,
        "growth_rate": growth_name,
        "front_url": front_url,
        "back_url": back_url,
    }


# --------------------------------------------------------------------
# Type chart

def fetch_type_relations() -> Dict[str, Dict[str, float]]:
    """Returns {attacker_type: {defender_type: multiplier}} for non-1.0 entries only."""
    relations: Dict[str, Dict[str, float]] = {}
    for attacker, _ in TYPE_ENUM.items():
        data = get_json(f"{API}/type/{attacker}")
        r = data["damage_relations"]
        entry: Dict[str, float] = {}
        for t in r["double_damage_to"]:
            if t["name"] in TYPE_ENUM:
                entry[t["name"]] = 2.0
        for t in r["half_damage_to"]:
            if t["name"] in TYPE_ENUM:
                entry[t["name"]] = 0.5
        for t in r["no_damage_to"]:
            if t["name"] in TYPE_ENUM:
                entry[t["name"]] = 0.0
        relations[attacker] = entry
    return relations


# --------------------------------------------------------------------
# .tres writers

def write_species_tres(s: Dict[str, Any]) -> Path:
    dex = s["dex"]
    filename = f"{dex:03d}_{s['name']}.tres"
    path = SPECIES_DIR / filename

    front_path_rel = f"res://assets/sprites/pokemon/front_{dex:03d}.png"
    back_path_rel = f"res://assets/sprites/pokemon/back_{dex:03d}.png"

    types_ints = [TYPE_ENUM[t] for t in s["types"]]
    types_str = ", ".join(str(v) for v in types_ints)

    # Map PokéAPI stat names to our .tres keys.
    bs = s["base_stats"]
    stats_line = (
        f"{{\"hp\": {bs['hp']}, \"atk\": {bs['attack']}, \"def\": {bs['defense']}, "
        f"\"spa\": {bs['special-attack']}, \"spd\": {bs['special-defense']}, \"spe\": {bs['speed']}}}"
    )

    growth_int = GROWTH_RATE_ENUM.get(s["growth_rate"], 0)

    content = (
        "[gd_resource type=\"Resource\" script_class=\"Species\" load_steps=4 format=3]\n\n"
        "[ext_resource type=\"Script\" path=\"res://scripts/data/species.gd\" id=\"1_script\"]\n"
        f"[ext_resource type=\"Texture2D\" path=\"{front_path_rel}\" id=\"2_front\"]\n"
        f"[ext_resource type=\"Texture2D\" path=\"{back_path_rel}\" id=\"3_back\"]\n\n"
        "[resource]\n"
        "script = ExtResource(\"1_script\")\n"
        f"dex_number = {dex}\n"
        f"species_name = \"{s['display_name']}\"\n"
        f"types = Array[int]([{types_str}])\n"
        f"base_stats = {stats_line}\n"
        f"catch_rate = {s['capture_rate']}\n"
        f"base_exp_yield = {s['base_exp']}\n"
        f"growth_rate = {growth_int}\n"
        "learnset = []\n"
        "front_sprite = ExtResource(\"2_front\")\n"
        "back_sprite = ExtResource(\"3_back\")\n"
        "evolutions = []\n"
        "abilities = []\n"
    )
    path.write_text(content)
    return path


def write_move_tres(m: Dict[str, Any]) -> Path:
    filename = m["name"].replace("-", "_") + ".tres"
    path = MOVES_DIR / filename

    type_int = TYPE_ENUM[m["type"]]
    cat_int = CATEGORY_ENUM[m["category"]]

    content = (
        "[gd_resource type=\"Resource\" script_class=\"Move\" load_steps=2 format=3]\n\n"
        "[ext_resource type=\"Script\" path=\"res://scripts/data/move.gd\" id=\"1_script\"]\n\n"
        "[resource]\n"
        "script = ExtResource(\"1_script\")\n"
        f"move_name = \"{m['display_name']}\"\n"
        f"type = {type_int}\n"
        f"category = {cat_int}\n"
        f"power = {m['power']}\n"
        f"accuracy = {m['accuracy']}\n"
        f"pp = {m['pp']}\n"
        f"priority = {m['priority']}\n"
    )
    path.write_text(content)
    return path


def write_type_chart_tres(relations: Dict[str, Dict[str, float]]) -> Path:
    # Flatten to "atk_id:def_id" keyed entries.
    entries: List[Tuple[str, float]] = []
    for attacker, defs in relations.items():
        a_id = TYPE_ENUM[attacker]
        for defender, mult in defs.items():
            d_id = TYPE_ENUM[defender]
            entries.append((f"{a_id}:{d_id}", mult))
    entries.sort()

    lines = ["{"]
    for i, (k, v) in enumerate(entries):
        sep = "," if i < len(entries) - 1 else ""
        lines.append(f"\t\"{k}\": {v}{sep}")
    lines.append("}")
    relations_literal = "\n".join(lines)

    content = (
        "[gd_resource type=\"Resource\" script_class=\"TypeChart\" load_steps=2 format=3]\n\n"
        "[ext_resource type=\"Script\" path=\"res://scripts/data/type_chart.gd\" id=\"1_script\"]\n\n"
        "[resource]\n"
        "script = ExtResource(\"1_script\")\n"
        f"relations = {relations_literal}\n"
    )
    TYPE_CHART_PATH.write_text(content)
    return TYPE_CHART_PATH


# --------------------------------------------------------------------
# Main

def main() -> int:
    SPRITES_DIR.mkdir(parents=True, exist_ok=True)
    SPECIES_DIR.mkdir(parents=True, exist_ok=True)
    MOVES_DIR.mkdir(parents=True, exist_ok=True)

    print("Fetching type chart...")
    relations = fetch_type_relations()
    tc_path = write_type_chart_tres(relations)
    print(f"  wrote {tc_path.relative_to(REPO_ROOT)}")

    print("\nFetching species...")
    for dex in SPECIES_IDS:
        s = fetch_species(dex)
        front = SPRITES_DIR / f"front_{dex:03d}.png"
        back = SPRITES_DIR / f"back_{dex:03d}.png"
        print(f"  #{dex:03d} {s['display_name']}: types={s['types']}, stats={s['base_stats']}")
        download_binary(s["front_url"], front)
        download_binary(s["back_url"], back)
        path = write_species_tres(s)
        print(f"    -> {path.relative_to(REPO_ROOT)}, front {front.name}, back {back.name}")

    print("\nFetching moves...")
    for name in MOVE_NAMES:
        m = fetch_move_gen3(name)
        path = write_move_tres(m)
        print(
            f"  {m['display_name']}: type={m['type']}, cat={m['category']}, "
            f"power={m['power']}, acc={m['accuracy']}, pp={m['pp']} -> {path.relative_to(REPO_ROOT)}"
        )

    print("\nDone. Run `godot --headless --import` to register the new sprite textures.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
