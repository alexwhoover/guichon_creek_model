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
| Subbasin 2 | Remainder to 08LG041, contains Mamit Lake. `DOWNSTREAM_ID = -1`. `GAUGED = 1` (calibration). |
| Elevation range | ~800–1900 m |
| Elevation bands | 1: <1000, 2: 1000–1200, 3: 1200–1400, 4: 1400–1600, 5: 1600+ (top merged; 1800–1900 is a sliver) |
| Solar HRU | Footprint clipped to the watershed (~2.1 km²). Always its own HRU, never merged. `BAND = 0` in GIS. |
| Mamit Lake | Lake-like `:Reservoir` at the subbasin 2 outlet. No lake HRU in v1 (`:HRUID` omitted, so lake evaporation is ignored). |
| CRS | NAD83 BC Environment Albers (EPSG:3005) for all GIS work; WGS84 decimal degrees for HRU lat/lon |

## Naming conventions
- **Subbasin IDs:** 1 = `Guichon_BelowSolar`, 2 = `Guichon_08LG041`
- **HRU IDs:** sequential 1…N, taken from the `HRU_ID` field of `data/delineation_copy/hrus_final.shp`. Solar HRUs are 1 (SB1) and 6 (SB2). Attributes come from `data/scripts/hru_attributes_arcpy.py` → `data/processed/hru_attributes.csv`.
- **Baseline classes (v1, all HRUs):** `DEFAULT_LU`, `DEFAULT_VEG`, `DEFAULT_P`
- **Scenario classes:** `SOLAR` (land use) and `SOLAR_VEG` (vegetation)
- **HRU group:** `SOLAR_SITE`. Declare it in the .rvi with `:DefineHRUGroups` and populate it in the .rvh.
- **Channel profile:** `CHAN_GUICHON`
- **Run names:** `baseline`, `solar` (with variants such as `solar_lo` / `solar_hi` for sensitivity)

## Model configuration decisions
- **Template:** Raven manual v4.1, Appendix F.2 (HBV-EC), with these changes:
  - `:Routing ROUTE_DIFFUSIVE_WAVE`. The template's `ROUTE_NONE` is for single-subbasin models only. This requires a `:ChannelProfile` in the .rvp.
  - Delete the glacier lines: Flush→GLACIER and its conditional, `GlacierMelt`, and `GlacierRelease`.
  - Keep `:LakeStorage SLOW_RESERVOIR` (an HBV-EC quirk).
- **Time step and periods:** daily. Include one spin-up year before the calibration period, and set it with `:EvaluationPeriod`.
- **Metrics:** `:EvaluationMetrics NASH_SUTCLIFFE KLING_GUPTA PCT_BIAS`
- **Scenario method:** put `:LandUseChange` and `:VegetationChange` for `SOLAR_SITE` at the bottom of the .rvp, dated `1900-01-01`. Because that is before `:StartDate`, Raven applies the change at t = 0, so both runs use identical forcings over the full record.

## Raven gotchas (check these first when debugging)
- **Aspect direction:** Raven measures aspect counter-clockwise from north (west = 90°). From GIS sine/cosine means, use `ASPECT = degrees(atan2(-sin_mean, cos_mean)) % 360`.
- **Units:** precipitation must be in mm/d, even for sub-daily data.
- **Missing values:** the blank/missing-data flag is `-1.2345`.
- **Time intervals:** the interval in `:Data`, `:MultiData` and `:ObservationData` headers must be a decimal (e.g. `1.0`), not `hh:mm:ss`.
- **HRU group order:** define HRU groups in the .rvi before populating them in the .rvh.
- **RVP template:** add `:CreateRVPTemplate` to the .rvi, run once to generate a blank .rvp, then remove the line (the model will not run while it is present).
- **Gauge elevation:** this must be correct, because `OROCORR_HBV` lapses temperature and precipitation from it to each HRU.
- **PET inputs:** `PET_FROMMONTHLY` needs `:MonthlyAveTemperature` and `:MonthlyAveEvaporation` in the gauge block.
- **After every run:** check `RavenErrors.txt` before looking at results.

## Run commands
```
Raven.exe Guichon -o output\ -r baseline
Raven.exe Guichon -o output\ -r solar
```
Outputs to compare: `<run>_Hydrographs.csv` (subbasin 1 for the answer, subbasin 2 against observed) and `<run>_Diagnostics.csv`.

## Calibration
- **Parameters, roughly in order:** `RAINSNOW_TEMP`, `MELT_FACTOR` / `MIN_MELT_FACTOR`, `:RainCorrection` / `:SnowCorrection`, `HBV_BETA`, `FIELD_CAPACITY`, `BASEFLOW_COEFF` (fast and slow), `MAX_PERC_RATE`, `TIME_CONC`
- **Method:** manual first, then OSTRICH if needed
- **Solar-site parameters are not calibrated.** The flow record cannot constrain `FOREST_COV`, `IMPERM` or interception for the site, so set them from literature or judgment and bracket them with low, central and high scenarios.

## Reference documents
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