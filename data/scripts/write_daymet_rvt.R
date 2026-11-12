# Build the model's forcing file hbvec.rvt from Daymet: one virtual gauge per HRU.
# Daymet replaced the ECCC Highland Valley Lornex station on 2026-11-12 (the Lornex pipeline
# is in archive/lornex/; the comparison is analysis/compare_lornex_daymet.pdf).
#
# Each HRU's daily Tmax, Tmin and precipitation is the mean of the Daymet sample points
# inside it (equal-area 2 km grid, see get_daymet.R), i.e. the HRU's area-weighted mean.
# Each gauge is placed at its HRU's LATITUDE/LONGITUDE/ELEVATION from hbvec.rvh, so:
#   - INTERP_NEAREST_NEIGHBOR assigns every HRU its own gauge (distance 0), and
#   - OROCORR_HBV applies no lapse (HRU elevation - gauge elevation = 0). Daymet already
#     includes elevation effects, so this avoids correcting for elevation twice.
#
# :RainCorrection / :SnowCorrection are carried over from the existing hbvec.rvt (all gauges
# must share one value), so calibrated values survive a rebuild. The current values were
# calibrated with Lornex forcing and have not yet been recalibrated for Daymet.
# PET_FROMMONTHLY normals are computed per HRU with Hargreaves (1985), from the HRU's
# Daymet temperatures, over the model period 1982-10..2011-09.
#
# Daymet uses a 365-day calendar: in leap years Dec 31 is omitted. It is filled here with
# Dec 30's temperatures and zero precipitation.
#
# Inputs : data/processed/daymet_points.csv, data/raw/daymet/pt_NNNN.csv (from get_daymet.R)
#          hbvec.rvh (HRU locations), hbvec.rvt (gauge corrections, observed-flow redirects)
# Outputs: data/processed/daymet_hru_daily.csv     HRU-mean daily forcing
#          data/processed/daymet_hru_normals.csv   monthly temperature + PET per HRU
#          data/daymet/met_daymet_hruNN.rvt        :MultiData per HRU
#          hbvec.rvt                               gauge blocks + observed flow (overwritten)
#
# Usage (from Raven/HBVEC_Model):  Rscript data/scripts/write_daymet_rvt.R
# Run:   Raven.exe hbvec -o output\ -r baseline

Sys.setenv(TZ = "America/Vancouver")

NORM_START <- as.Date("1982-10-01")
NORM_END   <- as.Date("2011-09-30")
dir.create("data/daymet", showWarnings = FALSE)

# ---- read and average the point series ---------------------------------------
pts <- read.csv("data/processed/daymet_points.csv")
read_pt <- function(id) {
  f  <- sprintf("data/raw/daymet/pt_%04d.csv", id)
  ln <- readLines(f)
  x  <- read.csv(text = ln[grep("^year,", ln):length(ln)], check.names = FALSE)
  data.frame(date = as.Date(sprintf("%d-01-01", x$year)) + x$yday - 1,
             tmax = x[["tmax (deg c)"]], tmin = x[["tmin (deg c)"]], prcp = x[["prcp (mm/day)"]])
}
all <- do.call(rbind, lapply(seq_len(nrow(pts)), function(i) cbind(HRU_ID = pts$HRU_ID[i], read_pt(pts$point_id[i]))))
d   <- aggregate(cbind(tmax, tmin, prcp) ~ HRU_ID + date, all, mean)

# fill the Dec 31 that Daymet omits in leap years
days <- seq(min(d$date), max(d$date), by = "day")
full <- merge(expand.grid(HRU_ID = sort(unique(d$HRU_ID)), date = days), d, all.x = TRUE)
full <- full[order(full$HRU_ID, full$date), ]
miss <- is.na(full$prcp)
stopifnot(all(format(full$date[miss], "%m-%d") == "12-31"))
full$tmax[miss] <- full$tmax[which(miss) - 1]
full$tmin[miss] <- full$tmin[which(miss) - 1]
full$prcp[miss] <- 0
cat("Filled", sum(miss), "leap-year Dec 31 HRU-days\n")
write.csv(transform(full, tmax = round(tmax, 2), tmin = round(tmin, 2), prcp = round(prcp, 2)),
          "data/processed/daymet_hru_daily.csv", row.names = FALSE)

# ---- HRU locations from hbvec.rvh --------------------------------------------
rvh  <- readLines("hbvec.rvh")
rows <- grep("^\\s+\\d+,\\s+[0-9.]+,\\s+[0-9.]+,\\s+[0-9.]+,\\s+-", rvh, value = TRUE)
f    <- strsplit(sub("#.*", "", rows), ",")
loc  <- data.frame(HRU_ID = as.integer(sapply(f, `[`, 1)), elev = trimws(sapply(f, `[`, 3)),
                   lat = trimws(sapply(f, `[`, 4)), lon = trimws(sapply(f, `[`, 5)))
stopifnot(setequal(loc$HRU_ID, unique(full$HRU_ID)))

# ---- gauge corrections and observed-flow redirects from hbvec.rvt -----------
rvt  <- readLines("hbvec.rvt")
rain <- unique(trimws(grep("^\\s*:RainCorrection", rvt, value = TRUE)))
snow <- unique(trimws(grep("^\\s*:SnowCorrection", rvt, value = TRUE)))
obs  <- grep("^:RedirectToFile data/obs_", rvt, value = TRUE)
stopifnot(length(rain) == 1, length(snow) == 1, length(obs) == 2)   # one value shared by all gauges
corr <- paste0("  ", c(rain, snow))

# ---- Hargreaves (1985) PET from Tmax, Tmin and extraterrestrial radiation ----
hargreaves <- function(date, tmax, tmin, lat) {
  J     <- as.integer(format(date, "%j"))
  phi   <- lat * pi / 180
  dr    <- 1 + 0.033 * cos(2 * pi * J / 365)
  delta <- 0.409 * sin(2 * pi * J / 365 - 1.39)
  ws    <- acos(pmin(pmax(-tan(phi) * tan(delta), -1), 1))
  Ra    <- 24 * 60 / pi * 0.0820 * dr * (ws * sin(phi) * sin(delta) + cos(phi) * cos(delta) * sin(ws))
  pmax(0, 0.0023 * 0.408 * Ra * ((tmax + tmin) / 2 + 17.8) * sqrt(pmax(tmax - tmin, 0)))
}

# ---- write per-HRU forcing and the .rvt --------------------------------------
out <- c("#########################################################################",
         ":FileType          rvt ASCII Raven 4.1",
         sprintf(":CreationDate      %s", format(Sys.Date())),
         "#",
         "# Raven HBV-EC emulation - TIME SERIES FILE (Daymet forcing + observed flow)",
         "# One virtual gauge per HRU, holding the HRU's area-weighted Daymet V4 R1 forcing.",
         "# Generated by data/scripts/write_daymet_rvt.R. Run with:",
         "#   Raven.exe hbvec -o output\\ -r baseline",
         "#------------------------------------------------------------------------", "")
normals <- list()
for (h in sort(loc$HRU_ID)) {
  x  <- full[full$HRU_ID == h, ]
  L  <- loc[loc$HRU_ID == h, ]
  fn <- sprintf("data/daymet/met_daymet_hru%02d.rvt", h)
  con <- file(fn, "w")
  writeLines(c(sprintf("# Daymet V4 R1 daily forcing, area-weighted mean over HRU %d (%d sample points)",
                       h, sum(pts$HRU_ID == h)),
               "# Generated by data/scripts/write_daymet_rvt.R. PRECIP = total precipitation, mm/d.",
               ":MultiData", sprintf(" %s 00:00:00  1.0  %d", format(x$date[1]), nrow(x)),
               ":Parameters  TEMP_DAILY_MAX  TEMP_DAILY_MIN  PRECIP",
               ":Units       C               C               mm/d"), con)
  # round first, then + 0 turns -0 into 0: Raven rejects "-0.00" as non-numeric
  r2 <- function(v) round(v, 2) + 0
  writeLines(sprintf(" %6.2f  %6.2f  %6.2f", r2(x$tmax), r2(x$tmin), r2(x$prcp)), con)
  writeLines(":EndMultiData", con)
  close(con)

  p <- x[x$date >= NORM_START & x$date <= NORM_END, ]
  m <- as.integer(format(p$date, "%m"))
  tav <- tapply((p$tmax + p$tmin) / 2, m, mean)
  pet <- tapply(hargreaves(p$date, p$tmax, p$tmin, as.numeric(L$lat)), m, mean)
  normals[[length(normals) + 1]] <- data.frame(HRU_ID = h, month = 1:12, temp_ave_C = round(tav, 1),
                                               pet_mm_d = round(pet, 2))
  out <- c(out,
    sprintf(":Gauge Daymet_HRU%02d", h),
    sprintf("  :Latitude     %s", L$lat),
    sprintf("  :Longitude    %s", L$lon),
    sprintf("  :Elevation    %s      # = HRU elevation, so OROCORR_HBV applies no lapse", L$elev),
    corr,
    sprintf("  :MonthlyAveTemperature, %s", paste(sprintf("%5.1f", tav), collapse = ", ")),
    sprintf("  :MonthlyAveEvaporation, %s", paste(sprintf("%5.2f", pet), collapse = ", ")),
    sprintf("  :RedirectToFile %s", fn),
    ":EndGauge", "")
}
out <- c(out, "# Observed streamflow: WSC 08LG041 (subbasin 2, regulated) and 08LG056 (subbasin 3, natural)", obs)
writeLines(out, "hbvec.rvt")
write.csv(do.call(rbind, normals), "data/processed/daymet_hru_normals.csv", row.names = FALSE)
cat("Wrote hbvec.rvt and", length(loc$HRU_ID), "files in data/daymet/\n")
