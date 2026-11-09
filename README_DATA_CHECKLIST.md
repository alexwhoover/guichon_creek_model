# HBV-EC Raven model: data checklist

These files are a template. The process list follows Raven Manual v4.1 Appendix F.2. The structure is based on the Alouette2 (HBV-EC) and Salmon_HBV tutorials. Every line marked `>>> TODO` has to be replaced with a value for your basin.

| File | What it holds | Where the data comes from |
|---|---|---|
| `hbvec.rvi` | Run dates and model structure | You choose |
| `hbvec.rvh` | Subbasin and HRUs | GIS: DEM, land cover, basin outline |
| `hbvec.rvp` | Parameters | Starting values, then calibration |
| `hbvec.rvt` | Met gauge and monthly normals | Climate station or gridded data |
| `data/met_daily.rvt` | Daily Tmax, Tmin, precipitation | Climate station or gridded data |
| `data/obs_flow_daily.rvt` | Observed daily flow | Hydrometric gauge |
| `hbvec.rvc` | Initial storages | Rough guesses; the warm-up year makes them unimportant |

## Step 1: Define the basin outlet and boundary (GIS)
- [ ] The streamflow gauge you will calibrate to: its station ID, latitude and longitude, and its **published drainage area**.
- [ ] A basin polygon delineated from a DEM down to that gauge. Its area should match the published drainage area to within a few %.

## Step 2: Build the HRUs (GIS, goes into `hbvec.rvh`)
- [ ] **DEM**, used to split the basin into elevation bands. Use 200–500 m bands, or 3–10 bands in total.
- [ ] **Land cover**, used to get the forested and open fraction of each band.
- [ ] **Glacier and lake extents**, if the basin has any.
- [ ] For each HRU: AREA (km²), mean ELEVATION (m), centroid LAT/LON, mean SLOPE (deg) and mean ASPECT (deg clockwise from N).
- [ ] Check that the HRU areas add up to the drainage area.
- [ ] Update the `:HRUGroup AllHRUs` range, and the number of values in `hbvec.rvc`.

## Step 3: Gather the daily meteorological forcing (`data/met_daily.rvt`)
- [ ] Daily **max temperature** (°C), **min temperature** (°C) and **total precipitation** (mm/day).
- [ ] The record must be gap-free over the whole run period. Fill any gaps first, from a nearby station or from gridded data.
- [ ] The station (or grid point) **latitude, longitude and elevation**, which go in `hbvec.rvt`. The elevation matters because temperature and precipitation are lapsed from it to each HRU.
- Possible sources: an ECCC/NOAA climate station, Daymet, ERA5-Land, or a provincial or state network.

## Step 4: Calculate the monthly climate normals (`hbvec.rvt`)
- [ ] `:MonthlyAveTemperature` has 12 values of mean monthly temperature (°C) at the gauge, which you can calculate from the Step 3 data.
- [ ] `:MonthlyAveEvaporation` has 12 values of mean monthly **PET in mm/day** (not mm/month). Sources include published PET or lake-evaporation normals, or a calculation from your temperature data (Hargreaves, Oudin, etc.).

## Step 5: Gather the observed streamflow (`data/obs_flow_daily.rvt`)
- [x] Daily mean flow (m³/s) at the outlet gauge, covering the same period as the met data. **Done:** WSC 08LG041, 1982-01-01 to 2024-12-31, from HYDAT via `data/scripts/get_obs_08LG041.py`. Raw values and flags are in `data/raw/08LG041_daily_HYDAT.csv`. See `data/README.md` for the full data pipeline.
- [x] Mark missing days with `-1.2345`.
- Possible sources: WSC HYDAT (Canada) or USGS NWIS (USA).

## Step 6: Set the run period (`hbvec.rvi`)
- [ ] Set `:StartDate` and `:EndDate` to fall inside both the met record and the flow record.
- [ ] Allow at least one year of warm-up before the first `:EvaluationPeriod`.
- [ ] Split the remaining years into CALIBRATION and VALIDATION periods.

## Step 7: Run the model
```
Raven.exe hbvec -o output/
```
Look at `output/Raven_errors.txt` first, then `Hydrographs.csv`, `Diagnostics.csv` and `ForcingFunctions.csv`. Use the last one to check that PET, temperature and precipitation look sensible.

## Step 8: Calibrate (`hbvec.rvp`, `hbvec.rvt`, `hbvec.rvh`)
There are 21 classic HBV-EC parameters. Each one is tagged in the file comments (HBV_PARA_01 to 21, as in the Salmon_HBV tutorial). The ones that matter most are usually these:
- Snow: RAINSNOW_TEMP, MELT_FACTOR, SnowCorrection
- Soil: TOPSOIL thickness and POROSITY (together they set FC), FIELD_CAPACITY (LP), HBV_BETA
- Runoff: FAST_RES and SLOW_RES BASEFLOW_COEFF, MAX_PERC_RATE, TIME_CONC (MAXBAS)
- Water balance: RainCorrection and SnowCorrection

Calibrate by hand (see Walkthrough 3) or with OSTRICH.

## Optional data that helps
- **Snow survey or snow pillow SWE**, to check the snowpack (Walkthrough 3, section 3.4).
- **Several met stations**. Add another `:Gauge` block for each one. With nearest-neighbour interpolation, each HRU uses its closest gauge.
