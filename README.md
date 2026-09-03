# U.S. Long-Term Care Access Decision-Support System

**AI-enabled demand forecasting and access modelling for long-term care, at census-tract resolution.**

Author: **Edoseawe Godwin Okoduwa**, MHSA, CPH
PhD Candidate, Public & Community Health, Medical College of Wisconsin
[ORCID](https://orcid.org/0009-0009-8678-3176) · [Google Scholar](https://scholar.google.com/citations?user=DV4mqtYAAAAJ&hl=en)

---

## What this is

Federal long-term care (LTC) planning instruments, HPSA designations, MUA/P, and CMS
facility databases, are **category-specific, retrospective, and reported at macro
geographies**. None of them model whether an older adult in a *specific neighborhood*
can actually reach appropriate care, and none forecast where access will fail next.

This repository implements a decision-support system that addresses those three gaps:

| Gap in existing federal tools | What this system does |
|---|---|
| No LTC-specific shortage designation | Constructs an LTC Demand Index (LDI-T) plus service-type sub-indices for nursing facilities, home health, and adult day services |
| Retrospective only | Forecasts tract-level demand annually 2025 to 2035 under three documented scenarios |
| Macro-geography (county/state) | Operates at **census-tract** resolution across all tracts in the study area |
| Models supply, not access | Weights supply against demand, care need intensity, isolation, disability, and poverty barriers |

Output is an interactive web decision-support interface intended for state health
departments, county aging offices, ADRCs, and provider networks.

---

## Data basis, please read

This distinction is maintained rigorously throughout the codebase, the interface, and
the documentation.

**Observed data.** All baseline feature values are real, publicly available federal data:

| Feature | Source |
|---|---|
| Tract boundaries | U.S. Census Bureau TIGER/Line Cartographic Boundary Files (2022) |
| Population, age structure | Census ACS 5-Year 2022, Table B01001 |
| Median household income | Census ACS 5-Year 2022, Table B19013 |
| Poverty | Census ACS 5-Year 2022, Table B17001 |
| 65+ living alone | Census ACS 5-Year 2022, Table B09021 |
| Disability (65+) | Census ACS 5-Year 2022, Table B18101 |
| Nursing facility beds | CMS Care Compare / Provider of Services |
| Chronic disease prevalence | CDC PLACES (tract-level model-based estimates) |

**Projected data.** All 2025 to 2035 values are **scenario projections**, not measurements.
They are produced by applying documented federal trend assumptions (SSA demographic
projections, CMS facility closure rates, PHI direct-care workforce projections, BRFSS
disability trends) to observed 2022 baselines. Three scenarios, Baseline, Optimistic,
Pessimistic, are reported so that outputs remain actionable under uncertainty rather
than anchored to a single point estimate.

Note that CDC PLACES values are themselves small-area model-based estimates, not direct
measurements; this is documented in [`docs/DATA_SOURCES.md`](docs/DATA_SOURCES.md).

---

## Quick start

### Prerequisites

- R ≥ 4.2
- A free Census API key: https://api.census.gov/data/key_signup.html

```r
install.packages(c(
  "tidyverse","tidycensus","tigris","sf","httr","jsonlite",
  "tidymodels","ranger","xgboost","stacks","openxlsx","patchwork","scales"
))

# one time only
tidycensus::census_api_key("YOUR_KEY_HERE", install = TRUE)
```

### Run

```r
setwd("path/to/ltc-dss")

source("R/01_fetch_real_data.R")   # ~3-8 min: downloads real federal data
source("R/02_model.R")             # ~2-5 min: trains ensemble, exports payload
```

### View

The interface loads its geometry over HTTP and **will not work if opened directly
from disk** (`file://` blocks `fetch`). Serve it locally:

```bash
python3 -m http.server 8000
# then open http://localhost:8000
```

---

## Repository layout

```
ltc-dss/
├── index.html              interactive decision-support interface
├── README.md               this file
├── SETUP.md                reproducing the pipeline from scratch
├── LICENSE                 MIT
├── R/
│   ├── 01_fetch_real_data.R    federal data acquisition (Census, CMS, CDC)
│   └── 02_model.R              LDI-T construction, ensemble, forecasting
├── docs/
│   ├── HOW_IT_WORKS.md         plain-language explanation of the method
│   ├── METHODOLOGY.md          index construction, model spec, validation
│   ├── DATA_SOURCES.md         full provenance and known limitations
│   └── DEVELOPMENT_LOG.md      how the system was built, what remains
├── data/
│   ├── wi_tracts.geojson       real tract boundaries        [generated]
│   ├── tract_features.rds      real feature table           [generated]
│   └── dss_payload.json        interface data payload       [generated]
└── outputs/
    └── ltc_results.xlsx        8-sheet analyst workbook     [generated]
```

Generated artifacts are not committed. Run the two scripts in `R/` to reproduce
them. Note that `index.html` is self-contained and does not require them; the
generated files let you verify or extend the pipeline.

---

## Method summary

**LDI-T** is a weighted composite of eight min-max normalised components:

```
LDI_T = 0.25·age + 0.20·projected_age + 0.15·bed_gap + 0.12·care_need_intensity
      + 0.10·hha_gap + 0.08·disability + 0.06·isolation + 0.04·adl_limitation
```

Service-type sub-indices re-weight the same components against the dominant access
barrier for each service type (bed scarcity for nursing facilities, coverage and
workforce for home health, poverty and isolation for adult day services).

A **stacked ensemble** (Random Forest via `ranger` + Gradient Boosting via `xgboost`,
blended with `stacks`) is trained on an 80/20 split with 5-fold cross-validation, then
applied to trend-adjusted feature vectors to generate annual forecasts. Risk tiers use
fixed quantile thresholds from the baseline year so tier assignment stays comparable
across projection years.

Full specification, weight justification, and validation results:
[`docs/METHODOLOGY.md`](docs/METHODOLOGY.md).

---

## Limitations

Stated plainly, because a planning tool that overstates its certainty is worse than none:

1. **Projections are scenario estimates.** Long-range demographic and facility-supply
   projections carry substantial uncertainty. Three scenarios are reported for this reason.
2. **Nursing facility beds are resolved at county level** and distributed to tracts;
   true point-location catchment modelling (E2SFCA with road-network travel times) is
   implemented in the companion Wisconsin study and is being integrated here.
3. **ADL limitation uses a disability proxy** pending NHATS or MDS linkage.
4. **Index weights are theory-driven**, informed by the LTC access literature and the
   Wisconsin statewide analysis. They have not yet been empirically optimised against
   observed utilisation outcomes; sensitivity analysis is planned.
5. **CDC PLACES estimates are modelled**, not directly measured.

---

## Related work

This system extends a statewide analysis of long-term care access disparities in
Wisconsin, conducted in collaboration with the Wisconsin Department of Health Services
and funded through the Advancing a Healthier Wisconsin Endowment. That work produced a
63-page statewide disparities report and a deployed interactive mapping platform, and
was presented at the American Public Health Association Annual Meeting (November 2025,
Washington D.C.).

---

---

## What is in this repository

| Path | Contents |
|---|---|
| `index.html` | The decision-support interface. Self-contained; open it directly in a browser. |
| `R/01_fetch_real_data.R` | Retrieves tract boundaries and features from Census, CMS and CDC. |
| `R/02_model.R` | Builds the demand index, trains the ensemble, generates forecasts. |
| `docs/HOW_IT_WORKS.md` | Plain-language explanation of the method and what it found. |
| `docs/METHODOLOGY.md` | Index construction, model specification, validation status. |
| `docs/DATA_SOURCES.md` | Full data provenance, vintages and known limitations. |
| `docs/DEVELOPMENT_LOG.md` | How the system was built and what remains outstanding. |
| `SETUP.md` | Reproducing the pipeline from scratch. |
| `LICENSE` | MIT. |

Nothing in this repository requires a licensed dataset, a paid API or
institutional access. A free Census API key is the only credential needed to
reproduce the pipeline.

## Reusing this work

The methodology is state-agnostic. The pipeline is parameterised by state FIPS
code, and every input is a federal dataset published for all 50 states on the
same schema. Applying it to another state is a configuration change, not a
redesign.

If you adapt this for your jurisdiction, please read `docs/DATA_SOURCES.md`
first. It documents the limitations that constrain how the outputs should be
interpreted, particularly around forecast uncertainty and the absence of
external validation.

## License

MIT, see [`LICENSE`](LICENSE). Released openly so that state, local, tribal, and
territorial health departments can adapt the methodology to their own jurisdictions.

## Citation

```bibtex
@software{okoduwa_ltc_dss_2026,
  author  = {Okoduwa, Edoseawe Godwin},
  title   = {U.S. Long-Term Care Access Decision-Support System},
  year    = {2026},
  url     = {https://github.com/USERNAME/ltc-dss}
}
```
