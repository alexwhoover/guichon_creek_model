@echo off
REM Run by OSTRICH from calib\processor_0\ each time a trial beats the best so far.
IF NOT EXIST best mkdir best

copy /y model\hbvec.rvp best\hbvec.rvp >nul
copy /y model\hbvec.rvt best\hbvec.rvt >nul
copy /y model\output\calib_Diagnostics.csv best\calib_Diagnostics.csv >nul
