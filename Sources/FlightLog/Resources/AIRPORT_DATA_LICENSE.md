# Airport data notices

`airports.json` was generated on 2026-08-19 from the OurAirports
`airports.csv` and `countries.csv` exports:

- https://ourairports.com/data/
- https://davidmegginson.github.io/ourairports-data/airports.csv
- https://davidmegginson.github.io/ourairports-data/countries.csv

OurAirports states that its downloadable data is released to the Public
Domain. The generated resource excludes closed airports and rows without an
IATA code. OurAirports `keywords` are normalized into airport aliases.

Chinese airport and city aliases are merged from the checked-in
`scripts/data/wikidata_zh_airport_aliases.json` snapshot, retrieved on
2026-08-19. It primarily contains Chinese labels and aliases for IATA airports
in mainland China, Hong Kong, Macau, and Taiwan from Wikidata. Wikidata data is
released under Creative Commons CC0 1.0:

- https://www.wikidata.org/
- https://query.wikidata.org/
- https://creativecommons.org/publicdomain/zero/1.0/

Common Chinese names for major international hubs are a separately identified,
manually curated mapping of short factual airport names to IATA codes. They are
not represented as Wikidata-derived or covered by Wikidata's CC0 declaration;
the snapshot records their category and recording date separately.

The snapshot is used only at generation time. The application has no runtime
network dependency for airport search.

IANA time zone identifiers were computed from each airport coordinate with
`timezonefinder`. The package is MIT-licensed and uses geographic time zone
boundaries produced by `timezone-boundary-builder` from OpenStreetMap data.
That boundary data is made available under the Open Database License (ODbL);
OpenStreetMap contributors are credited at https://www.openstreetmap.org/copyright.

The generated JSON is redistributed with this notice. See:

- https://github.com/jannikmi/timezonefinder
- https://github.com/evansiroky/timezone-boundary-builder
- https://opendatacommons.org/licenses/odbl/
