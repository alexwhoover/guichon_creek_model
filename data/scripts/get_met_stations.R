# Download ECCC daily climate data with the weathercan package and write one
# raw CSV per station:
#   data/raw/1123469_HighlandValleyLornex_daily.csv   (main station)
#   data/raw/1163780_KamloopsA_daily.csv              (gap-fill station)
#
# Usage (from Raven/HBVEC_Model):  Rscript data/scripts/get_met_stations.R
# Next step: Rscript data/scripts/fill_met_lornex.R

Sys.setenv(TZ = "America/Vancouver")
library(weathercan)

STATIONS <- c("1123469" = "HighlandValleyLornex",
              "1163780" = "KamloopsA")

keep <- c("date", "max_temp", "max_temp_flag", "min_temp", "min_temp_flag",
          "mean_temp", "mean_temp_flag", "total_precip", "total_precip_flag",
          "total_rain", "total_snow", "snow_grnd")

inv <- stations()

for (cid in names(STATIONS)) {
  # weathercan downloads by ECCC station_id, so look it up from the Climate ID
  stn <- inv[inv$climate_id == cid & inv$interval == "day", ]
  if (nrow(stn) != 1) stop("Expected one daily station for Climate ID ", cid)
  print(as.data.frame(stn[, c("station_name", "station_id", "climate_id", "lat", "lon",
                              "elev", "start", "end")]))

  d <- weather_dl(station_ids = stn$station_id, interval = "day")
  d <- d[, intersect(keep, names(d))]

  out <- file.path("data", "raw", paste0(cid, "_", STATIONS[[cid]], "_daily.csv"))
  write.csv(d, out, row.names = FALSE, na = "")
  cat("Wrote", nrow(d), "rows,", format(min(d$date)), "to", format(max(d$date)), "->", out, "\n\n")
}
