#########################################################################
:FileType          rvp ASCII Raven 4.1
:CreationDate      2026-11-06
#
# Raven HBV-EC emulation - PARAMETER FILE
#
#------------------------------------------------------------------------

#========================================================================
# GLOBAL PARAMETERS
#========================================================================
:GlobalParameter RAINSNOW_TEMP     par_TT    # TT    [C]
:GlobalParameter RAINSNOW_DELTA    2.0    # TTI   [C]
:GlobalParameter SNOW_SWI          0.05   # CWH   [-]
:GlobalParameter ADIABATIC_LAPSE   6.5    # TCALT [C/km]
:GlobalParameter PRECIP_LAPSE      0.0    # PCALT [mm/d/km]
:AvgAnnualRunoff   34                     # mm/yr, 08LG041 WY1982-2024 mean (870.1 km2)

#========================================================================
# SOIL
#========================================================================
# Conceptual stores: TOPSOIL = soil box, FAST_RES = upper zone, SLOW_RES = lower zone
:SoilClasses
  :Attributes,
  :Units,
    TOPSOIL
    FAST_RES
    SLOW_RES
:EndSoilClasses

# FC [mm] = TOPSOIL thickness [m] x 1000 x POROSITY  (2.0 x 1000 x 0.36 = 720 mm)
# POROSITY 0.36 = BC SIFT texture mix (Rawls et al. 1982 means) x (1 - 23% coarse fragments)
:SoilProfiles
    LAKE,       0
    DEFAULT_P,  3,  TOPSOIL, par_THICK,  FAST_RES, 100.0,  SLOW_RES, 100.0
:EndSoilProfiles

# Soil / runoff generation (HBV names):
#   FIELD_CAPACITY = LP, HBV_BETA = BETA, MAX_CAP_RISE_RATE = CFLUX
#   FAST_RES: MAX_PERC_RATE = PERC, BASEFLOW_COEFF = KF, BASEFLOW_N = 1+ALPHA
#   SLOW_RES: BASEFLOW_COEFF = KS
:SoilParameterList
  :Parameters,  POROSITY,  FIELD_CAPACITY,  SAT_WILT,  HBV_BETA,  MAX_CAP_RISE_RATE,  MAX_PERC_RATE,  BASEFLOW_COEFF,  BASEFLOW_N
  :Units,           none,            none,      none,      none,               mm/d,           mm/d,             1/d,        none
    [DEFAULT],      0.36,           par_LP,       0.0,     par_BETA,                1.0,            0.0,             0.0,         0.0
    FAST_RES,   _DEFAULT,        _DEFAULT,       0.0,  _DEFAULT,           _DEFAULT,          par_PERC,          par_KF,       par_BFN
    SLOW_RES,   _DEFAULT,        _DEFAULT,       0.0,  _DEFAULT,           _DEFAULT,       _DEFAULT,          par_KS,         1.0
:EndSoilParameterList

#========================================================================
# VEGETATION
#========================================================================
# Mixed classes = f x forest (25 m, LAI 6) + (1-f) x open (0.5 m, LAI 1)
#   MIX20_VEG   20% forest   SB1 + SB3 (HRUs 2-5, 12-15) and solar site pre-project (HRUs 1, 6)
#   MIX40_VEG   40% forest   SB2 bands (HRUs 7-11)
#   SOLAR_VEG    0% forest   solar site post-project
# MAX_HT and MAX_LAI do not affect this HBV-EC setup (PRECIP_ICEPT_USER, PET_FROMMONTHLY,
# SOILEVAP_HBV); forest effects act through FOREST_COV (interception and melt) only.
:VegetationClasses
  :Attributes,  MAX_HT,  MAX_LAI,  MAX_LEAF_COND
  :Units,            m,     none,       mm_per_s
    MIX20_VEG,     5.4,      2.0,            5.3
    MIX40_VEG,    10.3,      3.0,            5.3
    SOLAR_VEG,     0.5,      1.0,            5.3
:EndVegetationClasses

:VegetationParameterList
  :Parameters,  MAX_CAPACITY,  MAX_SNOW_CAPACITY
  :Units,                 mm,                 mm
    MIX20_VEG,         10000,              10000
    MIX40_VEG,         10000,              10000
    SOLAR_VEG,         10000,              10000
:EndVegetationParameterList

#========================================================================
# LAND USE
#========================================================================
# FOREST_COV must match the vegetation class above
:LandUseClasses
  :Attributes,  IMPERM,  FOREST_COV
  :Units,         frac,        frac
    MIX20_LU,      0.0,         0.2
    MIX40_LU,      0.0,         0.4
    SOLAR,         1.0,         0.0    # worst case: fully impervious, no forest
:EndLandUseClasses

# Snow melt (POTMELT_HBV): CFMAX, MIN_MELT, MRF, CFR, AM
:LandUseParameterList
  :Parameters,  MELT_FACTOR,  MIN_MELT_FACTOR,  HBV_MELT_FOR_CORR,  REFREEZE_FACTOR,  HBV_MELT_ASP_CORR
  :Units,            mm/d/K,           mm/d/K,               none,           mm/d/K,               none
    [DEFAULT],        par_CFMAX,            par_CFMIN,                0.5,              2.0,               0.48
:EndLandUseParameterList

:LandUseParameterList
  :Parameters,  LAKE_REL_COEFF
  :Units,                  1/d
    [DEFAULT],             0.0
:EndLandUseParameterList

#========================================================================
# SCENARIO: none here. This file is the baseline (pre-project).
# The solar (post-project) run uses hbvec_solar.rvp, which includes this file and adds the
# :LandUseChange / :VegetationChange for SOLAR_SITE:
#   Raven.exe hbvec -p hbvec_solar.rvp -o output\ -r solar
#========================================================================
