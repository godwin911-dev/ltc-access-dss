# Development Log

Record of how the Long-Term Care Access Decision-Support System reached its
current state. Maintained so that the provenance of every component is
traceable, and so that anyone reviewing the work can see what was built, what
was replaced, and what remains outstanding.

---

## Phase 0, Origin (2024 to 2025)

**Wisconsin statewide long-term care access analysis**
Medical College of Wisconsin, in collaboration with the Wisconsin Department of
Health Services. Funded by a competitive Advancing a Healthier Wisconsin
Endowment grant.

Outputs:
- 63-page statewide disparities report
- Interactive web mapping platform for LTC resource navigation
- Census-tract-level geospatial analysis using E2SFCA accessibility methods
- Finding: 7.0% of Wisconsin older adults live in residential LTC deserts,
  18.7% in non-residential deserts, 4.2% in both, none visible in the
  statewide aggregates published by the Wisconsin LTC Scorecard

Presented at the American Public Health Association Annual Meeting,
November 2025, Washington D.C. (oral presentation, competitive abstract review).

---

## Phase 1, Forecasting prototype (May 2026)

First attempt to extend the descriptive Wisconsin analysis into predictive
modelling.

**Built:**
- LTC Demand Index (LDI-T): eight-component weighted composite
- Service-type sub-indices for nursing facilities, home health, adult day services
- Stacked ensemble: Random Forest (`ranger`) + Gradient Boosting (`xgboost`),
  blended via `stacks`
- Annual demand forecasts 2025 to 2035
- Three-scenario architecture (Baseline, Optimistic, Pessimistic)
- Early-warning classification for tracts escalating toward critical shortage
- Browser-based decision-support interface

**Data basis:** calibrated model data. Feature values generated from parametric
distributions (Normal, Beta, Gamma, Log-Normal) matched to published federal
summary statistics. Tract geometry was schematic grid cells subdivided from
county bounding boxes.

**Rationale at the time:** standard practice for demonstrating that an ML
architecture is executable before investing in data acquisition.

**Limitation, in hindsight:** the interface rendered synthetic grid cells on a
real basemap with Census-formatted identifiers. Although the code header
disclosed the synthetic basis, the interface itself did not, and a reader could
reasonably have mistaken the display for an analysis of actual Wisconsin
geography.

---

## Phase 2, Rebuild on observed federal data (August 2026)

Undertaken to move the system from methodological demonstration onto observed
federal data, so that outputs describe actual Wisconsin geography and populations.

### 2.1 Data acquisition pipeline

New script `R/01_fetch_real_data.R`. Retrieves, from public federal sources:

| Component | Source | Method |
|---|---|---|
| Tract boundaries | Census TIGER/Line 2022 cartographic files | `tigris::tracts(cb = TRUE)` |
| Population, age structure | ACS 5-Year 2018 to 2022, B01001 | `tidycensus::get_acs()` |
| Median household income | ACS B19013 | `tidycensus` |
| Poverty | ACS B17001 | `tidycensus` |
| 65+ living alone | ACS B09021 | `tidycensus` |
| Disability, 65+ | ACS B18101 | `tidycensus` |
| Nursing facility beds | CMS Care Compare provider records | `NH_ProviderInfo.csv` |
| Chronic disease prevalence | CDC PLACES tract estimates | Socrata API, dataset `cwsq-ngmh` |

Water-only tracts (`ALAND = 0`) excluded. Geometry reprojected to EPSG:4326 and
simplified for browser delivery; simplification generalises boundary vertices
only and does not alter tract identity or any computed value.

**Result:** 1,526 real census tracts across all 72 Wisconsin counties, replacing
1,409 synthetic grid cells.

### 2.2 Issues encountered and resolved

Recorded because they affect data quality and a reviewer may wish to verify how
they were handled.

**CMS endpoint moved.** The published bulk-download URL returned HTTP 404. The
script now checks for a local `NH_ProviderInfo.csv` before attempting network
retrieval, and caches successful downloads.

**County join failure.** Tract-level records initially carried the tract name
(`"Census Tract 28"`) in the county field rather than the county name, causing
the CMS bed-supply join to fail silently and leaving nursing facility capacity
100% missing. Resolved by deriving county from the GEOID county FIPS segment
(characters 3 to 5) against the Wisconsin county code table. All 72 counties now
resolve; nursing bed data is 1.4% missing, confined to tracts with no resident
elderly population.

**Data quality after resolution:**

| Variable | Missing |
|---|---|
| Population, age structure | 0.0% |
| Income, poverty, isolation | 0.1% |
| Disability, ADL proxy | 0.3% |
| Chronic disease index | 0.1% |
| Nursing facility beds | 1.4% |

### 2.3 Model results on real data

Held-out test set, 80/20 split, 5-fold cross-validation:

| Model | R² | RMSE | MAE |
|---|---|---|---|
| Random Forest | 0.9841 | 0.9455 | 0.6532 |
| Gradient Boosting | 0.9960 | 0.4716 | 0.3005 |
| **Stacked Ensemble** | **0.9961** | **0.4805** | **0.2927** |

Substantive finding: **371 tracts (24.3%) currently below the Critical threshold
are projected to cross it by 2035** under baseline assumptions. Statewide
critical-tract count rises from 383 to 752.

**Interpretation caveat.** The ensemble is trained to predict LDI-T from its own
constituent features. A high R² indicates the model has learned the index
structure well enough to extrapolate it to trend-adjusted inputs. It is not
evidence that LDI-T correctly measures real-world access. External validation
against observed utilisation has not been performed.

### 2.4 Interface corrections

Several controls in the Phase 1 interface were found to be non-functional:

| Control | Defect | Resolution |
|---|---|---|
| Map scenario selector | Read into a variable, never applied to rendering | Wired to projection; scenario factors derived from the statewide forecast |
| Year slider + metric | Always recoloured by score, ignoring the selected metric | Metric, year and scenario now compose correctly |
| Trajectory scenario | Read into a variable, never applied to curve arithmetic | Applied; numeric readout added because the effect is small |
| Sidebar statistics | Fixed to the 2025 baseline | Recalculates for the active year and scenario |

Added: a status banner reporting the active service, metric, year and scenario;
a numeric readout of scenario endpoints on the forecast tab; provenance
statements in the interface header and Model & Methods tab.

### 2.5 Publication

Repository released under the MIT licence with complete methodology
documentation, data provenance, and stated limitations. The pipeline is
reproducible by any third party from freely available federal data with a free
Census API key.

---

## Current state

**Working:**
- 1,526 real census tracts, all 72 Wisconsin counties, observed federal data
- LDI-T composite and three service-type sub-indices
- Stacked ensemble forecasting, 2025 to 2035
- Three-scenario projection
- Early-warning identification of escalating tracts
- Eight-panel interactive interface
- Analyst workbook, eight sheets
- Reproducible open-source pipeline

**Not yet working:**

| Item | Status |
|---|---|
| Service-specific forecast trajectories | Currently scaled from the composite, not modelled independently |
| Tract-level accessibility (E2SFCA) | Bed supply resolved at county level; road-network catchment not integrated |
| ADL measurement | Disability proxy pending NHATS or MDS linkage |
| Home health coverage | Derived rather than measured; CMS Home Health Compare not yet integrated |
| ACS margins of error | Not propagated into index uncertainty |
| Index weight sensitivity analysis | Not performed |
| External validation | Not performed |
| Multi-state coverage | Wisconsin only |

---

## Roadmap

1. **Service-specific forecasting**, re-run the ensemble against each sub-index
   with its own trend-adjusted feature vector, replacing the current
   proportional approximation.
2. **E2SFCA integration**, port road-network catchment modelling from the
   Wisconsin statewide study; replace county-resolved bed supply with true
   tract-level accessibility. CMS provider records include facility latitude and
   longitude, which makes point-location catchment modelling feasible without
   additional data acquisition.
3. **Multi-state expansion**, Minnesota, Illinois, Iowa. The pipeline is
   parameterised by state FIPS; extension requires no methodological change.
4. **Uncertainty propagation**, carry ACS margins of error into index
   confidence bands.
5. **External validation**, test LDI-T against observed utilisation and
   unmet-need outcomes; compare designations against HPSA and MUA/P.
6. **Weight sensitivity analysis**, test alternative weighting schemes and,
   where data permits, optimise empirically.
7. **National framework**, approximately 74,000 tracts across 50 states.

---

## Known issue in the codebase

`R/02_model.R` exports a payload that omits several keys the web interface
requires (`score_lookup`, `tier_lookup`, `feature_weights`, `yearly_means`,
`yearly_critical`, `disparity`, `tier_thresholds`, `county_service`). The
deployed interface has a complete payload embedded directly, so the system
functions as shipped. The export schema must be corrected before extending to
additional states. Note also that `tier_thresholds` must be exported as named
objects (`q25`, `q50`, `q75`) rather than arrays, and disparity groups must be
dict-keyed with `mean`, `n` and `n_crit` fields.
