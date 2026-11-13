# CLAUDE.md — Guichon Creek Raven HBV-EC model

## Project purpose
Assess how the m.ah a temEEwuh Solar Project's land-cover change affects flows in Guichon Creek (BC). The project's footprint is up to 260 ha, about 5 km north of Logan Lake, and about 80% of it lies in the Guichon watershed.

- Model: Raven, HBV-EC emulation
- Domain: Guichon Creek down to the model outlet just below the solar site (subbasins 1 and 3, 185 km²). Until 2026-11-12 it extended to WSC 08LG041 at the Mamit Lake outlet (subbasin 2); that was removed because the gauge is regulated and lies downstream of the result.
- Deliverable: before/after hydrographs at a model outlet on Guichon Creek immediately below the solar site
- Context: Swiftwater Consulting scope letter SWC-1-43-01-P-001. A small change is expected, so report the differences between runs, not absolute flows.

## Keep it simple first
Build the simplest model that runs end to end, then add complexity one step at a time. Before adding something, ask whether it changes the before/after answer.

## Spatial setup
| Item | Value |
|---|---|
| Subbasin 1 | Outlet on Guichon Creek just below the solar site. `DOWNSTREAM_ID = -1` (model outlet). `GAUGED = 1` (main output). |
| Subbasin 2 | **Removed 2026-11-12** (remainder to regulated WSC 08LG041, HRUs 6–11 incl. solar HRU 6, Mamit Lake reservoir). Its data and download script are in `archive/sb2/`. Subbasin ID 2 and HRU IDs 6–11 are not reused. |
| Subbasin 3 | Headwater above WSC 08LG056 (76 km², natural flow, RHBN), split out of subbasin 1. `DOWNSTREAM_ID = 1`. `GAUGED = 1` (main calibration target). HRUs 12–15. |
| Elevation range | ~800–1900 m |
| Elevation bands | 1: <1000, 2: 1000–1200, 3: 1200–1400, 4: 1400–1600, 5: 1600+ (top merged; 1800–1900 is a sliver) |
| Solar HRU | HRU 1 (3.24 km², subbasin 1). Always its own HRU, never merged. `BAND = 0` in GIS. The footprint clipped to the watershed was given as ~2.1 km²; confirm which area is right before reporting. |
| CRS | NAD83 BC Environment Albers (EPSG:3005) for all GIS work; WGS84 decimal degrees for HRU lat/lon |

## Naming conventions
- **Subbasin IDs:** 1 = `Guichon_BelowSolar`, 3 = `Guichon_08LG056` (2 = `Guichon_08LG041`, removed)
- **HRU IDs:** 1–5 (subbasin 1) and 12–15 (subbasin 3), from the `HRU_ID` field of `data/gis/hrus_final.shp` and the 08LG056 split. IDs 6–11 belonged to the removed subbasin 2 and are not reused, so the IDs match the GIS layers. The solar HRU is 1. Attributes come from `data/scripts/hru_attributes_arcpy.py` → `data/processed/hru_attributes.csv`.
- **Land use / vegetation classes (pairs, by forest cover):** `MIX20_LU`/`MIX20_VEG` (20%: all HRUs, including the solar site HRU 1 pre-project). Soil profile `DEFAULT_P` for all HRUs. Forest cover acts only through `FOREST_COV` (interception, melt); `MAX_HT`/`MAX_LAI` have no effect in this setup. `RAIN_ICEPT_PCT`/`SNOW_ICEPT_PCT` are Raven defaults (0.12/0.10), not set explicitly.
- **Scenario classes:** `SOLAR` (land use: `IMPERM` 1.0, `FOREST_COV` 0, a worst-case screening assumption) and `SOLAR_VEG` (vegetation)
- **HRU groups:** `SB1_HRUs`, `SB3_HRUs`, `SOLAR_SITE` (= HRU 1). Declare them in the .rvi with `:DefineHRUGroups` and populate them in the .rvh.
- **Channel profile:** none while `:Routing ROUTE_NONE` (`PROFILE = NONE` in `:SubBasins`). Use `CHAN_GUICHON` if channel routing is switched on.
- **Met gauges:** `Daymet_HRUnn`, one per HRU (see Forcing below)
- **Run names:** `baseline`, `solar` (with variants such as `solar_lo` / `solar_hi` for sensitivity)

## Model configuration decisions
- **Template:** Raven manual v4.1, Appendix F.2 (HBV-EC), with these changes:
  - `:Routing ROUTE_NONE` with `:CatchmentRoute ROUTE_TRI_CONVOLUTION` (HBV MAXBAS-style triangular unit hydrograph in each subbasin, set by `TIME_CONC`/`TIME_TO_PEAK`). Raven warns that `ROUTE_NONE` is meant for one-subbasin models; this is accepted for now. Switching to `ROUTE_DIFFUSIVE_WAVE` would need a `:ChannelProfile` in the .rvp, its name in the `:SubBasins` PROFILE column, and subbasin 1's `REACH_LENGTH` shortened (it still includes the 17.3 km above 08LG056).
  - Delete the glacier lines: Flush→GLACIER and its conditional, `GlacierMelt`, and `GlacierRelease`.
  - Keep `:LakeStorage SLOW_RESERVOIR` (an HBV-EC quirk).
- **Time step and periods:** daily. Simulation 1980-10-01 to 2024-09-30; WY1981 is spin-up. Flow records start 1982-01-01 and end 2024-12-31; 08LG056 has no data Oct 2011 - Jan 2013 (Raven skips missing days in the diagnostics).
- **Metrics:** `:EvaluationMetrics NASH_SUTCLIFFE KLING_GUPTA PCT_BIAS RMSE R2`.
- **Evaluation periods (Option A, chosen 2026-11-12):** CALIBRATION 2004-10-01 to 2024-09-30 (WY2005-2024), VALIDATION 1981-10-01 to 2004-09-30 (WY1982-2004). Calibrate on present-day conditions, because observed flow at 08LG056 roughly doubled after about 2004 (pine beetle and mine operations are suspected but unverified), and the solar project acts on the present-day catchment. The earlier regime tests whether the parameters transfer.
- **Scenario method:** `hbvec.rvp` is the baseline. `hbvec_solar.rvp` includes it with `:RedirectToFile hbvec.rvp` and adds `:LandUseChange` / `:VegetationChange` for `SOLAR_SITE`, dated `1900-01-01`. Because the date is before `:StartDate`, Raven applies the change at t = 0, so both runs use identical forcings and parameters over the full record. Never copy parameters into `hbvec_solar.rvp`; edit `hbvec.rvp` only.
- **Solar scenario = fully impervious site** (`IMPERM` 1.0): all rain and melt on HRU 1 bypasses the soil and goes to the fast reservoir. Report it as a bounding case, not an estimate. Capillary rise (`CRISE_HBV`) still returns some fast-reservoir water to the soil, where it can evaporate, so it is not literally zero ET. Note the solar HRU is 3.24 km², about 1.5 times the ~2.1 km² footprint figure; confirm which is right before reporting.

## Forcing (Daymet, since 2026-11-12)
- **Source:** Daymet V4 R1, 1 km daily grid (Tmax, Tmin, precip), downloaded for 1980-01-01 to 2024-12-31 (Daymet itself runs 1980 to the present). It replaced the ECCC Highland Valley Lornex station (1123469), which reads low after about 1999 relative to the regional estimate, and which ends in 2011. In the 1982-2011 comparison with unchanged parameters, Daymet raised KGE at 08LG056 from 0.40 to 0.75 (WY2000-2011: 0.05 to 0.64). Evidence: `archive/lornex/compare_lornex_daymet.pdf` (local only; archive/ is not tracked).
- **Lornex is archived** in `archive/lornex/` (not tracked). It can still be run for comparison with `Raven.exe hbvec -t archive/lornex/hbvec_lornex.rvt -o output\ -r lornex`.
- **Method:** `data/scripts/get_daymet.R` samples Daymet on a 2 km grid in each HRU (250 m for small HRUs) through the single-pixel API, because the NetCDF/THREDDS server needs a NASA Earthdata login. `data/scripts/write_daymet_rvt.R` averages the points per HRU and writes `hbvec.rvt` with one virtual gauge per HRU. Details and the data folder layout (`model_input/`, `raw/`, `processed/`, `gis/`, `scripts/`): `data/README.md`.
- **Virtual gauges sit at their HRU's exact lat/lon/elevation from the .rvh.** `INTERP_NEAREST_NEIGHBOR` then gives each HRU its own gauge, and `OROCORR_HBV` applies no lapse, which is right because Daymet already includes elevation effects. No NetCDF build of Raven is needed.
- **If the HRUs or the .rvh change,** re-run both scripts so the sample points and gauge locations match. `get_daymet.R` and `write_daymet_rvt.R` use only HRUs in the .rvh. Daymet point IDs are numbered over the original 15-HRU delineation and never renumbered, because they name the raw files.
- **Gauge corrections:** every gauge carries the same `:RainCorrection` / `:SnowCorrection`. `write_daymet_rvt.R` keeps the values already in `hbvec.rvt`, so edit them there (all 9 gauges) and they survive a rebuild.
- **Monthly PET normals** (`:MonthlyAveTemperature` / `:MonthlyAveEvaporation` per gauge) are computed over the model period, WY1981-2024. If the period changes, update `NORM_START`/`NORM_END` in `write_daymet_rvt.R` and `START`/`END` in `get_daymet.R`, then re-run both.
- **The Lornex comparison (`archive/lornex/`) covers 1982-2011 only;** Lornex ends in Nov 2011, so it can't run the extended period.

## Raven gotchas (check these first when debugging)
- **Aspect direction:** Raven measures aspect counter-clockwise from north (west = 90°). From GIS sine/cosine means, use `ASPECT = degrees(atan2(-sin_mean, cos_mean)) % 360`.
- **Units:** precipitation must be in mm/d, even for sub-daily data.
- **Missing values:** the blank/missing-data flag is `-1.2345`.
- **Time intervals:** the interval in `:Data`, `:MultiData` and `:ObservationData` headers must be a decimal (e.g. `1.0`), not `hh:mm:ss`.
- **HRU group order:** define HRU groups in the .rvi before populating them in the .rvh.
- **RVP template:** add `:CreateRVPTemplate` to the .rvi, run once to generate a blank .rvp, then remove the line (the model will not run while it is present).
- **`:SubBasins` columns are positional:** Raven reads `ID, NAME, DOWNSTREAM_ID, PROFILE, REACH_LENGTH, GAUGED` in that order and ignores `:Attributes`. Leaving out PROFILE shifts the columns, so no subbasin is gauged and Hydrographs.csv holds only precipitation (Diagnostics.csv still fills).
- **Non-numeric values in time series:** Raven rejects `-0.00`. Round, then add 0, before formatting.
- **Gauge elevation:** this must be correct, because `OROCORR_HBV` lapses temperature and precipitation from it to each HRU. For the Daymet gauges it equals the HRU elevation, so the lapse is zero.
- **Daymet calendar:** Daymet omits Dec 31 in leap years. `write_daymet_rvt.R` fills it with Dec 30's temperatures and zero precip.
- **PET inputs:** `PET_FROMMONTHLY` needs `:MonthlyAveTemperature` and `:MonthlyAveEvaporation` in the gauge block.
- **After every run:** check `RavenErrors.txt` before looking at results.

## Run commands
```
Raven.exe hbvec -o output\ -r baseline
Raven.exe hbvec -p hbvec_solar.rvp -o output\ -r solar
```
Outputs to compare: `<run>_Hydrographs.csv` (subbasin 1 for the answer; subbasin 3 against observed 08LG056) and `<run>_Diagnostics.csv`. Interactive comparison: `Rscript analysis/plot_solar_dygraph.R`.

## Calibration
- **Parameters, roughly in order:** `RAINSNOW_TEMP`, `MELT_FACTOR` / `MIN_MELT_FACTOR`, `:RainCorrection` / `:SnowCorrection`, `HBV_BETA`, `FIELD_CAPACITY`, `BASEFLOW_COEFF` (fast and slow), `MAX_PERC_RATE`, `TIME_CONC`
- **Method:** manual first, then OSTRICH. Objective: KGE at 08LG056, CALIBRATION period.
- **Current parameters:** OSTRICH DDS, 1000 trials, Daymet forcing, 2026-11-12; rounded into `hbvec.rvp`/`hbvec.rvt` (results in `calib/results_2026-11-12_daymet/`). KGE at 08LG056: 0.86 calibration (WY2005-2024, bias −0.4%), 0.08 validation (WY1982-2004, bias +82%). Accepted as good enough by the user, with known weaknesses:
  - While subbasin 2 was in the model, 08LG041 volume came out about double the observed (bias +99% calibration, +174% validation). The parameters fit the high post-2004 flows at 08LG056 by shedding more water from the soil (`HBV_BETA` 1.0, `FIELD_CAPACITY` 0.80), which may make the lower part of subbasin 1 too wet as well; there is no gauge left to check it.
  - Two parameters finished at their bounds: `:RainCorrection` 0.805 (lower bound 0.80), slow-reservoir `BASEFLOW_COEFF` 0.0498 (upper bound 0.05).
  - Possible next step: widen those two bounds.
- **The OSTRICH setup is in `calib/`** (see `calib/README.md`; local only, `calib/` is git-ignored). Re-run `python prepare.py` there after any model edit so the templates match. `prepare.py` handles the Daymet gauges' `:RainCorrection`/`:SnowCorrection` lines (one shared value).
- **08LG056 is the only gauge in the model** (natural flow). 08LG041 is regulated and was removed with subbasin 2.
- **Solar-site parameters are not calibrated.** The flow record cannot constrain `FOREST_COV`, `IMPERM` or interception for the site, so set them from literature or judgment and bracket them with low, central and high scenarios.

## Reference documents
- **`data/README.md`:** data folder layout, Daymet method, rebuild steps
- **`analysis/daymet_virtual_gauges.pdf`:** how the Daymet virtual gauges are built, with figures (rebuild: `Rscript analysis/daymet_virtual_gauges.R`)
- **`archive/lornex/compare_lornex_daymet.pdf`:** Lornex vs Daymet forcing comparison, why Daymet is used (local only)
- **`RavenUsersManual_v4.1.pdf`:**
  - App. F.2: HBV-EC template
  - App. A.3: .rvh format
  - App. A.4: .rvt format
  - App. A.5: .rvc format
  - App. D: parameter tables
  - Land-use change commands: in the .rvp "Special Commands" section
- **`Raven Walkthrough 1–5.pdf`:**
  - WT1: RVP template generation
  - WT2: multi-subbasin setup, HRU groups, `:LandUseChange`
  - WT3: Alouette HBV-EC example
- **`Raven Paper.pdf`:** Craig et al. (2020), the Raven framework paper
- **`SWC-1-43-01-P-001.pdf`:** scope letter
- **Guichon_Raven_HBV-EC_Setup_Guide.pdf:** step-by-step setup guide written for this project

## Working preferences
- Explain the reasoning behind Raven settings; I'm learning Raven as I build this.
- When suggesting ArcGIS steps, name the exact ArcGIS Pro tool and its key parameters.
- When editing Raven files, show only the changed blocks unless asked for the full file.
- Flag any change that would make the baseline and solar runs differ in anything other than the solar HRU's land cover.
- **Do not run Raven.** After editing model files, do not execute `Raven.exe` (including test copies). I run the model myself. Tell me what to run and what to check instead.