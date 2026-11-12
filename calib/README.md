# calib/ — OSTRICH calibration of the Guichon Creek model

Automatic calibration of the baseline (pre-project) model with OSTRICH's DDS search.
Nothing in this folder changes the model files in the folder above until you copy the
best parameters back yourself (step 5).

## What is calibrated against what

| Gauge | Model outlet | Flow | Role |
|---|---|---|---|
| WSC 08LG056, Guichon Creek above Tunkwa Lake Diversion (76 km²) | subbasin 3 | natural (RHBN reference station) | calibration target: KGE |

The objective is KGE at 08LG056 for the CALIBRATION period, WY2005-2024 (2004-10-01 to
2024-09-30): present-day conditions, which the solar project will act on. VALIDATION is
WY1982-2004. Both are set by `:EvaluationPeriod` in `hbvec.rvi`. 08LG056 has no data from
Oct 2011 to Jan 2013; Raven skips those days. KGE scores volume, variability and timing, and
the gauge sits inside subbasin 1, upstream of the solar site.

08LG041 (regulated, at the Mamit Lake outlet) was never part of the objective. Its subbasin
(subbasin 2, with solar HRU 6 and the Mamit Lake reservoir) was removed from the model on
2026-11-12, because it is downstream of the subbasin 1 outlet and adds nothing to the result.
The 2026-11-12 calibration below was run before that, so its diagnostics still include
08LG041 rows (`[2]`); removing subbasin 2 does not change subbasins 1 and 3.

## Parameters (12)

| OSTRICH name | Raven parameter | File | Start | Range |
|---|---|---|---|---|
| `par_TT` | `RAINSNOW_TEMP` (°C) | .rvp | 0.727 | −1 to 2.5 |
| `par_CFMAX` | `MELT_FACTOR` (mm/d/K) | .rvp | 4.384 | 2.5 to 7 |
| `par_MINFRAC` | `MIN_MELT_FACTOR` ÷ `MELT_FACTOR` | .rvp | 0.209 | 0.2 to 1 |
| `par_SFCF` | `:SnowCorrection` (all 15 gauges) | .rvt | 0.896 | 0.8 to 1.5 |
| `par_RFCF` | `:RainCorrection` (all 15 gauges) | .rvt | 1.016 | 0.8 to 1.3 |
| `par_THICK` | TOPSOIL thickness (m) | .rvp | 1.456 | 0.3 to 2.0 |
| `par_BETA` | `HBV_BETA` | .rvp | 2.2 | 0.5 to 4 |
| `par_LP` | `FIELD_CAPACITY` | .rvp | 0.642 | 0.5 to 0.9 |
| `par_PERC` | `MAX_PERC_RATE`, fast reservoir (mm/d) | .rvp | 1.706 | 0.1 to 6 |
| `par_KF` | `BASEFLOW_COEFF`, fast reservoir (1/d) | .rvp | 0.0553 | 0.01 to 0.5 |
| `par_BFN` | `BASEFLOW_N`, fast reservoir | .rvp | 1.15 | 1 to 3 |
| `par_KS` | `BASEFLOW_COEFF`, slow reservoir (1/d) | .rvp | 0.0441 | 0.001 to 0.05 |

- Start values are the first (Lornex-forced) OSTRICH calibration of 2026-11-12, as rounded into
  the model files. DDS starts from them (`UseInitialParamValues`).
- `MIN_MELT_FACTOR` is written as `par_MINFRAC × par_CFMAX`, so it can never exceed `MELT_FACTOR`.
- The TOPSOIL upper bound is 2.0 m (not the 1.5 m suggested for BC) so that the current value
  is inside the range. A result above 1.5 m is a warning sign, not a finding.

Left fixed on purpose: `POROSITY` (0.36, from the soil survey), `HBV_MELT_FOR_CORR` (drives the
solar result), `HBV_MELT_ASP_CORR` (no effect while HRU
slopes are 0), lapse rates, `TIME_CONC`, and everything about the solar site.

## Files

| File | Purpose |
|---|---|
| `ostIn.txt` | OSTRICH control file: parameters, ranges, objective, algorithm |
| `prepare.py` | Builds the templates and `model\` from the model files, and checks `ostIn.txt` |
| `hbvec.rvp.tpl`, `hbvec.rvt.tpl` | Templates written by `prepare.py` (do not edit by hand) |
| `Ost-RAVEN.bat` | Runs Raven for one trial |
| `save_best.bat` | Keeps the best trial's files |
| `Ostrich.exe` | OSTRICH v17.12.19 (32-bit), from `RavenOstrichTutorialFiles.zip` on the Raven downloads page (not in git) |
| `msvcp120.dll`, `msvcr120.dll` | 32-bit Visual C++ 2013 runtime that `Ostrich.exe` needs. Copied from this PC's Microsoft Office folder (`...fs\ProgramFilesCommonX86\Microsoft Shared\Office16`). Not in git. Not needed if the Visual C++ 2013 x86 redistributable is installed |
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
   `model\output\calib_Diagnostics.csv` has a row `HYDROGRAPH_CALIBRATION[3]` with KGE in
   column 4.

3. **Test OSTRICH** (optional but quick): set `MaxIterations` to 3 in `ostIn.txt`, run
   `Ostrich.exe`, and check `OstErrors0.txt` is empty and `OstModel0.txt` has 3 or 4 rows with
   sensible objective values (minus the KGE, so about −1 to 0.5). Then set it back to 1000
   and delete `processor_0\` and the `Ost*.txt` output files.

4. **Calibrate.** `Ostrich.exe`. 1000 Raven runs. Progress is in `OstModel0.txt`; the result is
   in `OstOutput0.txt`; the best trial's input files are in `processor_0\best\`.

5. **Use the result.** Look at `processor_0\best\calib_Diagnostics.csv` first: the VALIDATION
   rows were not used in the calibration. If you accept it,
   copy `hbvec.rvp` and `hbvec.rvt` from `processor_0\best\` over the ones in `HBVEC_Model\`,
   then run the baseline and solar runs as usual. The copies have the same text as the
   originals with only the 13 numbers changed.

Before starting a new calibration, delete `processor_0\` and the `Ost*.txt` output files, and
re-run `prepare.py` if any model file changed.

## Things to know before trusting the result

- **Regime shift around 2004.** Observed flow at 08LG056 roughly doubled after about 2004
  while Daymet precipitation did not. Calibrating on WY2005-2024 fits present-day conditions;
  expect the VALIDATION period (WY1982-2004) to be over-predicted if the shift is real.
- **Tunkwa Lake diversion.** 08LG056 is just upstream of a historic diversion out of Guichon
  Creek (WSC 08LG014, gauged 1919–1930). The model does not take any water out there. If the
  diversion still operates, flows at the subbasin 1 outlet are overstated in both runs.
- **One gauge, higher ground.** The catchment above 08LG056 is mostly 1200–1750 m. The solar
  site (about 1215 m) and the rest of subbasin 1 are lower and drier, and the calibration
  assumes the same parameters hold there.
- **A snow course exists** if the snow parameters need an independent check: BC Snow Survey
  1C09A Highland Valley (1510 m, active), inside the watershed. It is not used here.
