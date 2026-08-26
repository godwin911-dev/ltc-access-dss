# Data Sources and Provenance

Every input to this system is public federal data. This document records exactly what
is used, where it comes from, what vintage it is, and what its known limitations are.

The central distinction maintained throughout: **observed** values are measurements or
official estimates; **projected** values are model outputs produced by applying trend
assumptions to observed baselines. Projections are not measurements and are never
presented as such.

---

## 1. Observed inputs

### 1.1 Census tract boundaries

| | |
|---|---|
| Source | U.S. Census Bureau, TIGER/Line Cartographic Boundary Files |
| Vintage | 2022 |
| Access | `tigris::tracts(state, cb = TRUE, year = 2022)` |
| Geography | Census tract, all tracts with `ALAND > 0` |
| Processing | Reprojected to EPSG:4326; simplified with `sf::st_simplify(dTolerance = 0.0005, preserveTopology = TRUE)` for web delivery |

Water-only and purely statistical tracts (`ALAND == 0`) are excluded, since they contain
no resident population and would distort accessibility measures.

Simplification reduces file size for browser delivery. It slightly generalises boundary
vertices; it does not alter tract identity, adjacency, or any computed value, all of
which are keyed on GEOID rather than geometry.

### 1.2 American Community Survey 5-Year Estimates

| | |
|---|---|
| Source | U.S. Census Bureau, ACS 5-Year Estimates |
| Vintage | 2018 to 2022 (release year 2022) |
| Access | `tidycensus::get_acs(geography = "tract", survey = "acs5")` |

| Variable | ACS Table | Derivation |
|---|---|---|
| Total population | B01003_001 | direct |
| Population 65+ | B01001_020:025, B01001_044:049 | summed across sex-by-age cells |
| % Age 65+ |, | `100 × pop_65plus / pop_total` |
| Median household income | B19013_001 | direct, expressed in $1,000s |
| % Below poverty | B17001_002 / B17001_001 | ratio |
| % 65+ living alone | B09021_022 / B09021_001 | ratio |
| Disability, 65+ | B18101_015, B18101_034 | summed male + female |
| Households without vehicle | B08201_002 | direct |

**Limitations.** ACS 5-year estimates are survey-based and carry margins of error that
widen in low-population tracts. Margins of error are retrieved but not currently
propagated through the index; this is a known limitation and a planned enhancement.
The 5-year window means values represent a pooled 2018 to 2022 period, not a single year.

### 1.3 CMS nursing facility supply

| | |
|---|---|
| Source | Centers for Medicare & Medicaid Services, Care Compare / Provider of Services |
| File | `NH_ProviderInfo.csv` |
| Access | https://data.cms.gov/provider-data/topics/nursing-homes |
| Vintage | Current release at time of run |

Certified bed counts are aggregated to county and expressed as **beds per 1,000
residents aged 65+**, then joined to tracts within each county.

**Limitation, significant.** This is a county-level supply measure distributed to
tracts, not a tract-level measure. It cannot distinguish a tract adjacent to a facility
from one at the far edge of the same county. True point-location catchment modelling
using Enhanced Two-Step Floating Catchment Area (E2SFCA) with road-network travel times
is implemented in the companion Wisconsin statewide study and is being integrated here.
Until that integration is complete, the bed-gap component should be read as a county
characteristic, not a neighbourhood one.

### 1.4 CDC PLACES

| | |
|---|---|
| Source | CDC PLACES: Local Data for Better Health, Census Tract Data |
| Access | Socrata API, dataset `cwsq-ngmh` |
| Measures used | Diabetes, arthritis, stroke, COPD (crude prevalence) |

Combined into a chronic disease index (`cdi`) as the mean of standardised prevalences.

**Limitation.** PLACES values are **small-area model-based estimates**, produced by
multilevel regression and poststratification from BRFSS responses. They are not direct
tract-level measurements. They inherit the modelling assumptions of the PLACES
methodology, and uncertainty is not published at tract level in a form that can be
readily propagated.

---

## 2. Projected inputs

All projections apply documented trend assumptions to observed 2022 baselines. Each
assumption below is sourced; none are invented.

| Parameter | Baseline | Optimistic | Pessimistic | Basis |
|---|---|---|---|---|
| Nursing facility beds, change to 2035 | −12% | +5% | −18% | CMS facility closure rates 2020 to 2024 |
| Direct-care workforce deficit | +20% | +8% | +30% | PHI direct-care workforce projections |
| Home health coverage | −7% | +2% | −12% | CMS rural HHA contraction |
| Disability prevalence, 65+ | +8% | +4% | +12% | BRFSS age-adjusted trend |
| Share aged 65+ | Linear interpolation to SSA 2035 projection (+33%) | | | SSA demographic projections |

**How to read the scenarios.** Baseline continues observed recent trends. Optimistic
assumes policy intervention slows or reverses facility contraction and workforce
shortage. Pessimistic assumes acceleration of current trends. Scenario spread is the
honest expression of uncertainty; a single-point projection would overstate confidence.

Long-range projections at small-area geography are inherently uncertain. Tract-level
demographic change is influenced by migration, housing development, and local economic
shifts that no statewide trend assumption captures. **Forecast outputs are planning
aids, not predictions.**

---

## 3. Known limitations, consolidated

1. ACS margins of error are not propagated into the composite index.
2. Nursing facility supply is county-resolved, not tract-resolved.
3. ADL limitation uses a disability proxy pending NHATS or MDS linkage.
4. Home health coverage is currently derived rather than measured directly; direct CMS
   Home Health Compare integration is in progress.
5. CDC PLACES inputs are themselves modelled estimates.
6. Index weights are theory-driven and have not been empirically optimised against
   observed utilisation outcomes. Sensitivity analysis is planned.
7. Projections extend ten years at tract level, where uncertainty is substantial.

These are stated openly because a decision-support tool that conceals its uncertainty
misleads the planners who rely on it. Each is a specific, addressable item on the
development roadmap rather than a permanent constraint.

---

## 4. Reproducibility

All data is public and free. No licensed, proprietary, or restricted-access source is
used. Anyone with R and a free Census API key can reproduce every figure in this
repository from scratch by running the two scripts in `R/`.

`set.seed(2024)` is set. Ensemble training remains mildly stochastic; re-runs may vary
performance metrics within approximately ±0.005.
