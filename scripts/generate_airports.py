#!/usr/bin/env python3
"""Generate the bundled airport database from OurAirports CSV exports."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import re
import sys
import urllib.request
from pathlib import Path
from typing import TextIO

OURAIRPORTS_REVISION = "c2b0dbed1ce4444edb9a565b7532968ec48bf124"
OURAIRPORTS_RAW_ROOT = (
    "https://raw.githubusercontent.com/davidmegginson/ourairports-data/"
    f"{OURAIRPORTS_REVISION}"
)
AIRPORTS_URL = f"{OURAIRPORTS_RAW_ROOT}/airports.csv"
AIRPORTS_SHA256 = (
    "8f1be28f939a9f6305306b00211debb621de4c25846fbe1e4b3c52685f00b6bf"
)
COUNTRIES_URL = f"{OURAIRPORTS_RAW_ROOT}/countries.csv"
COUNTRIES_SHA256 = (
    "2a9dbee691125b0cdb8ceb5fe227c48c903f99c488963b8e53e2ab366521c639"
)
DEFAULT_ALIASES_PATH = (
    Path(__file__).resolve().parent / "data" / "wikidata_zh_airport_aliases.json"
)


def open_csv(
    path: Path | None,
    url: str,
    expected_sha256: str | None = None,
) -> TextIO:
    if path is not None:
        return path.open("r", encoding="utf-8-sig", newline="")
    with urllib.request.urlopen(url) as response:
        data = response.read()
    if (
        expected_sha256 is not None
        and hashlib.sha256(data).hexdigest() != expected_sha256
    ):
        raise SystemExit(f"source SHA256 mismatch: {url}")
    return io.StringIO(data.decode("utf-8-sig"))


def country_names(path: Path | None) -> dict[str, str]:
    with open_csv(path, COUNTRIES_URL, COUNTRIES_SHA256) as stream:
        return {
            row["code"].strip().upper(): row["name"].strip()
            for row in csv.DictReader(stream)
        }


def cleaned_aliases(values: list[str]) -> list[str]:
    aliases: list[str] = []
    seen: set[str] = set()
    for value in values:
        alias = " ".join(value.split())
        key = alias.casefold()
        if not alias or key in seen:
            continue
        seen.add(key)
        aliases.append(alias)
    return aliases


def keyword_aliases(value: str) -> list[str]:
    return cleaned_aliases(re.split(r"[,;|，；\n]+", value))


def external_aliases(path: Path | None) -> dict[str, list[str]]:
    if path is None:
        return {}
    payload = json.loads(path.read_text(encoding="utf-8"))
    airports = payload.get("airports", {})
    return {
        str(iata).strip().upper(): cleaned_aliases(
            [str(alias) for alias in aliases]
        )
        for iata, aliases in airports.items()
        if isinstance(aliases, list)
    }


def generate(
    airports_path: Path | None,
    countries_path: Path | None,
    aliases_path: Path | None = None,
    timezone_finder=None,
) -> tuple[list[dict[str, object]], int]:
    if timezone_finder is None:
        try:
            from timezonefinder import TimezoneFinder
        except ImportError as error:
            raise SystemExit(
                "timezonefinder is required for generation: "
                "python3 -m pip install -r scripts/requirements-airports.txt"
            ) from error

        timezone_finder = TimezoneFinder(in_memory=True)

    countries = country_names(countries_path)
    aliases_by_iata = external_aliases(aliases_path)
    generated: list[dict[str, object]] = []
    utc_fallbacks = 0

    with open_csv(airports_path, AIRPORTS_URL, AIRPORTS_SHA256) as stream:
        for row in csv.DictReader(stream):
            iata = row["iata_code"].strip().upper()
            if row["type"].strip() == "closed" or not iata:
                continue

            latitude = float(row["latitude_deg"])
            longitude = float(row["longitude_deg"])
            time_zone = timezone_finder.timezone_at(
                lng=longitude,
                lat=latitude,
            )
            if time_zone is None:
                time_zone = "Etc/UTC"
                utc_fallbacks += 1

            country_code = row["iso_country"].strip().upper()
            aliases = cleaned_aliases(
                keyword_aliases(row.get("keywords", ""))
                + aliases_by_iata.get(iata, [])
            )
            generated.append(
                {
                    "iata": iata,
                    "icao": row["gps_code"].strip().upper(),
                    "name": row["name"].strip(),
                    "city": row["municipality"].strip(),
                    "country": countries.get(country_code, country_code),
                    "countryCode": country_code,
                    "latitude": latitude,
                    "longitude": longitude,
                    "timeZoneID": time_zone,
                    "aliases": aliases,
                }
            )

    generated.sort(
        key=lambda airport: (
            str(airport["iata"]),
            str(airport["icao"]),
            str(airport["name"]),
        )
    )
    return generated, utc_fallbacks


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        type=Path,
        help="Directory containing airports.csv and countries.csv snapshots.",
    )
    parser.add_argument(
        "--airports-input",
        type=Path,
        help="Local airports.csv; downloads the current export when omitted.",
    )
    parser.add_argument(
        "--countries-input",
        type=Path,
        help="Local countries.csv; downloads the current export when omitted.",
    )
    parser.add_argument(
        "--aliases-input",
        type=Path,
        default=DEFAULT_ALIASES_PATH,
        help="Checked-in IATA-to-aliases JSON snapshot.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("Sources/FlightLog/Resources/airports.json"),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    airports_input = args.airports_input
    countries_input = args.countries_input
    if args.source is not None:
        airports_input = args.source / "airports.csv"
        countries_input = args.source / "countries.csv"

    airports, utc_fallbacks = generate(
        airports_input,
        countries_input,
        aliases_path=args.aliases_input,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(
            airports,
            ensure_ascii=False,
            separators=(",", ":"),
        )
        + "\n",
        encoding="utf-8",
    )
    print(
        f"Wrote {len(airports)} airports to {args.output} "
        f"({utc_fallbacks} Etc/UTC fallbacks)",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
