# =============================================================================
#
#  STEP 01 — ACQUIRE REAL FEDERAL DATA
#  Long-Term Care Access Decision-Support System
#
#  Author      : Edoseawe Godwin Okoduwa, MHSA, CPH
#  Affiliation : PhD Candidate, Public & Community Health
#                Medical College of Wisconsin
#
#  PURPOSE
#  Replaces all synthetic geometry and synthetic feature values with real,
#  publicly available federal data. Produces two artifacts consumed by the
#  modelling stage (02_model.R):
#
#    data/wi_tracts.geojson   real TIGER/Line tract boundaries (simplified)
#    data/tract_features.rds  real ACS + CMS + CDC feature table, keyed on GEOID
#
#  DATA SOURCES (all public, all free)
#    U.S. Census Bureau  ACS 5-Year Estimates      via tidycensus
#    U.S. Census Bureau  TIGER/Line Cartographic   via tigris
#    CMS                 Provider of Services      via data.cms.gov  (public CSV)
#    CDC                 PLACES tract estimates    via data.cdc.gov  (Socrata)
#
#  PREREQUISITE — Census API key (free, issued instantly):
#    https://api.census.gov/data/key_signup.html
#    Then run once:  tidycensus::census_api_key("YOUR_KEY", install = TRUE)
#
#  RUNTIME  approx 3-8 minutes on first run (cached thereafter)
#
# =============================================================================

# install.packages(c("tidyverse","tidycensus","tigris","sf","httr","jsonlite"))

suppressPackageStartupMessages({
  library(tidyverse)
  library(tidycensus)
  library(tigris)
  library(sf)
  library(httr)
  library(jsonlite)
})

options(tigris_use_cache = TRUE)
sf::sf_use_s2(FALSE)

STATES    <- c("WI")          # extend later: c("WI","MN","IL","IA")
ACS_YEAR  <- 2022
OUT_DIR   <- "data"
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

cat("=================================================================\n")
cat(" STEP 01 — ACQUIRING REAL FEDERAL DATA\n")
cat(" States:", paste(STATES, collapse = ", "), "| ACS year:", ACS_YEAR, "\n")
cat("=================================================================\n\n")


# -----------------------------------------------------------------------------
# 1. REAL TRACT BOUNDARIES  (TIGER/Line via tigris)
# -----------------------------------------------------------------------------
cat("[1/5] Downloading real census tract boundaries (TIGER/Line)...\n")

tracts_sf <- map_dfr(STATES, function(st) {
  tigris::tracts(state = st, cb = TRUE, year = ACS_YEAR, progress_bar = FALSE)
})

tracts_sf <- tracts_sf |>
  filter(ALAND > 0) |>                      # drop pure-water tracts
  transmute(
    GEOID,
    county_fips = paste0(STATEFP, COUNTYFP),
    county      = NAMELSAD,
    aland_km2   = ALAND / 1e6
  )

cat(sprintf("      Retrieved %s real tracts across %s counties\n",
            format(nrow(tracts_sf), big.mark = ","),
            n_distinct(tracts_sf$county_fips)))


# -----------------------------------------------------------------------------
# 2. REAL ACS DEMOGRAPHIC + SDOH FEATURES
# -----------------------------------------------------------------------------
cat("[2/5] Downloading ACS 5-Year demographic and SDOH estimates...\n")

acs_vars <- c(
  pop_total    = "B01003_001",   # Total population
  med_income   = "B19013_001",   # Median household income
  pov_total    = "B17001_001",   # Poverty universe
  pov_below    = "B17001_002",   # Income below poverty level
  hh65_alone   = "B09021_022",   # 65+ living alone
  hh65_total   = "B09021_001",   # 65+ household population
  dis_total    = "B18101_001",   # Disability universe
  novehicle    = "B08201_002"    # Households with no vehicle
)

# 65+ population is split across many sex-by-age cells; sum them explicitly
age65_vars <- c(
  paste0("B01001_0", 20:25),     # male   65-66 .. 85+
  paste0("B01001_0", 44:49)      # female 65-66 .. 85+
)

acs_main <- map_dfr(STATES, function(st) {
  get_acs(geography = "tract", state = st, year = ACS_YEAR,
          variables = acs_vars, output = "wide",
          survey = "acs5", geometry = FALSE, progress_bar = FALSE)
})

acs_age <- map_dfr(STATES, function(st) {
  get_acs(geography = "tract", state = st, year = ACS_YEAR,
          variables = age65_vars, output = "tidy",
          survey = "acs5", geometry = FALSE, progress_bar = FALSE)
}) |>
  group_by(GEOID) |>
  summarise(pop_65plus = sum(estimate, na.rm = TRUE), .groups = "drop")

acs_dis <- map_dfr(STATES, function(st) {
  get_acs(geography = "tract", state = st, year = ACS_YEAR,
          variables = c(dis65m = "B18101_015", dis65f = "B18101_034"),
          output = "wide", survey = "acs5", geometry = FALSE,
          progress_bar = FALSE)
}) |>
  transmute(GEOID, dis_65plus = dis65mE + dis65fE)

acs <- acs_main |>
  left_join(acs_age, by = "GEOID") |>
  left_join(acs_dis, by = "GEOID") |>
  transmute(
    GEOID,
    pop_total   = pop_totalE,
    pop_65plus,
    pct_65      = if_else(pop_totalE > 0, 100 * pop_65plus / pop_totalE, NA_real_),
    income_k    = med_incomeE / 1000,
    pct_pov     = if_else(pov_totalE > 0, 100 * pov_belowE / pov_totalE, NA_real_),
    pct_aln     = if_else(hh65_totalE > 0, 100 * hh65_aloneE / hh65_totalE, NA_real_),
    pct_dis     = if_else(pop_65plus > 0, 100 * dis_65plus / pop_65plus, NA_real_),
    n_novehicle = novehicleE
  )

cat(sprintf("      Retrieved ACS estimates for %s tracts\n",
            format(nrow(acs), big.mark = ",")))


# -----------------------------------------------------------------------------
# 3. REAL CMS NURSING FACILITY SUPPLY
# -----------------------------------------------------------------------------
cat("[3/5] Downloading CMS Provider of Services / Care Compare...\n")

local_cms <- file.path(OUT_DIR, "NH_ProviderInfo.csv")
cms_url   <- "https://data.cms.gov/provider-data/sites/default/files/resources/NH_ProviderInfo.csv"

read_cms <- function(path) {
  raw <- readr::read_csv(path, show_col_types = FALSE, progress = FALSE)
  nm  <- names(raw)
  pick <- function(...) {
    for (p in c(...)) {
      h <- grep(p, nm, ignore.case = TRUE, value = TRUE)
      if (length(h)) return(h[1])
    }
    NA_character_
  }
  col_state  <- pick("^State$", "Provider State", "state")
  col_beds   <- pick("Number of Certified Beds", "Certified Beds", "beds")
  col_county <- pick("County.Parish", "County/Parish", "Provider County", "^County")

  if (any(is.na(c(col_state, col_beds, col_county)))) {
    cat("      WARNING: could not identify required columns in CMS file.\n")
    cat("      Columns found:", paste(nm[1:min(10,length(nm))], collapse=", "), "\n")
    return(tibble(county_key=character(), county_beds=numeric(), n_facilities=integer()))
  }

  raw |>
    rename(state_  = all_of(col_state),
           beds_   = all_of(col_beds),
           county_ = all_of(col_county)) |>
    filter(toupper(str_trim(state_)) %in% STATES) |>
    mutate(county_key = toupper(str_trim(county_)),
           beds_      = suppressWarnings(as.numeric(beds_))) |>
    group_by(county_key) |>
    summarise(county_beds  = sum(beds_, na.rm = TRUE),
              n_facilities = n(), .groups = "drop")
}

cms_beds <- if (file.exists(local_cms)) {
  cat("      Found local NH_ProviderInfo.csv — using it.\n")
  tryCatch(read_cms(local_cms),
           error = function(e) {
             cat("      ERROR reading local file:", conditionMessage(e), "\n")
             tibble(county_key=character(), county_beds=numeric(), n_facilities=integer())
           })
} else {
  cat("      No local file found — attempting download...\n")
  tryCatch({
    raw <- readr::read_csv(cms_url, show_col_types = FALSE, progress = FALSE)
    readr::write_csv(raw, local_cms)
    cat("      Downloaded and cached to data/NH_ProviderInfo.csv\n")
    read_cms(local_cms)
  }, error = function(e) {
    cat("      NOTE: CMS download failed (", conditionMessage(e), ")\n", sep = "")
    cat("      Download manually from https://data.cms.gov/provider-data/topics/nursing-homes\n")
    cat("      and place NH_ProviderInfo.csv in data/, then re-run.\n")
    tibble(county_key=character(), county_beds=numeric(), n_facilities=integer())
  })
}

cat(sprintf("      CMS bed supply resolved for %d counties\n", nrow(cms_beds)))


# -----------------------------------------------------------------------------
# 4. REAL CDC PLACES CHRONIC DISEASE PREVALENCE (tract level)
# -----------------------------------------------------------------------------
cat("[4/5] Downloading CDC PLACES tract-level chronic disease estimates...\n")

places <- tryCatch({
  measures <- c("DIABETES", "ARTHRITIS", "STROKE", "COPD")
  map_dfr(STATES, function(st) {
    map_dfr(measures, function(m) {
      u <- paste0("https://data.cdc.gov/resource/cwsq-ngmh.csv",
                  "?stateabbr=", st, "&measureid=", m,
                  "&$select=locationid,measureid,data_value&$limit=50000")
      readr::read_csv(u, show_col_types = FALSE, progress = FALSE)
    })
  }) |>
    mutate(GEOID = sprintf("%011s", as.character(locationid))) |>
    select(GEOID, measureid, data_value) |>
    pivot_wider(names_from = measureid, values_from = data_value,
                values_fn = mean) |>
    rowwise() |>
    mutate(cdi = mean(c_across(-GEOID), na.rm = TRUE)) |>
    ungroup() |>
    select(GEOID, cdi)
}, error = function(e) {
  cat("      NOTE: CDC PLACES unavailable (", conditionMessage(e), ")\n", sep = "")
  tibble(GEOID = character(), cdi = numeric())
})

cat(sprintf("      PLACES estimates for %s tracts\n",
            format(nrow(places), big.mark = ",")))


# -----------------------------------------------------------------------------
# 5. ASSEMBLE, VALIDATE, EXPORT
# -----------------------------------------------------------------------------
cat("[5/5] Assembling feature table and exporting...\n")

county_lookup <- tracts_sf |>
  st_drop_geometry() |>
  mutate(county_key = toupper(str_remove(county, "\\s+County$"))) |>
  select(GEOID, county, county_key)

features <- county_lookup |>
  left_join(acs,     by = "GEOID") |>
  left_join(places,  by = "GEOID") |>
  left_join(cms_beds, by = "county_key") |>
  group_by(county_key) |>
  mutate(
    county_65 = sum(pop_65plus, na.rm = TRUE),
    nh_beds   = if_else(county_65 > 0,
                        1000 * county_beds / county_65, NA_real_)  # beds per 1k 65+
  ) |>
  ungroup() |>
  mutate(
    hha_cov = NA_real_,   # populated in 02_model.R from CMS HHA file if present
    pct_adl = pct_dis     # ADL proxy until NHATS/MDS linkage is added
  ) |>
  select(GEOID, county, pop_total, pop_65plus, pct_65, income_k, pct_pov,
         pct_aln, pct_dis, pct_adl, cdi, nh_beds, n_facilities)

# ---- data quality report ----------------------------------------------------
qc <- features |>
  summarise(across(where(is.numeric),
                   ~ round(100 * mean(is.na(.x)), 1))) |>
  pivot_longer(everything(), names_to = "variable", values_to = "pct_missing")

cat("\n      DATA QUALITY — percent missing by variable:\n")
print(as.data.frame(qc), row.names = FALSE)

stopifnot(nrow(features) > 0)
if (mean(is.na(features$pct_65)) > 0.10) {
  warning("More than 10% of tracts missing pct_65 — inspect ACS retrieval.")
}

# ---- write simplified geometry for the web DSS -------------------------------
geo_out <- tracts_sf |>
  st_transform(4326) |>
  st_simplify(dTolerance = 0.0005, preserveTopology = TRUE) |>
  left_join(select(features, GEOID, county_name = county), by = "GEOID") |>
  select(GEOID, county = county_name)

geo_path <- file.path(OUT_DIR, "wi_tracts.geojson")
if (file.exists(geo_path)) file.remove(geo_path)
st_write(geo_out, geo_path, driver = "GeoJSON", quiet = TRUE)

saveRDS(features, file.path(OUT_DIR, "tract_features.rds"))

cat(sprintf("\n      WROTE  %s  (%.1f MB, %s real tracts)\n",
            geo_path, file.size(geo_path) / 1e6,
            format(nrow(geo_out), big.mark = ",")))
cat(sprintf("      WROTE  %s\n", file.path(OUT_DIR, "tract_features.rds")))

cat("\n=================================================================\n")
cat(" STEP 01 COMPLETE — all geometry and features are real federal data\n")
cat(" Next:  source(\"R/02_model.R\")\n")
cat("=================================================================\n")
