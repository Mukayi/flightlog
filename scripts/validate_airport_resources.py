#!/usr/bin/env python3
"""Validate the airport resources copied into a packaged FlightLog app."""

from __future__ import annotations

import json
import sys
from pathlib import Path


def validate(resources: Path) -> tuple[int, int]:
    airports_path = resources / "airports.json"
    license_path = resources / "AIRPORT_DATA_LICENSE.md"
    airports = json.loads(airports_path.read_text(encoding="utf-8"))
    if not isinstance(airports, list) or len(airports) < 9_000:
        raise ValueError("airport resource must contain at least 9000 airports")
    if not all(
        isinstance(airport, dict)
        and isinstance(airport.get("aliases"), list)
        for airport in airports
    ):
        raise ValueError("every airport resource row must contain aliases")
    alias_airport_count = sum(bool(airport["aliases"]) for airport in airports)
    if alias_airport_count == 0:
        raise ValueError("airport resource must contain aliases")

    license_text = license_path.read_text(encoding="utf-8")
    for marker in ("2026-08-19", "Wikidata", "CC0 1.0"):
        if marker not in license_text:
            raise ValueError(f"airport license must contain {marker}")
    return len(airports), alias_airport_count


def main() -> int:
    if len(sys.argv) != 2:
        print(
            "usage: validate_airport_resources.py <Resources directory>",
            file=sys.stderr,
        )
        return 2
    try:
        airport_count, alias_airport_count = validate(Path(sys.argv[1]))
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(error, file=sys.stderr)
        return 1
    print(f"{airport_count} airports; {alias_airport_count} with aliases")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
