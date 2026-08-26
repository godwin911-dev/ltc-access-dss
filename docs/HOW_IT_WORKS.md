# How This System Works, and Why It Matters

A plain-language explanation. No statistics background assumed.

---

## The problem

Federal instruments that identify healthcare shortage areas have three
limitations when applied to long-term care.

**No long-term care designation exists.** Health Professional Shortage Area
designations cover primary care, mental health and dental health. Medically
Underserved Area designations use a general index. Neither identifies shortage
in nursing facilities, home health or adult day services specifically, even
though long-term care need is among the fastest growing categories of demand.

**They look backwards.** A designation appears once shortage is already present.
Building a nursing facility, recruiting and training a direct-care workforce, or
expanding a home and community-based services waiver takes years. By the time a
shortage shows up in federal data, the window to prevent it has closed.

**They count providers, not access.** A provider-to-population ratio tells you
how many beds exist per thousand residents in a county. It does not tell you
whether an 82-year-old with limited mobility living in a specific neighbourhood
can reach one of them, whether the facility has capacity, or whether the care is
affordable.

---

## What this system does differently

**Works at census tract level.** A tract is roughly a neighbourhood, about 4,000
people. Wisconsin has 1,526 of them across 72 counties. County-level analysis
averages across neighbourhoods that differ enormously. Tract level does not.

**Long-term care specific.** The index is built from components that determine
long-term care need and supply: age structure, projected ageing, nursing bed
availability, caregiver workforce capacity, home health coverage, disability
prevalence, social isolation and functional limitation.

**Separates service types.** What constrains access to a nursing facility is bed
scarcity. What constrains home health is workforce and coverage. What constrains
adult day services is affordability and whether an isolated older adult can get
there at all. The system computes a separate sub-index for each.

**Looks forward.** Annual projections through 2035 under three scenarios, so a
planner sees where shortage will appear, not only where it already is.

**Flags what is still preventable.** The early warning function identifies tracts
currently below the critical threshold that are projected to cross it. This is
the operationally useful output, because it is the set of places where
intervention still has time to work.

---

## How it is built

**Step 1. Retrieve real federal data.**

| What | Source |
|---|---|
| Tract boundaries | U.S. Census Bureau TIGER/Line, 2022 |
| Population and age structure | American Community Survey 5-Year, 2018 to 2022 |
| Income, poverty, isolation, disability | American Community Survey 5-Year |
| Nursing facility beds | CMS Care Compare provider records |
| Chronic disease prevalence | CDC PLACES tract estimates |

All public, all free. No licensed or proprietary source is used.

**Step 2. Build the demand index.**

Eight components, each rescaled to a common 0 to 100 range, combined with
weights reflecting their contribution to long-term care demand:

```
LDI-T = 0.25 x current age 65+        0.20 x projected age 65+
      + 0.15 x nursing bed gap        0.12 x caregiver deficit
      + 0.10 x home health gap        0.08 x disability
      + 0.06 x living alone           0.04 x ADL limitation
```

The same components are reweighted for each service type against whichever
barrier dominates for that service.

**Step 3. Train a model.**

Two machine learning algorithms, a random forest and a gradient boosting model,
are trained to predict the index from its inputs, then combined into a stacked
ensemble. This is what allows the index to be extrapolated to future years by
feeding it trend-adjusted inputs.

**Step 4. Project forward.**

Documented federal trend assumptions are applied to the 2022 baseline: Social
Security Administration demographic projections for ageing, CMS closure rates
for facility supply, PHI projections for the direct-care workforce, and BRFSS
trends for disability. Three scenarios, so outputs stay usable under uncertainty
rather than depending on a single guess.

**Step 5. Present it usably.**

An interactive map, county rankings, a searchable tract explorer, disparity
breakdowns, an early warning list, and an analyst workbook.

---

## What it found in Wisconsin

**371 tracts, 24.3 percent of the state, are projected to cross the critical
threshold by 2035.** The statewide count of critical tracts rises from 383 to
752 under baseline assumptions.

Rural northern counties rank highest for current demand: Adams, Door, Vilas,
Bayfield, Burnett, Sawyer. Several show 100 percent of their tracts in the
critical tier.

None of this is visible in the Wisconsin Long-Term Care Scorecard, the state's
primary monitoring instrument, which reports at statewide level only.

---

## Why the approach is not Wisconsin specific

Every input is a federal dataset published for all 50 states on identical
schemas. The pipeline is parameterised by state code. Extending it to Minnesota,
Illinois or Iowa requires changing one variable, not redesigning the method.

The system is released under the MIT licence with complete documentation. Any
state, local, tribal or territorial health department can adopt it and apply it
to its own jurisdiction using the same free federal data.

---

## What it does not yet do

Stated plainly, because a planning tool that hides its limits misleads the people
who rely on it.

1. **Wisconsin only.** Other states are planned, not built.
2. **Service-type forecasts are approximations.** The composite forecast is
   produced by the model. The three service-type forward trajectories are
   currently scaled from it rather than modelled independently.
3. **Bed supply is county-resolved.** Capacity is aggregated to county and
   distributed to tracts. True tract-level catchment modelling using road-network
   travel times is implemented in the companion Wisconsin study but not yet
   integrated here.
4. **Not externally validated.** The model is trained to predict the index from
   its own components, so its high fit statistic reflects internal consistency,
   not real-world accuracy. Testing against observed utilisation has not been
   done.
5. **Weights are theory-driven.** Informed by the literature and the Wisconsin
   study, not empirically optimised. Sensitivity analysis is planned.
6. **Some inputs are themselves modelled.** CDC PLACES values are small-area
   estimates, not direct measurements.

See `docs/METHODOLOGY.md` and `docs/DATA_SOURCES.md` for full detail.

---

## Who this is for

State health departments allocating long-term care resources. County aging
offices and Aging and Disability Resource Centers targeting outreach. State
Medicaid agencies directing home and community-based services expansion.
Researchers studying long-term care access. Anyone who needs to know not just
where shortage exists today, but where it is coming.
