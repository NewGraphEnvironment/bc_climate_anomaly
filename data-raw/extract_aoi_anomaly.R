# Extract climate anomaly time series and trend statistics for a custom AOI
#
# Replicates the core analysis from app.R (lines ~1290-1470) without the Shiny
# wrapper. Reads .nc rasters, crops to AOI, computes spatial mean per year,
# runs Mann-Kendall + Theil-Sen trend analysis, and writes a summary CSV.
#
# Usage: source interactively or Rscript data-raw/extract_aoi_anomaly.R
#
# Requires: terra, sf, Kendall, zyp, tidyverse

library(terra)
library(sf)
library(Kendall)
library(zyp)
library(tidyverse)

# -- Config -------------------------------------------------------------------
ano_dt_pth <- "./ano_clm_trn_data/"
aoi_path <- "shapefiles/Study Area.geojson"
aoi_name <- "Neexdzii Kwah"
output_dir <- "data-raw"

# Parameters and periods to extract (seasonal + annual only for report)
parameters <- c("tmean", "tmax", "tmin", "prcp", "vpd", "rh", "soil_moisture")
periods <- c("annual", "winter", "spring", "summer", "fall")

# Percentage-based anomaly parameters (same logic as app.R line 1325)
pct_params <- c("prcp", "soil_moisture")

# -- Load AOI -----------------------------------------------------------------
aoi <- st_read(aoi_path, quiet = TRUE)
aoi_vect <- vect(aoi)

# -- Build file index (mirrors app.R lines 148-170) --------------------------
nc_files <- tibble(
  dt_pth = list.files(ano_dt_pth, pattern = "\\.nc$", full.names = TRUE),
  fl_nam = basename(dt_pth)
) |>
  mutate(
    par = str_extract(fl_nam, paste(parameters, collapse = "|")),
    dt_type = str_extract(fl_nam, "(ano|clm|spatial_trend)"),
    mon = str_extract(fl_nam, "(annual|fall|summer|winter|spring|Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)"),
    start_year = str_extract(fl_nam, "(19|20)\\d{2}")
  ) |>
  filter(!is.na(par))

# -- Extract function ---------------------------------------------------------
extract_anomaly_ts <- function(par_sel, period_sel, nc_files, aoi_vect,
                                pct_params) {

  # Get anomaly raster
  ano_file <- nc_files |>
    filter(par == par_sel, dt_type == "ano", mon == period_sel)

  if (nrow(ano_file) == 0) return(NULL)

  ano_rast <- rast(ano_file$dt_pth)

  # Extract years from layer names
  yr_df <- tibble(paryr = names(ano_rast)) |>
    mutate(yr = as.numeric(str_extract(paryr, "[0-9]+")))
  names(ano_rast) <- yr_df$yr

  # Crop to AOI
  ano_crop <- terra::crop(ano_rast, aoi_vect, snap = "out", mask = TRUE)

  # For prcp and soil_moisture: convert to % of normal
  if (par_sel %in% pct_params) {
    clm_file <- nc_files |>
      filter(par == par_sel, dt_type == "clm", mon == period_sel)
    clm_rast <- rast(clm_file$dt_pth)
    clm_crop <- terra::crop(clm_rast, aoi_vect, snap = "out", mask = TRUE)
    ano_crop <- (ano_crop / clm_crop) * 100
    # Cap at +/- 200% (same as app.R lines 1328-1332)
    ano_crop <- ifel(ano_crop > 201, 200, ano_crop)
    ano_crop <- ifel(ano_crop < -201, -200, ano_crop)
  }

  # Spatial mean per year
  ts_df <- tibble(rownames_to_column(
    as.data.frame(global(ano_crop, fun = "mean", na.rm = TRUE)), "yr"
  )) |>
    transmute(
      yr = as.numeric(str_extract(yr, "[0-9]+")),
      ano = round(mean, 4)
    ) |>
    drop_na() |>
    filter(yr > 1950)

  # Trend 1950-present
  mk_50 <- MannKendall(ts_df$ano)
  sen_50 <- zyp.sen(ano ~ yr, ts_df)

  # Trend 1980-present
  ts_80 <- ts_df |> filter(yr > 1979)
  mk_80 <- MannKendall(ts_80$ano)
  sen_80 <- zyp.sen(ano ~ yr, ts_80)

  # Time series data
  ts_out <- ts_df |>
    mutate(par = par_sel, period = period_sel, region = aoi_name)

  # Trend summary
  trend_out <- tibble(
    par = par_sel,
    period = period_sel,
    region = aoi_name,
    trend_start = c(1950, 1980),
    trend_slope = round(c(sen_50$coefficients[2], sen_80$coefficients[2]), 4),
    trend_intercept = round(c(sen_50$coefficients[1], sen_80$coefficients[1]), 4),
    mk_p = round(c(mk_50$sl, mk_80$sl), 4),
    n_years = c(nrow(ts_df), nrow(ts_80))
  )

  list(ts = ts_out, trend = trend_out)
}

# -- Run extraction -----------------------------------------------------------
message("Extracting anomaly time series for: ", aoi_name)

results <- expand_grid(par = parameters, period = periods) |>
  pmap(function(par, period) {
    message("  ", par, " / ", period)
    extract_anomaly_ts(par, period, nc_files, aoi_vect, pct_params)
  })

# Combine
ts_all <- bind_rows(map(compact(results), "ts"))
trend_all <- bind_rows(map(compact(results), "trend"))

# -- Write output -------------------------------------------------------------
ts_path <- file.path(output_dir, paste0(
  str_replace_all(tolower(aoi_name), " ", "_"), "_anomaly_timeseries.csv"
))
trend_path <- file.path(output_dir, paste0(
  str_replace_all(tolower(aoi_name), " ", "_"), "_anomaly_trends.csv"
))

write_csv(ts_all, ts_path)
write_csv(trend_all, trend_path)

message("Wrote: ", ts_path)
message("Wrote: ", trend_path)
message("Done. ", nrow(ts_all), " time series rows, ",
        nrow(trend_all), " trend summaries.")
