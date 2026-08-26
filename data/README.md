# data/

Generated artifacts. Not committed to version control.

Run the pipeline to populate:

```r
source("R/01_fetch_real_data.R")   # -> wi_tracts.geojson, tract_features.rds
source("R/02_model.R")             # -> dss_payload.json
```

| File | Produced by | Contents |
|---|---|---|
| `wi_tracts.geojson` | 01 | Real TIGER/Line tract boundaries, simplified for web |
| `tract_features.rds` | 01 | Real ACS + CMS + CDC feature table keyed on GEOID |
| `dss_payload.json` | 02 | Scores, tiers, forecasts, model metrics for the interface |

If CMS live download fails, place `NH_ProviderInfo.csv` here manually from
https://data.cms.gov/provider-data/topics/nursing-homes and re-run script 01.
