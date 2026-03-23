# Build the `nwa` package — NetCDF Weather Anomaly toolkit

## Problem

All climate anomaly computation in `bc_climate_anomaly` is embedded in a monolithic Shiny app (`app.R`, ~3000 lines) with the same logic copy-pasted across `2_spatial_trend_cal_fun.R`, `ecoprovince_average_anomaly/eco_province_ave_anomaly_cal.R`, and `data-raw/extract_aoi_anomaly.R`. There's no reusable API — every new AOI or report requires re-implementing the same crop → anomaly → zonal → trend pipeline.

The upstream app hardcodes a 1981-2010 baseline. The Neexdzii Kwah analysis showed that 75-year trends (1950+) detect significant change in VPD, soil moisture, and precipitation that 45-year trends (1980+) miss entirely. Baseline period must be a parameter, not a constant.

## Proposed Solution

Build `nwa` — a lean R package that extracts the core operations into abstract, composable functions. Every function takes the minimum inputs needed and returns tidy outputs. No BC-specific assumptions in the function signatures.

## Package name

`nwa` — NetCDF Weather Anomaly. Short prefix, easy to type, `nwa_*` autocomplete is clean.

## Function inventory

### Data I/O

| Function | Signature | Returns |
|----------|-----------|---------|
| `nwa_rast_index()` | `(path, pattern)` | Tibble of file paths + parsed metadata (parameter, period, year range) |
| `nwa_rast_read()` | `(file, years)` | `SpatRaster` stack with year-named layers |

`nwa_rast_index()` parses NetCDF filenames into structured metadata. The regex pattern is configurable so it works beyond the current ERA5-Land naming convention.

`nwa_rast_read()` loads a raster and attaches temporal information to layer names. Optional `years` filter to load a subset.

### Baseline & Anomaly

| Function | Signature | Returns |
|----------|-----------|---------|
| `nwa_baseline()` | `(rast, years = 1981:2010)` | Single-layer `SpatRaster` (mean over reference period) |
| `nwa_anomaly()` | `(rast, baseline, pct = FALSE, cap = 200)` | `SpatRaster` stack of anomalies |

`nwa_baseline()` computes the reference period mean. Default is 1981-2010 but **parameterized** — pass `1951:1980` for pre-warming, or any custom range.

`nwa_anomaly()` computes departure from baseline. When `pct = TRUE`, returns percentage of normal `(anomaly / baseline) * 100`, capped at `±cap`. This replaces the scattered if/else blocks for prcp/soil_moisture throughout the current code.

### Zonal statistics

| Function | Signature | Returns |
|----------|-----------|---------|
| `nwa_zonal()` | `(rast, aoi, fun = "mean")` | Tibble with columns: `year`, `value` |

Crops raster to AOI, masks, computes spatial summary per layer (year). The AOI can be any `sf`/`SpatVector` object — BC boundary, ecoprovince, custom watershed, whatever. `fun` accepts any function `terra::global()` supports.

### Trend analysis

| Function | Signature | Returns |
|----------|-----------|---------|
| `nwa_trend()` | `(x, time, starts)` | Tibble: `start`, `n_years`, `slope`, `intercept`, `p_value` |
| `nwa_trend_pixel()` | `(rast, starts, workers = 1)` | Named list of 2-layer `SpatRaster` (slope + p-value), one per start year |

`nwa_trend()` runs Mann-Kendall + Theil-Sen on a numeric vector. `starts` accepts multiple start years (e.g., `c(1950, 1980)`) and returns one row per period. This is the common pattern — the Neexdzii Kwah analysis needed both periods side by side to show how baseline choice affects significance.

`nwa_trend_pixel()` applies trend analysis across every pixel in a raster stack. Returns slope and p-value rasters. Optional parallel execution via `workers` parameter (wraps `furrr` or `terra`'s built-in parallelism).

### Visualization

| Function | Signature | Returns |
|----------|-----------|---------|
| `nwa_stripe()` | `(df, col_warm, col_cold)` | `ggplot` object (climate stripe) |
| `nwa_plot_ts()` | `(df, trend_df, title, units)` | `ggplot` or `plotly` object |

`nwa_stripe()` generates a warming stripe visualization from a year/value dataframe.

`nwa_plot_ts()` plots a time series with optional trend line overlay. Takes the output of `nwa_zonal()` and optionally `nwa_trend()`.

## Design principles

1. **No hardcoded baselines.** Every temporal reference is a parameter with a sensible default.
2. **Tidy in, tidy out.** Functions accept `sf`/`SpatRaster`/tibbles and return tibbles or `SpatRaster`.
3. **Composable.** Each function does one thing. The pipeline is: `read → baseline → anomaly → zonal → trend`. Users compose as needed.
4. **Data-source agnostic.** Functions operate on rasters, not file paths. How the raster was obtained (local NetCDF, STAC, cloud-optimized GeoTIFF) is the caller's concern. STAC integration can wrap these functions later without changing the API.
5. **Region agnostic.** Nothing assumes BC, ERA5-Land, or specific variable names. The AOI is just a polygon. The raster is just a raster.

## Scaffold checklist

Following R package dev conventions:

- [ ] `usethis::create_package()` in a new repo (`NewGraphEnvironment/nwa`)
- [ ] `usethis::use_mit_license("New Graph Environment Ltd.")`
- [ ] `usethis::use_testthat(edition = 3)`
- [ ] `usethis::use_pkgdown()` + GitHub Action
- [ ] DESCRIPTION: `Imports: terra, sf, zyp, Kendall, ggplot2, tibble, dplyr`
- [ ] DESCRIPTION: `Suggests: furrr, plotly, testthat`
- [ ] `inst/testdata/` with small cropped NetCDFs for tests/examples
- [ ] `data-raw/make_testdata.R` documenting how test rasters were created
- [ ] One function per file: `R/nwa_baseline.R`, `R/nwa_anomaly.R`, etc.
- [ ] One test file per function: `tests/testthat/test-nwa_baseline.R`, etc.
- [ ] Vignette: Neexdzii Kwah end-to-end (read → baseline → anomaly → zonal → trend → plot)
- [ ] Hex sticker

## Implementation order

Start with the core pipeline, test each before moving on:

1. `nwa_rast_read()` + `nwa_rast_index()` — data loading
2. `nwa_baseline()` — reference period computation
3. `nwa_anomaly()` — departure calculation
4. `nwa_zonal()` — spatial aggregation
5. `nwa_trend()` — time series trend detection
6. `nwa_trend_pixel()` — pixel-level trends
7. `nwa_stripe()` + `nwa_plot_ts()` — visualization
8. Vignette — Neexdzii Kwah worked example reproducing the CSV from `restoration_wedzin_kwa_2024`

## Future scope (separate issues)

- **STAC integration** — `nwa_stac_read()` to pull ERA5-Land (or other sources) from Planetary Computer / custom STAC catalog, returning the same `SpatRaster` that `nwa_rast_read()` does
- **Shiny module** — extract the app.R UI/server logic into `nwa_mod_*()` Shiny modules that consume the package API
- **Report template** — Quarto parameterized report that imports `nwa` functions

## Context

- Upstream app: `bcgov/bc_climate_anomaly`
- Fork: `NewGraphEnvironment/bc_climate_anomaly`
- Neexdzii Kwah trends: `NewGraphEnvironment/restoration_wedzin_kwa_2024/data/climate/neexdzii_kwah_anomaly_trends.csv`
- Relates to NewGraphEnvironment/bc_climate_anomaly#1
