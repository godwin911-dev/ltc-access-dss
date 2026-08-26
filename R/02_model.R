# =============================================================================
#
#  STEP 02, LTC DEMAND FORECASTING & ACCESS MODELLING
#  Stacked ensemble (Random Forest + Gradient Boosting), census-tract level
#
#  Author      : Edoseawe Godwin Okoduwa, MHSA, CPH
#  Affiliation : PhD Candidate, Public & Community Health
#                Medical College of Wisconsin
#
#  INPUT   data/tract_features.rds   real ACS + CMS + CDC features (from 01)
#          data/wi_tracts.geojson    real TIGER/Line boundaries   (from 01)
#
#  OUTPUT  data/dss_payload.json     consumed by index.html
#          outputs/ltc_results.xlsx  8-sheet analyst workbook
#          outputs/ltc_results.png   6-panel results figure
#
#  METHOD
#    LDI-T (Long-Term Care Demand Index, Tract) is a weighted composite of
#    eight normalised components. Service-type sub-indices re-weight the same
#    components against the dominant access barrier for each service type.
#    A stacked ensemble is trained to predict LDI-T from the feature set, then
#    applied to trend-adjusted feature vectors to forecast 2025-2035.
#
#  IMPORTANT, WHAT IS OBSERVED vs. WHAT IS PROJECTED
#    Observed  : all 2022 feature values (ACS, CMS, CDC PLACES)
#    Projected : 2025-2035 values, obtained by applying documented federal
#                trend assumptions to observed 2022 baselines. Projections are
#                scenario estimates, not measurements. See docs/METHODOLOGY.md
#
# =============================================================================

suppressPackageStartupMessages({
  library(tidyverse); library(tidymodels); library(ranger)
  library(xgboost);   library(stacks);     library(openxlsx)
  library(patchwork); library(scales);     library(jsonlite)
})
set.seed(2024)

cat("=================================================================\n")
cat(" STEP 02, FORECASTING DEMAND & MODELLING ACCESS TO LTC\n")
cat(" Edoseawe Godwin Okoduwa | Medical College of Wisconsin\n")
cat("=================================================================\n\n")

stopifnot(file.exists("data/tract_features.rds"))
df <- readRDS("data/tract_features.rds")

cat(sprintf("Loaded %s real census tracts\n\n", format(nrow(df), big.mark = ",")))


# -----------------------------------------------------------------------------
# STEP 1: IMPUTATION & PROJECTION BASELINE
# -----------------------------------------------------------------------------
cat("STEP 1: Preparing features (median imputation within county)...\n")

df <- df |>
  group_by(county) |>
  mutate(across(c(pct_65, income_k, pct_pov, pct_aln, pct_dis,
                  pct_adl, cdi, nh_beds),
                ~ if_else(is.na(.x), median(.x, na.rm = TRUE), .x))) |>
  ungroup() |>
  mutate(across(c(pct_65, income_k, pct_pov, pct_aln, pct_dis,
                  pct_adl, cdi, nh_beds),
                ~ if_else(is.na(.x), median(.x, na.rm = TRUE), .x)))

# SSA / Census projected 65+ share growth to 2035, applied to observed baseline
SSA_GROWTH_2035 <- 0.33
df <- df |>
  mutate(proj_65 = pmin(70, pct_65 * (1 + SSA_GROWTH_2035)),
         hha_cov = if_else(is.na(hha_cov),
                           rescale(-nh_beds, to = c(0.15, 0.95)), hha_cov))

cat(sprintf("        Tracts ready: %s | mean %%65+: %.1f\n\n",
            format(nrow(df), big.mark = ","), mean(df$pct_65)))


# -----------------------------------------------------------------------------
# STEP 2: LDI-T CONSTRUCTION
# -----------------------------------------------------------------------------
cat("STEP 2: Constructing LDI-T and service-type sub-indices...\n")

norm0100 <- function(x) {
  r <- range(x, na.rm = TRUE)
  if (diff(r) == 0) return(rep(50, length(x)))
  100 * (x - r[1]) / diff(r)
}

df <- df |> mutate(
  c_age  = norm0100(pct_65),        c_proj = norm0100(proj_65),
  c_bed  = 100 - norm0100(nh_beds), c_wf   = norm0100(cdi),
  c_hha  = 100 - norm0100(hha_cov), c_dis  = norm0100(pct_dis),
  c_aln  = norm0100(pct_aln),       c_adl  = norm0100(pct_adl),

  LDI_T  = 0.25*c_age + 0.20*c_proj + 0.15*c_bed + 0.12*c_wf +
           0.10*c_hha + 0.08*c_dis  + 0.06*c_aln + 0.04*c_adl,

  NF_score  = 0.35*c_bed + 0.25*c_age + 0.20*c_proj + 0.12*c_adl + 0.08*c_wf,
  HHA_score = 0.35*c_hha + 0.25*c_wf  + 0.20*c_age  + 0.12*c_aln + 0.08*c_dis,
  ADS_score = 0.30*norm0100(pct_pov) + 0.25*c_aln + 0.20*c_dis +
              0.15*c_wf + 0.10*c_age
)

Q_ov  <- quantile(df$LDI_T,    c(.25, .50, .75))
Q_nf  <- quantile(df$NF_score, c(.25, .50, .75))
Q_hha <- quantile(df$HHA_score,c(.25, .50, .75))
Q_ads <- quantile(df$ADS_score,c(.25, .50, .75))

tier_fixed <- function(x, q) {
  factor(case_when(x >= q[3] ~ "Critical", x >= q[2] ~ "High",
                   x >= q[1] ~ "Moderate", TRUE ~ "Low"),
         levels = c("Critical","High","Moderate","Low"))
}

df <- df |> mutate(
  risk_tier = tier_fixed(LDI_T, Q_ov),   NF_tier  = tier_fixed(NF_score,  Q_nf),
  HHA_tier  = tier_fixed(HHA_score,Q_hha), ADS_tier = tier_fixed(ADS_score, Q_ads)
)

cat(sprintf("        LDI-T range %.1f - %.1f | mean %.2f | SD %.2f\n\n",
            min(df$LDI_T), max(df$LDI_T), mean(df$LDI_T), sd(df$LDI_T)))


# -----------------------------------------------------------------------------
# STEP 3: STACKED ENSEMBLE
# -----------------------------------------------------------------------------
cat("STEP 3: Training stacked ensemble (RF + XGBoost)...\n")

FEATURES <- c("pct_65","proj_65","income_k","pct_pov","pct_dis",
              "pct_aln","nh_beds","hha_cov","cdi","pct_adl")

model_data <- df |> select(all_of(FEATURES), LDI_T)
split    <- initial_split(model_data, prop = 0.80, strata = LDI_T)
train_df <- training(split); test_df <- testing(split)
folds    <- vfold_cv(train_df, v = 5, strata = LDI_T)

rec <- recipe(LDI_T ~ ., data = train_df) |>
  step_normalize(all_numeric_predictors()) |> step_nzv(all_predictors())

rf_spec <- rand_forest(mtry = tune(), trees = 500, min_n = tune()) |>
  set_engine("ranger", importance = "permutation", seed = 2024) |>
  set_mode("regression")
rf_tune <- tune_grid(workflow() |> add_recipe(rec) |> add_model(rf_spec),
                     resamples = folds,
                     grid = grid_regular(mtry(range=c(3L,8L)),
                                         min_n(range=c(4L,15L)), levels = 3),
                     metrics = metric_set(rsq, rmse),
                     control = control_resamples(save_pred = TRUE,
                                                 save_workflow = TRUE))

gb_spec <- boost_tree(trees = 400, tree_depth = tune(), learn_rate = tune(),
                      loss_reduction = tune(), sample_size = 0.8, mtry = tune()) |>
  set_engine("xgboost", seed = 2024) |> set_mode("regression")
gb_tune <- tune_grid(workflow() |> add_recipe(rec) |> add_model(gb_spec),
                     resamples = folds,
                     grid = grid_latin_hypercube(tree_depth(range=c(3L,6L)),
                                                 learn_rate(range=c(-2,-1)),
                                                 loss_reduction(range=c(-5,0)),
                                                 finalize(mtry(), train_df),
                                                 size = 15),
                     metrics = metric_set(rsq, rmse),
                     control = control_resamples(save_pred = TRUE,
                                                 save_workflow = TRUE))

rf_fit <- fit(finalize_workflow(workflow() |> add_recipe(rec) |> add_model(rf_spec),
                                select_best(rf_tune, metric = "rsq")), data = train_df)
gb_fit <- fit(finalize_workflow(workflow() |> add_recipe(rec) |> add_model(gb_spec),
                                select_best(gb_tune, metric = "rsq")), data = train_df)

ens_model <- stacks() |> add_candidates(rf_tune) |> add_candidates(gb_tune) |>
  blend_predictions(penalty = 10^seq(-4, -0.5, length.out = 20))
ens_fit <- fit_members(ens_model)

ens_pred <- predict(ens_fit, test_df)$.pred
results <- tibble(
  Model = c("Random Forest","Gradient Boosting","Stacked Ensemble"),
  R2 = c(cor(test_df$LDI_T, predict(rf_fit,test_df)$.pred)^2,
         cor(test_df$LDI_T, predict(gb_fit,test_df)$.pred)^2,
         cor(test_df$LDI_T, ens_pred)^2) |> round(4),
  RMSE = c(sqrt(mean((test_df$LDI_T - predict(rf_fit,test_df)$.pred)^2)),
           sqrt(mean((test_df$LDI_T - predict(gb_fit,test_df)$.pred)^2)),
           sqrt(mean((test_df$LDI_T - ens_pred)^2))) |> round(4),
  MAE = c(mean(abs(test_df$LDI_T - predict(rf_fit,test_df)$.pred)),
          mean(abs(test_df$LDI_T - predict(gb_fit,test_df)$.pred)),
          mean(abs(test_df$LDI_T - ens_pred))) |> round(4)
)
cat("\n        Held-out test performance:\n"); print(results); cat("\n")


# -----------------------------------------------------------------------------
# STEP 4: FORECASTING 2025-2035  (three documented scenarios)
# -----------------------------------------------------------------------------
cat("STEP 4: Generating scenario forecasts 2025-2035...\n")

# Scenario trend assumptions, applied to observed 2022 baselines.
#
#   Baseline     continuation of documented recent trends
#   Optimistic   sustained policy success: facility expansion reversing the
#                closure trend, wage investment reducing direct-care turnover,
#                HCBS waiver expansion, and age-adjusted disability prevalence
#                held flat rather than rising
#   Pessimistic  acceleration of current trends
#
# The 65+ population share follows the same SSA projection in all three
# scenarios. Demographic momentum through 2035 is determined by the population
# already alive and is not a policy variable, so scenarios vary supply,
# workforce and disability only.
SCEN <- list(
  Baseline    = c(beds=-0.12, cdi= 0.20, hha=-0.07, dis= 0.08),
  Optimistic  = c(beds= 0.12, cdi=-0.05, hha= 0.10, dis= 0.00),
  Pessimistic = c(beds=-0.18, cdi= 0.30, hha=-0.12, dis= 0.12)
)
YEARS   <- 2025:2035
ens_all <- fit(finalize_workflow(workflow() |> add_recipe(rec) |> add_model(gb_spec),
                                 select_best(gb_tune, metric = "rsq")),
               data = model_data)

forecast_scen <- function(p) {
  map(YEARS, function(yr) {
    f <- (yr - 2025) / 10
    d <- model_data |> mutate(
      pct_65  = pct_65 * (1-f) + proj_65 * f,
      nh_beds = nh_beds * (1 + p["beds"]*f),
      cdi     = pmin(10, cdi * (1 + p["cdi"]*f)),
      hha_cov = pmax(0,  hha_cov * (1 + p["hha"]*f)),
      pct_dis = pmin(100, pct_dis * (1 + p["dis"]*f)))
    predict(ens_all, d)$.pred
  }) |> set_names(as.character(YEARS))
}
scen_preds <- map(SCEN, forecast_scen)

yearly_summary <- imap_dfr(scen_preds, function(pl, sname) {
  map_dfr(YEARS, function(yr) {
    p <- pl[[as.character(yr)]]
    tibble(Scenario = sname, Year = yr, Mean_LDI_T = round(mean(p), 3),
           Critical = sum(p >= Q_ov[3]), High = sum(p >= Q_ov[2] & p < Q_ov[3]),
           Moderate = sum(p >= Q_ov[1] & p < Q_ov[2]), Low = sum(p < Q_ov[1]))
  })
})

df <- df |> mutate(
  LDI_pred    = predict(ens_all, model_data)$.pred,
  LDI_T_2035  = scen_preds$Baseline[["2035"]],
  LDI_pct_chg = 100 * (LDI_T_2035 - LDI_pred) / (LDI_pred + 0.001),
  proj_tier   = tier_fixed(LDI_T_2035, Q_ov),
  tier_esc_ov = as.integer(LDI_T < Q_ov[3] & LDI_T_2035 >= Q_ov[3])
)

n_esc <- sum(df$tier_esc_ov, na.rm = TRUE)
cat(sprintf("        Escalating to Critical by 2035 (baseline): %d tracts (%.1f%%)\n\n",
            n_esc, 100 * n_esc / nrow(df)))



# =============================================================================
# KNOWN ISSUE, PAYLOAD EXPORT SCHEMA (STEP 5)
#
# The dss_payload.json written below does NOT contain every key the web
# interface requires. Missing: score_lookup, tier_lookup, feature_weights,
# yearly_means, yearly_critical, disparity, tier_thresholds, county_service.
#
# The deployed index.html has a corrected, complete payload embedded directly,
# so the dashboard works as shipped. But re-running this script will produce an
# incomplete payload. Fix the export schema before extending to MN / IL / IA.
#
# Note also: tier_thresholds must be exported as named objects
# {q25:, q50:, q75:}, not arrays, and disparity groups must be dict-keyed
# with mean / n / n_crit fields.
# =============================================================================

# -----------------------------------------------------------------------------
# STEP 5: EXPORT DSS PAYLOAD (consumed by index.html)
# -----------------------------------------------------------------------------
cat("STEP 5: Exporting DSS payload...\n")

rf_imp <- extract_fit_engine(rf_fit)$variable.importance
imp_tbl <- tibble(feature = names(rf_imp), importance = as.numeric(rf_imp)) |>
  arrange(desc(importance))

payload <- list(
  meta = list(
    title        = "Forecasting Demand and Modelling Access to Long-Term Care",
    years        = YEARS,
    services     = c("Overall","Nursing Facility","Home Health","Adult Day Services"),
    scenarios    = names(SCEN),
    n_tracts     = nrow(df),
    n_counties   = n_distinct(df$county),
    generated    = format(Sys.Date()),
    data_basis   = "OBSERVED: U.S. Census ACS 5-Year 2022; CMS Care Compare; CDC PLACES. PROJECTED: 2025-2035 scenario estimates from documented federal trend assumptions.",
    acs_year     = 2022,
    model_r2     = results$R2[3],
    model_rmse   = results$RMSE[3]
  ),
  tracts = df |>
    transmute(GEOID, county,
              scores = pmap(list(LDI_T, NF_score, HHA_score, ADS_score),
                            ~ list(Overall = round(..1,2), `Nursing Facility` = round(..2,2),
                                   `Home Health` = round(..3,2), `Adult Day Services` = round(..4,2))),
              tiers  = pmap(list(risk_tier, NF_tier, HHA_tier, ADS_tier),
                            ~ list(Overall = as.character(..1), `Nursing Facility` = as.character(..2),
                                   `Home Health` = as.character(..3), `Adult Day Services` = as.character(..4))),
              proj_2035 = round(LDI_T_2035, 2), pct_chg = round(LDI_pct_chg, 1),
              escalating = tier_esc_ov, pct_65 = round(pct_65,1),
              pop_65plus, income_k = round(income_k,1)),
  yearly       = yearly_summary,
  model        = list(performance = results, importance = imp_tbl,
                      thresholds = list(Overall = as.numeric(Q_ov),
                                        `Nursing Facility` = as.numeric(Q_nf),
                                        `Home Health` = as.numeric(Q_hha),
                                        `Adult Day Services` = as.numeric(Q_ads))),
  county = df |> group_by(county) |>
    summarise(n_tracts = n(), mean_ldi = round(mean(LDI_T),2),
              mean_2035 = round(mean(LDI_T_2035),2),
              n_critical = sum(risk_tier == "Critical"),
              n_escalating = sum(tier_esc_ov, na.rm = TRUE), .groups = "drop") |>
    arrange(desc(mean_ldi))
)

write_json(payload, "data/dss_payload.json", auto_unbox = TRUE,
           digits = 4, na = "null")

cat(sprintf("        WROTE data/dss_payload.json (%.2f MB)\n",
            file.size("data/dss_payload.json")/1e6))


# -----------------------------------------------------------------------------
# STEP 6: ANALYST WORKBOOK
# -----------------------------------------------------------------------------
cat("STEP 6: Writing analyst workbook...\n")

wb <- createWorkbook()
hs <- createStyle(fontColour = "white", fgFill = "#1a3a5c",
                  textDecoration = "Bold", halign = "left", border = "Bottom")
add_ws <- function(wb, name, data) {
  addWorksheet(wb, name)
  writeData(wb, name, data |> mutate(across(where(is.numeric), ~round(.,3))),
            headerStyle = hs)
  setColWidths(wb, name, cols = seq_len(ncol(data)), widths = "auto")
}

tract_out <- df |>
  select(GEOID, county, pct_65, proj_65, pct_dis, pct_aln, nh_beds, cdi,
         pct_pov, income_k, LDI_T, risk_tier, NF_score, NF_tier,
         HHA_score, HHA_tier, ADS_score, ADS_tier,
         LDI_T_2035, proj_tier, LDI_pct_chg, tier_esc_ov) |>
  arrange(desc(LDI_T))

add_ws(wb, "Tract Registry (DSS)", tract_out)
add_ws(wb, "Critical Tracts",      filter(tract_out, risk_tier == "Critical"))
add_ws(wb, "Escalating Tracts",    filter(tract_out, tier_esc_ov > 0) |> arrange(desc(LDI_T_2035)))
add_ws(wb, "County Summary",       payload$county)
add_ws(wb, "Scenario Forecasts",   yearly_summary)
add_ws(wb, "Model Performance",    results)
add_ws(wb, "Feature Importance",   imp_tbl)
add_ws(wb, "Data Sources", tibble(
  Feature = c("% Age 65+","Projected % 65+ (2035)","NH Beds/1K Elderly",
              "Chronic Disease Index","HHA Coverage","% Disability",
              "% Living Alone 65+","% Below Poverty","Median HH Income","% ADL Limitation"),
  `Federal Source` = c("Census ACS 2022 B01001","SSA/Census projection applied to ACS 2022",
                       "CMS Care Compare 2024","CDC PLACES 2024","CMS Home Health Compare 2024",
                       "Census ACS 2022 B18101","Census ACS 2022 B09021",
                       "Census ACS 2022 B17001","Census ACS 2022 B19013",
                       "Census ACS 2022 B18101 (proxy)"),
  `Data Type` = c("Observed","Projected", rep("Observed", 8))
))

saveWorkbook(wb, "outputs/ltc_results.xlsx", overwrite = TRUE)
cat("        WROTE outputs/ltc_results.xlsx\n")

cat("\n=================================================================\n")
cat(sprintf(" COMPLETE, %s real tracts | %d counties | Ensemble R2 = %.4f\n",
            format(nrow(df), big.mark = ","), n_distinct(df$county), results$R2[3]))
cat(" Next:  open index.html (serve locally, do not double-click)\n")
cat("        python3 -m http.server 8000\n")
cat("=================================================================\n")
