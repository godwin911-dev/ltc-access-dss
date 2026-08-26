# Setup, from zero to a live public URL

## 1. Get a Census API key (2 minutes, free)

https://api.census.gov/data/key_signup.html, arrives by email instantly.

```r
install.packages("tidycensus")
tidycensus::census_api_key("YOUR_KEY_HERE", install = TRUE)
# restart R
```

## 2. Install packages

```r
install.packages(c(
  "tidyverse","tidycensus","tigris","sf","httr","jsonlite",
  "tidymodels","ranger","xgboost","stacks","openxlsx","patchwork","scales"
))
```

`sf` needs system geospatial libraries. If install fails:
- **macOS**: `brew install gdal proj geos`
- **Ubuntu/Debian**: `sudo apt install libgdal-dev libproj-dev libgeos-dev libudunits2-dev`
- **Windows**: installs from binary, no extra step

## 3. Run the pipeline

```r
setwd("path/to/ltc-dss")
source("R/01_fetch_real_data.R")   # 3-8 min
source("R/02_model.R")             # 2-5 min
```

Script 01 prints a data-quality table. If any variable shows high percent missing,
stop and investigate before proceeding, do not model over silent gaps.

## 4. View locally

```bash
python3 -m http.server 8000
```

Open http://localhost:8000

**The interface will not work if you double-click `index.html`.** Browsers block
`fetch` on `file://` URLs. It must be served over HTTP.

## 5. Publish to GitHub

```bash
cd ltc-dss
git init
git add .
git commit -m "LTC access decision-support system: real federal data pipeline"
git branch -M main
git remote add origin https://github.com/USERNAME/ltc-dss.git
git push -u origin main
```

Create the empty repo at github.com/new first, **do not** initialise it with a README,
or the push will be rejected for unrelated histories.

### Enable GitHub Pages

Repository → **Settings** → **Pages** → Source: `main`, folder: `/ (root)` → Save.

Live at `https://USERNAME.github.io/ltc-dss` in about a minute.

### Important: generated data is gitignored

`.gitignore` excludes `data/*.geojson` and `data/*.json`, so a fresh clone has code but
no data, good practice, but **GitHub Pages will show an empty map**.

To publish a working live demo, force-add the two files the interface needs:

```bash
git add -f data/wi_tracts.geojson data/dss_payload.json
git commit -m "Add generated data artifacts for GitHub Pages demo"
git push
```

If `wi_tracts.geojson` exceeds ~50 MB, raise the simplification tolerance in
`01_fetch_real_data.R` (`dTolerance = 0.001` or `0.002`) and regenerate.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Map area shows a "boundaries could not be loaded" message | Opened via `file://`, or geojson missing | Serve over HTTP; confirm `data/wi_tracts.geojson` exists |
| `Error: API key required` | Census key not installed | Re-run `census_api_key(..., install = TRUE)`, restart R |
| CMS download fails | data.cms.gov URL changed | Download `NH_ProviderInfo.csv` manually into `data/`, re-run 01 |
| `sf` won't install | Missing GDAL/PROJ/GEOS | See step 2 |
| Push rejected, "unrelated histories" | Repo initialised with README | `git pull --rebase origin main` then push |
| Pages shows empty map | Data files gitignored | `git add -f` the two data files (above) |
