@echo off
REM Run by OSTRICH once per trial, from calib\processor_0\.
REM OSTRICH has just written hbvec.rvp and hbvec.rvt here from the templates.

copy /y hbvec.rvp model\hbvec.rvp >nul
copy /y hbvec.rvt model\hbvec.rvt >nul

cd model
if not exist output mkdir output
REM Remove the last trial's scores so a failed run cannot be scored as if it were new
if exist output\calib_Diagnostics.csv del output\calib_Diagnostics.csv

Raven.exe hbvec -o output\ -r calib

cd ..
