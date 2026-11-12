# calib/ — OSTRICH calibration of the Guichon Creek model

Automatic calibration of the baseline (pre-project) model with OSTRICH's DDS search.
Nothing in this folder changes the model files in the folder above until you copy the
best parameters back yourself (step 5).

## What is calibrated against what

| Gauge | Model outlet | Flow | Role | Score used |
|---|---|---|---|---|
| WSC 08LG056, Guichon Creek above Tunkwa Lake Diversion (76 km²) | subbasin 3 | natural (RHBN reference station) | main target | KGE, weight 0.75 |
| WSC 08LG041, Guichon Creek at outlet of Mamit Lake (870 km²) | subbasin 2 | regulated | timing check only | R², weight 0.25 |

Both scores are for the CALIBRATION period (1983-10-01 to 1999-09-30). 08LG056 has no
missing days in that period.

08LG041 is regulated, so its volume is not used: R² scores only the timing and shape of the
hydrograph. KGE at 08LG056 scores volume, variability and timing, and that gauge sits inside
subbasin 1, upstream of the solar site.

## Parameters (13)

| OSTRICH name | Raven parameter | File | Start | Range |
|---|---|---|---|---|
| `par_TT` | `RAINSNOW_TEMP` (°C) | .rvp | 0.5 | −1 to 2.5 |
| `par_CFMAX` | `MELT_FACTOR` (mm/d/K) | .rvp | 2.5 | 2.5 to 7 |
| `par_MINFRAC` | `MIN_MELT_FACTOR` ÷ `MELT_FACTOR` | .rvp | 0.6 | 0.2 to 1 |
| `par_SFCF` | `:SnowCorrection` | .rvt | 1.0 | 0.8 to 1.5 |
| `par_RFCF` | `:RainCorrection` | .rvt | 1.0 | 0.8 to 1.3 |
| `par_THICK` | TOPSOIL thickness (m) | .rvp | 2.0 | 0.3 to 2.0 |
| `par_BETA` | `HBV_BETA` | .rvp | 2.0 | 0.5 to 4 |
| `par_LP` | `FIELD_CAPACITY` | .rvp | 0.5 | 0.5 to 0.9 |
| `par_PERC` | `MAX_PERC_RATE`, fast reservoir (mm/d) | .rvp | 5.0 | 0.1 to 6 |
| `par_KF` | `BASEFLOW_COEFF`, fast reservoir (1/d) | .rvp | 0.05 | 0.01 to 0.5 |
| `par_BFN` | `BASEFLOW_N`, fast reservoir | .rvp | 1.5 | 1 to 3 |
| `par_KS` | `BASEFLOW_COEFF`, slow reservoir (1/d) | .rvp | 0.02 | 0.001 to 0.05 |
| `par_CRESTW` | Mamit Lake `:CrestWidth` (m) | .rvh | 10 | 1 to 30 |

- `MIN_MELT_FACTOR` is written as `par_MINFRAC × par_CFMAX`, so it can never exceed `MELT_FACTOR`.
- The TOPSOIL upper bound is 2.0 m (not the 1.5 m suggested for BC) so that the current value
  is inside the range. A result above 1.5 m is a warning sign, not a finding.
- `par_CRESTW` only affects 08LG041. It is there so that a wrong lake response is not
  absorbed by the snow and soil parameters.

Left fixed on purpose: `POROSITY` (0.36, from the soil survey), `HBV_MELT_FOR_CORR` (drives the
solar result and no forested HRU drains to 08LG056), `HBV_MELT_ASP_CORR` (no effect while HRU
slopes are 0), lapse rates, `TIME_CONC`, and everything about the solar site.

## Files

| File | Purpose |
|---|---|
| `ostIn.txt` | OSTRICH control file: parameters, ranges, objective, algorithm |
| `prepare.py` | Builds the templates and `model\` from the model files, and checks `ostIn.txt` |
| `hbvec.rvp.tpl`, `.rvt.tpl`, `.rvh.tpl` | Templates written by `prepare.py` (do not edit by hand) |
| `Ost-RAVEN.bat` | Runs Raven for one trial |
| `save_best.bat` | Keeps the best trial's files |
| `Ostrich.exe` | OSTRICH v17.12.19, from `RavenOstrichTutorialFiles.zip` on the Raven downloads page (not in git) |
| `model\`, `processor_0\`, `Ost*.txt` | Created by `prepare.py` and OSTRICH (not in git) |

## Steps

Run everything from `HBVEC_Model\calib\`.

1. **Prepare.** `python prepare.py`. It must end with "All checks passed".

2. **Test one Raven run** with the current parameters:
   ```
   cd model
   Raven.exe hbvec -o output\ -r calib
   cd ..
   ```
   Check that `model\output\Raven_errors.txt` has no errors, and that
   `model\output\calib_Diagnostics.csv` has rows `HYDROGRAPH_CALIBRATION[2]` and
   `HYDROGRAPH_CALIBRATION[3]` with KGE in column 4 and R2 in column 7.

3. **Test OSTRICH** (optional but quick): set `MaxIterations` to 3 in `ostIn.txt`, run
   `Ostrich.exe`, and check `OstErrors0.txt` is empty and `OstModel0.txt` has 3 or 4 rows with
   sensible objective values (between −1 and about 0). Then set it back to 1000 and delete
   `processor_0\` and the `Ost*.txt` output files.

4. **Calibrate.** `Ostrich.exe`. 1000 Raven runs. Progress is in `OstModel0.txt`; the result is
   in `OstOutput0.txt`; the best trial's input files are in `processor_0\best\`.

5. **Use the result.** Look at `processor_0\best\calib_Diagnostics.csv` first (including the
   VALIDATION rows, which were not used). If you accept it, copy `hbvec.rvp`, `hbvec.rvt` and
   `hbvec.rvh` from `processor_0\best\` over the ones in `HBVEC_Model\`, then run the baseline
   and solar runs as usual. The copies have the same text as the originals with only the 14
   numbers changed.

Before starting a new calibration, delete `processor_0\` and the `Ost*.txt` output files, and
re-run `prepare.py` if any model file changed.

## Things to know before trusting the result

- **Not yet run.** This setup has been checked for consistency by `prepare.py`, but neither
  Raven nor OSTRICH has been run with it. Steps 2 and 3 are the real test.
- **Validation period forcing looks unreliable.** At 08LG056 the share of Lornex precipitation
  that becomes runoff is about 12% in 1984–1999 but 25–45% in 2006–2011, while Lornex
  precipitation falls from about 404 to 329 mm/yr. Natural runoff rising while measured
  precipitation falls points to the Lornex record under-reporting in its last years. Expect
  poor VALIDATION scores for that reason, whatever the parameters.
- **Tunkwa Lake diversion.** 08LG056 is just upstream of a historic diversion out of Guichon
  Creek (WSC 08LG014, gauged 1919–1930). The model does not take any water out there. If the
  diversion still operates, flows at the subbasin 1 outlet are overstated in both runs.
- **08LG041 volume is not constrained.** Expect the model to overpredict volume there, because
  withdrawals and storage upstream of that gauge are not modelled.
- **A snow course exists** if the snow parameters need an independent check: BC Snow Survey
  1C09A Highland Valley (1510 m, active), inside the watershed. It is not used here.
