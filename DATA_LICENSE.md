# Data licence

The results, aggregate data, figure data, review files and the content of the atlas and the policy brief in this repository, and any figures drawn from them, are licensed under the Creative Commons Attribution 4.0 International licence (CC BY 4.0), https://creativecommons.org/licenses/by/4.0/.

Copyright (c) 2026 Siddalingaiah H S.

This covers:

- `papers/D/results.json`, `papers/D/traceability.csv`, `papers/D/output/` and `papers/D/figures/data/` (results, aggregate tables and figure data);
- `papers/D/review/` (protocol, screening, extraction, evidence-gap map and PRISMA counts of the rapid review; bibliographic fields of the records are facts about the publications);
- `data/derived/synthesis/` (harvested companion estimates and outlooks, the digitised forecast archive, NFHS-5 state indicators and the input manifest);
- `data/derived/` (ENSO and climate tables, the companion analyses' state-year model inputs and NFHS state counts);
- `docs/index.html` and `papers/D/brief/` (the atlas page and the policy brief).

Attribution: cite the paper (see README.md) or this repository (CITATION.cff), and the original sources below.

**GADM exception.** GADM-derived identifiers, names and boundaries (the GADM state and district codes such as `unit_id` members and `gid1_members`, the names taken from GADM, and the state and national outlines embedded in `docs/index.html` and drawn in the figures, including the disputed-area units from the GADM Pakistan and China files) remain subject to the GADM licence (free for academic and other non-commercial use; redistribution or commercial use needs GADM's permission, https://gadm.org/license.html), not to CC BY 4.0. India's external boundary is drawn to include the areas claimed by India; it is not authenticated by the Survey of India.

## Third-party sources

CC BY 4.0 applies to the aggregation and processing in this repository. The original data remain subject to their producers' terms, and users must also attribute them.

| Source | Producer | Terms |
|---|---|---|
| Oceanic Niño Index, Relative ONI, Niño-3.4 | NOAA Climate Prediction Center | US Government public data; attribute NOAA CPC |
| ENSO forecast plume figures (`data/raw/forecasts/iri/`, SVG) and the digitised forecast archive | International Research Institute for Climate and Society (IRI), Columbia Climate School | IRI's figures, included unmodified with attribution so that the digitised values can be checked; attribute IRI and follow its terms of use for any other reuse |
| Gridded daily rainfall (0.25°) and temperature (1°), as district and unit aggregates | India Meteorological Department (IMD), Pune | IMD gridded-data terms; raw grids are not redistributed. Cite Pai DS et al. 2014, MAUSAM 65(1):1–18 and Srivastava AK et al. 2009, Atmos Sci Lett 10:249–254 |
| National Family Health Survey (NFHS-5), 2019–21: state factsheet values; national report (FR375) | International Institute for Population Sciences (IIPS), Mumbai, Ministry of Health and Family Welfare, and ICF; hosted by the DHS Program | Published values; cite IIPS and ICF. NFHS microdata are not redistributed |
| State malaria, dengue and recorded heat-death series (`data/derived/model/`) | Public Indian government series as compiled by the companion analyses (national vector-borne disease programme reports; National Crime Records Bureau) | See the companion repositories for the exact sources and terms |
| Administrative boundaries | GADM 4.1 (https://gadm.org) | GADM licence (see above); the GeoPackage itself is not redistributed |
