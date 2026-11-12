# data/

Inputs for the Guichon Creek Raven HBV-EC model.

```
data/
├── daymet/              Raven daily forcing (Tmax, Tmin, precip), one file per HRU. Read by hbvec.rvt
│   └── met_daymet_hruNN.rvt   Daymet V4 R1, area-weighted mean over HRU NN
├── obs_flow_daily.rvt   Raven observed flow at 08LG041 (subbasin 2). Read by hbvec.rvt
├── obs_flow_08LG056_daily.rvt   Raven observed flow at 08LG056 (subbasin 3). Read by hbvec.rvt
├── raw/                 Downloaded data, never edited by hand
│   ├── 08LG041_daily_HYDAT.csv                  WSC 08LG041 daily flow + HYDAT symbols
│   ├── 08LG056_daily_HYDAT.csv                  WSC 08LG056 daily flow + HYDAT symbols (1982 on)
│   └── daymet/pt_NNNN.csv                       Daymet single-pixel downloads (git-ignored, ~300 MB)
├── processed/           Products of the scripts below
│   ├── daymet_points.csv                        Daymet sample points (point_id, HRU_ID, lon, lat)
│   ├── daymet_hru_daily.csv                     HRU-mean daily Daymet forcing
│   ├── daymet_hru_normals.csv                   monthly temp + Hargreaves PET per HRU (in hbvec.rvt)
│   ├── hru_attributes.csv                       HRU attributes from GIS (source of the .rvh HRU table)
│   └── hru_split_08LG056.csv                    HRU rows for the split of subbasin 1 at 08LG056
└── scripts/
    ├── get_obs_08LG041.py   download flow   -> raw/08LG041_daily_HYDAT.csv, obs_flow_daily.rvt
    ├── get_obs_08LG056.py   download flow   -> raw/08LG056_daily_HYDAT.csv, obs_flow_08LG056_daily.rvt
    ├── get_daymet.R         download Daymet at sample points over each HRU -> raw/daymet/, processed/daymet_points.csv
    ├── write_daymet_rvt.R   HRU means -> daymet/*.rvt, processed/daymet_hru_*.csv, ../hbvec.rvt
    ├── hru_attributes_arcpy.py   HRU attributes in ArcGIS -> processed/hru_attributes.csv
    ├── split_08LG056_subbasin.R   08LG056 catchment from the CLRH hydrofabric -> processed/hru_split_08LG056.csv,
    │                              delineation_copy/catchment_08LG056.shp
    └── export_gis_layers.R  HRUs + subbasins as modelled, with attributes -> ArcGIS geodatabase
                             (hrus_v3_08LG056, subbasins_v3_08LG056; close ArcGIS Pro first)
```

The `.rvt` files stay under `data/` because `hbvec.rvt` points to them with
`:RedirectToFile`.

## Forcing: Daymet (since 2026-11-12)

Daymet V4 R1 (1 km daily grid; Thornton et al. 2022, https://doi.org/10.3334/ORNLDAAC/2129)
replaced the ECCC Highland Valley Lornex station, which reads low after about 1999 relative to
the regional estimate. See `archive/lornex/compare_lornex_daymet.pdf` (local only). The Lornex pipeline (station
downloads, Kamloops A gap-fill, `met_daily.rvt`, its `hbvec.rvt`) is in `archive/lornex/`.

- **Download:** Daymet's NetCDF server needs a NASA Earthdata login, so `get_daymet.R` uses the
  open single-pixel API. Points sit on a 2 km grid in each HRU (250 m for HRUs with fewer than
  5 points), so the mean of an HRU's points is its area-weighted mean.
- **Virtual gauges:** `hbvec.rvt` has one gauge per HRU at that HRU's lat/lon/elevation from
  `hbvec.rvh`. Nearest-neighbour interpolation then gives each HRU its own gauge, and
  `OROCORR_HBV` applies no lapse because Daymet already includes elevation effects.
- **Leap years:** Daymet omits Dec 31. It is filled with Dec 30's temperatures and zero precip.
- **If the HRUs change** (new .rvh), re-run both scripts: the sample points and gauge locations
  come from the HRU polygons and the .rvh.

## Rebuild everything

Run these from `HBVEC_Model/`:

```
python data/scripts/get_obs_08LG041.py
python data/scripts/get_obs_08LG056.py
Rscript data/scripts/get_daymet.R        # ~850 requests; skips points already downloaded
Rscript data/scripts/write_daymet_rvt.R  # rewrites hbvec.rvt, keeping its :RainCorrection/:SnowCorrection
```
