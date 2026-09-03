# Methodology

## 1. Problem specification

Federal long-term care planning instruments share three structural limitations that this
system is designed to address.

**Category coverage.** Health Professional Shortage Area designations cover primary care,
mental health, and dental health. There is no equivalent shortage designation for
long-term care, despite LTC being among the fastest-growing categories of need.

**Temporal orientation.** HPSA and MUA/P designations are retrospective. They identify
where shortage exists now. Long-term care infrastructure, constructing a facility,
recruiting and training a direct-care workforce, expanding an HCBS waiver program, operates on multi-year lead times. A designation that appears only after shortage has
materialised arrives after the intervention window has closed.

**Access versus supply.** Existing instruments largely model provider-to-population
ratios. A ratio can tell you how many beds exist per thousand residents in a county. It
cannot tell you whether a specific older adult with limited mobility can reach one of
those beds, whether the facility has capacity, or whether the available care is
affordable and appropriate.

This system addresses all three: it is LTC-specific, forward-looking, and models access
barriers rather than supply counts alone.

---

## 2. LTC Demand Index (LDI-T)

### 2.1 Components

Eight components, each min-max normalised to 0 to 100 across the study area. Higher values
consistently indicate greater unmet demand pressure.

| Component | Symbol | Derivation | Direction |
|---|---|---|---|
| Current elderly share | `c_age` | normalise(% age 65+) | higher = more demand |
| Projected elderly share | `c_proj` | normalise(projected % 65+ 2035) | higher = more demand |
| Nursing facility bed gap | `c_bed` | 100 − normalise(beds per 1k 65+) | inverted: fewer beds = higher gap |
| Care need intensity | `c_wf` | normalise(chronic disease index) | higher = more care need per capita |
| Home health coverage gap | `c_hha` | 100 − normalise(HHA coverage) | inverted |
| Disability prevalence | `c_dis` | normalise(% disability 65+) | higher = more demand |
| Social isolation | `c_aln` | normalise(% 65+ living alone) | higher = less informal care |
| ADL limitation | `c_adl` | normalise(% ADL limitation) | higher = more intensive need |

### 2.2 Composite

```
LDI_T = 0.25·c_age + 0.20·c_proj + 0.15·c_bed + 0.12·c_wf
      + 0.10·c_hha + 0.08·c_dis + 0.06·c_aln + 0.04·c_adl
```

**Weight justification.** Weights are theory-driven, informed by the long-term care
access literature and by the Wisconsin statewide disparities analysis. The logic:

- Current and projected elderly share receive the largest combined weight (0.45) because
  age structure is the dominant determinant of LTC demand and is the input measured with
  greatest reliability.
- Supply-side gaps (bed gap, HHA gap) receive 0.25 combined, reflecting that supply
  constrains access but does not by itself determine need.
- Workforce deficit receives 0.12 as the binding constraint on service delivery capacity
  independent of physical infrastructure.
- Disability, isolation, and ADL limitation receive 0.18 combined as need-intensity
  modifiers.

**These weights have not been empirically optimised against observed utilisation
outcomes.** That is a stated limitation, not a hidden one. Sensitivity analysis across
alternative weighting schemes is a planned validation step. Users who prefer different
weights can modify them directly in `R/02_model.R`; the weight vector is a single
editable line.

### 2.3 Service-type sub-indices

The same components are re-weighted against the dominant access barrier for each service
type, because what constrains access to a nursing facility differs from what constrains
access to adult day services.

```
NF_score  = 0.35·c_bed + 0.25·c_age + 0.20·c_proj + 0.12·c_adl + 0.08·c_wf
HHA_score = 0.35·c_hha + 0.25·c_wf  + 0.20·c_age  + 0.12·c_aln + 0.08·c_dis
ADS_score = 0.30·poverty + 0.25·c_aln + 0.20·c_dis + 0.15·c_wf + 0.10·c_age
```

Nursing facilities are bed-constrained. Home health is coverage- and workforce-
constrained. Adult day services are constrained primarily by affordability and by
whether an isolated older adult can reach a program at all.

### 2.4 Risk tiers

Quartile thresholds computed once on the baseline year and held fixed across all
projection years:

| Tier | Threshold |
|---|---|
| Critical | ≥ 75th percentile |
| High | 50th to 75th |
| Moderate | 25th to 50th |
| Low | < 25th percentile |

Fixing thresholds at baseline is deliberate. If thresholds were recomputed each year,
a tract could remain in the same tier while its absolute demand rose sharply, since the
whole distribution shifts. Fixed thresholds make tier escalation across years meaningful.

---

## 3. Predictive model

### 3.1 Specification

| | |
|---|---|
| Target | LDI-T (continuous, 0 to 100) |
| Features | 10 tract-level predictors |
| Split | 80 / 20 train-test, stratified on LDI-T |
| Resampling | 5-fold cross-validation, stratified |
| Preprocessing | normalisation, near-zero-variance filter |

**Base learners**

- **Random Forest** (`ranger`): 500 trees; `mtry` and `min_n` tuned over a regular grid;
  permutation importance.
- **Gradient Boosting** (`xgboost`): 400 trees; `tree_depth`, `learn_rate`,
  `loss_reduction`, and `mtry` tuned over a 15-point Latin hypercube.

**Ensemble.** Stacked via `stacks`, blending base-learner predictions with LASSO
regularisation over a 20-point penalty grid.

### 3.2 Rationale

Random Forest captures threshold effects and interactions with resistance to
overfitting. Gradient boosting captures the non-linear supply-demand interactions that
matter most in identifying tracts where multiple pressures compound. Stacking them
typically outperforms either alone and provides a check: when base learners disagree
substantially, that disagreement is itself informative about prediction reliability.

### 3.3 Interpreting model fit

The model is trained to predict LDI-T from its constituent features. A high R² is
therefore expected and is **not evidence that the index correctly measures real-world
access**. It indicates the ensemble has learned the index structure well enough to
extrapolate it to trend-adjusted feature vectors, which is what the forecasting step
requires.

External validation against observed LTC utilisation and unmet-need outcomes is the
appropriate test of whether LDI-T measures what it claims to measure. That validation is
a planned next phase and has not yet been performed. This distinction is stated
explicitly to avoid overclaiming.

---

## 4. Forecasting

For each year *t* ∈ 2025…2035 and each scenario *s*, features are adjusted by a linear
interpolation factor `f = (t − 2025) / 10`:

```
pct_65[t]  = pct_65 · (1 − f) + proj_65 · f
nh_beds[t] = nh_beds · (1 + β_beds[s] · f)
cdi[t]     = min(10, cdi · (1 + β_cdi[s] · f))
hha_cov[t] = max(0,  hha_cov · (1 + β_hha[s] · f))
pct_dis[t] = min(100, pct_dis · (1 + β_dis[s] · f))
```

The fitted ensemble is then applied to the adjusted feature matrix. Scenario parameters
β are documented in [`DATA_SOURCES.md`](DATA_SOURCES.md) §2.

**Scope limitation, service-specific forecasts.** The ensemble currently forecasts the composite
LDI-T only. Service-type trajectories displayed in the interface (Nursing Facility, Home Health, Adult
Day Services) are proportional approximations scaled from the Overall trajectory, not independent model
runs. Producing genuine service-specific forecasts requires re-running the ensemble against each
sub-index with its own trend-adjusted feature vector; this is implemented in the roadmap but not yet
in the deployed system. Service-type curves should be read as indicative only.

**On scenario spread.** The three scenarios diverge modestly because the dominant index component, age structure, 0.45 combined weight, follows the same SSA projection across all scenarios. Only
supply, workforce and disability trends vary. This is deliberate: demographic momentum through 2035 is
already largely determined by the current population, so presenting wide demographic divergence would
overstate genuine uncertainty on that component.

**Early warning.** A tract is flagged as escalating when it is currently below the
Critical threshold but is projected to cross it by 2035. This is the operationally
actionable output: it identifies where intervention has lead time to work.

---

## 5. Validation status

| Check | Status |
|---|---|
| Held-out test set performance | Implemented, reported in interface and workbook |
| 5-fold cross-validation | Implemented |
| Feature importance (permutation) | Implemented |
| Scenario sensitivity | Implemented, three scenarios |
| Index weight sensitivity analysis | **Planned** |
| External validation vs. utilisation outcomes | **Planned** |
| Service-specific forecast trajectories | **Not yet implemented** |
| Independent per-service model fitting | **Planned**, service sub-indices are currently scaled from the overall projection |
| Comparison against HPSA / MUA-P designations | **Planned** |

The planned items are stated as planned. A tool intended for public health planning
should be explicit about which of its claims have been tested and which have not.

---

## 6. Roadmap

1. Implement genuine service-specific forecast trajectories (currently approximated from the composite).
2. Integrate E2SFCA road-network catchment modelling from the Wisconsin statewide study,
   replacing the county-resolved bed-supply measure with true tract-level accessibility.
3. Extend to Minnesota, Illinois, and Iowa; then to a national framework.
3. Propagate ACS margins of error into index uncertainty bands.
4. Link NHATS or MDS data for direct ADL measurement.
5. External validation against observed utilisation and unmet-need outcomes.
6. Index weight sensitivity analysis and, where data permits, empirical optimisation.
