# CLAUDE.md — Guichon Creek Raven HBV-EC model

## Project purpose
Assess how the m.ah a temEEwuh Solar Project's land-cover change affects flows in Guichon Creek (BC). The project's footprint is up to 260 ha, about 5 km north of Logan Lake, and about 80% of it lies in the Guichon watershed.

- Model: Raven, HBV-EC emulation
- Domain: the WSC 08LG041 catchment (Guichon Creek at outlet of Mamit Lake)
- Deliverable: before/after hydrographs at a model outlet on Guichon Creek immediately below the solar site
- Context: Swiftwater Consulting scope letter SWC-1-43-01-P-001. A small change is expected, so report the differences between runs, not absolute flows.

## Keep it simple first
Build the simplest model that runs end to end, then add complexity one step at a time. Before adding something, ask whether it changes the before/after answer.

## Spatial setup
| Item | Value |
|---|---|
| Subbasin 1 | Outlet on Guichon Creek just below the solar site. `DOWNSTREAM_ID = 2`. `GAUGED = 1` (main output). |
| Subbasin 2 | Remainder to 08LG041, contains Mamit Lake. `DOWNSTREAM_ID = -1`. `GAUGED = 1` (regulated gauge; not calibrated, reported as a check only). |
| Subbasin 3 | Headwater above WSC 08LG056 (76 km², natural flow, RHBN), split out of subbasin 1. `DOWNSTREAM_ID = 1`. `GAUGED = 1` (main calibration target). HRUs 12–15. |
| Elevation range | ~800–1900 m |
| Elevation bands | 1: <1000, 2: 1000–1200, 3: 1200–1400, 4: 1400–1600, 5: 1600+ (top merged; 1800–1900 is a sliver) |
| Solar HRU | Footprint clipped to the watershed (~2.1 km²). Always its own HRU, never merged. `BAND = 0` in GIS. |
| Mamit Lake | Lake-like `:Reservoir` at the subbasin 2 outlet. No lake HRU in v1 (`:HRUID` omitted, so lake evaporation is ignored). |
| CRS | NAD83 BC Environment Albers (EPSG:3005) for all GIS work; WGS84 decimal degrees for HRU lat/lon |

## Naming conventions
- **Subbasin IDs:** 1 = `Guichon_BelowSolar`, 2 = `Guichon_08LG041`, 3 = `Guichon_08LG056`
- **HRU IDs:** sequential 1…N, taken from the `HRU_ID` field of `data/delineation_copy/hrus_final.shp`. Solar HRUs are 1 (SB1) and 6 (SB2). Attributes come from `data/scripts/hru_attributes_arcpy.py` → `data/processed/hru_attributes.csv`.
- **Land use / vegetation classes (pairs, by forest cover):** `MIX20_LU`/`MIX20_VEG` (20%: SB1 and SB3, including the solar site HRUs 1 and 6 pre-project), `MIX40_LU`/`MIX40_VEG` (40%: SB2 bands, HRUs 7-11). Soil profile `DEFAULT_P` for all HRUs. Forest cover acts only through `FOREST_COV` (interception, melt); `MAX_HT`/`MAX_LAI` have no effect in this setup. `RAIN_ICEPT_PCT`/`SNOW_ICEPT_PCT` are Raven defaults (0.12/0.10), not set explicitly.
- **Scenario classes:** `SOLAR` (land use: `IMPERM` 1.0, `FOREST_COV` 0, a worst-case screening assumption) and `SOLAR_VEG` (vegetation)
- **HRU groups:** `SB1_HRUs`, `SB2_HRUs`, `SB3_HRUs`, `SOLAR_SITE`. Declare them in the .rvi with `:DefineHRUGroups` and populate them in the .rvh.
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
- **Solar scenario = fully impervious site** (`IMPERM` 1.0): all rain and melt on HRUs 1 and 6 bypasses the soil and goes to the fast reservoir. Report it as a bounding case, not an estimate. Capillary rise (`CRISE_HBV`) still returns some fast-reservoir water to the soil, where it can evaporate, so it is not literally zero ET. Note the solar HRUs total 3.99 km², about twice the ~2.1 km² footprint figure above; confirm which is right before reporting.

## Forcing (Daymet, since 2026-11-12)
- **Source:** Daymet V4 R1, 1 km daily grid (Tmax, Tmin, precip), downloaded for 1980-01-01 to 2024-12-31 (Daymet itself runs 1980 to the present). It replaced the ECCC Highland Valley Lornex station (1123469), which reads low after about 1999 relative to the regional estimate, and which ends in 2011. In the 1982-2011 comparison with unchanged parameters, Daymet raised KGE at 08LG056 from 0.40 to 0.75 (WY2000-2011: 0.05 to 0.64). Evidence: `archive/lornex/compare_lornex_daymet.pdf` (local only; archive/ is not tracked).
- **Lornex is archived** in `archive/lornex/` (not tracked). It can still be run for comparison with `Raven.exe hbvec -t archive/lornex/hbvec_lornex.rvt -o output\ -r lornex`.
- **Method:** `data/scripts/get_daymet.R` samples Daymet on a 2 km grid in each HRU (250 m for small HRUs) through the single-pixel API, because the NetCDF/THREDDS server needs a NASA Earthdata login. `data/scripts/write_daymet_rvt.R` averages the points per HRU and writes `hbvec.rvt` with one virtual gauge per HRU. Details: `data/README.md`.
- **Virtual gauges sit at their HRU's exact lat/lon/elevation from the .rvh.** `INTERP_NEAREST_NEIGHBOR` then gives each HRU its own gauge, and `OROCORR_HBV` applies no lapse, which is right because Daymet already includes elevation effects. No NetCDF build of Raven is needed.
- **If the HRUs or the .rvh change,** re-run both scripts so the sample points and gauge locations match.
- **Gauge corrections:** every gauge carries the same `:RainCorrection` / `:SnowCorrection`. `write_daymet_rvt.R` keeps the values already in `hbvec.rvt`, so edit them there (all 15 gauges) and they survive a rebuild.
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
Outputs to compare: `<run>_Hydrographs.csv` (subbasin 1 for the answer, subbasin 2 against observed) and `<run>_Diagnostics.csv`.

## Calibration
- **Parameters, roughly in order:** `RAINSNOW_TEMP`, `MELT_FACTOR` / `MIN_MELT_FACTOR`, `:RainCorrection` / `:SnowCorrection`, `HBV_BETA`, `FIELD_CAPACITY`, `BASEFLOW_COEFF` (fast and slow), `MAX_PERC_RATE`, `TIME_CONC`
- **Method:** manual first, then OSTRICH. Objective: KGE at 08LG056, CALIBRATION period.
- **Current parameters were calibrated with Lornex forcing** (OSTRICH, 2026-11-12) and have not been recalibrated for Daymet. Recalibrating with Daymet is the next calibration step.
- **The OSTRICH setup is archived** in `archive/calib/` (not tracked; see its `README.md`). To reuse it, move it back to `calib/` or change `ROOT` in `prepare.py` to two folders up. Then re-run `python prepare.py` after any model edit so the templates match. The `.rvt` template must now cover the corrections in all 15 Daymet gauges.
- **08LG041 is regulated.** Do not calibrate against it; report its fit as an independent check. 08LG056 is the natural-flow target. Mamit Lake's outlet settings stay as uncalibrated guesses.
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