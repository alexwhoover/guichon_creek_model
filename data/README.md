# data/

Inputs for the Guichon Creek Raven HBV-EC model.

```
data/
├── met_daily.rvt        Raven daily forcing (Tmax, Tmin, precip). Read by hbvec.rvt
├── obs_flow_daily.rvt   Raven observed flow at 08LG041 (subbasin 2). Read by hbvec.rvt
├── obs_flow_08LG056_daily.rvt   Raven observed flow at 08LG056 (subbasin 3). Read by hbvec.rvt
├── raw/                 Downloaded data, never edited by hand
│   ├── 08LG041_daily_HYDAT.csv                  WSC 08LG041 daily flow + HYDAT symbols
│   ├── 08LG056_daily_HYDAT.csv                  WSC 08LG056 daily flow + HYDAT symbols (1982 on)
│   ├── 1123469_HighlandValleyLornex_daily.csv   ECCC Highland Valley Lornex (main met station)
│   └── 1163780_KamloopsA_daily.csv              ECCC Kamloops A (gap-fill station)
├── processed/           Products of the scripts below
│   ├── 1123469_HighlandValleyLornex_filled_daily.csv   gap-free Lornex; *_SRC columns flag filled days
│   ├── lornex_kamloops_scaling.csv                     monthly offsets / ratios used for the fill
│   ├── hru_split_08LG056.csv                           HRU rows for the split of subbasin 1 at 08LG056
│   └── lornex_monthly_normals.csv                      monthly temp + Hargreaves PET for hbvec.rvt
└── scripts/
    ├── get_obs_08LG041.py   download flow   -> raw/08LG041_daily_HYDAT.csv, obs_flow_daily.rvt
    ├── get_obs_08LG056.py   download flow   -> raw/08LG056_daily_HYDAT.csv, obs_flow_08LG056_daily.rvt
    ├── split_08LG056_subbasin.R   08LG056 catchment from the CLRH hydrofabric -> processed/hru_split_08LG056.csv,
    │                              delineation_copy/catchment_08LG056.shp
    ├── get_met_stations.R   download met    -> raw/<climate_id>_*_daily.csv  (weathercan)
    ├── export_gis_layers.R  HRUs + subbasins as modelled, with attributes -> ArcGIS geodatabase
    │                        (hrus_v3_08LG056, subbasins_v3_08LG056; close ArcGIS Pro first)
    ├── fill_met_lornex.R    fill Lornex gaps from Kamloops A (monthly linear scaling) -> processed/
    └── write_met_rvt.R      write met_daily.rvt + monthly normals
```

The `.rvt` files stay at the top of `data/` because `hbvec.rvt` points to them with
`:RedirectToFile`.

## Rebuild everything

Run these from `HBVEC_Model/`:

```
python data/scripts/get_obs_08LG041.py
Rscript data/scripts/get_met_stations.R
Rscript data/scripts/fill_met_lornex.R
Rscript data/scripts/write_met_rvt.R
```

If the normals change, copy the `:MonthlyAveTemperature` and `:MonthlyAveEvaporation` lines that
`write_met_rvt.R` prints into the gauge block in `hbvec.rvt`.
