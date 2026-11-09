# Fill gaps in the HIGHLAND VALLEY LORNEX (1123469) daily record using
# KAMLOOPS A (1163780), with monthly linear scaling:
#   temperature   : Lornex = Kamloops + offset_m       (additive, per calendar month)
#   precipitation : Lornex = Kamloops x ratio_m        (multiplicative, per calendar month)
# offset_m / ratio_m are computed from all days where BOTH stations have data.
# Tmax and Tmin get their own offsets.
#
# Days where Kamloops A is also missing:
#   temperature   -> linear interpolation in time between neighbouring days
#   precipitation -> 0
#
# Note on ECCC flags: accumulated precipitation is stored as 0 (flag C) on the
# days before, and the total on the last day (flag A). Those are not gaps and
# are left as recorded, so filling does not double-count them.
#
# Inputs  (from data/scripts/get_met_stations.R):
#   data/raw/1123469_HighlandValleyLornex_daily.csv
#   data/raw/1163780_KamloopsA_daily.csv
# Outputs:
#   data/processed/1123469_HighlandValleyLornex_filled_daily.csv
#       date, TEMP_MAX [C], TEMP_MIN [C], PRECIP [mm/d],
#       TEMP_MAX_SRC, TEMP_MIN_SRC, PRECIP_SRC  (OBS / KAMLOOPS / INTERP / ZERO)
#   data/processed/lornex_kamloops_scaling.csv   (monthly offsets and ratios used)
#
# Usage (from Raven/HBVEC_Model):  Rscript data/scripts/fill_met_lornex.R
# Next step: Rscript data/scripts/write_met_rvt.R

Sys.setenv(TZ = "America/Vancouver")   # avoids a harmless Windows timezone warning

lor <- read.csv("data/raw/1123469_HighlandValleyLornex_daily.csv")
kam <- read.csv("data/raw/1163780_KamloopsA_daily.csv")
lor$date <- as.Date(lor$date)
kam$date <- as.Date(kam$date)

# Complete daily sequence over the Lornex record, then attach both stations
d <- data.frame(date = seq(min(lor$date), max(lor$date), by = "day"))
d <- merge(d, lor[, c("date", "max_temp", "min_temp", "total_precip")], all.x = TRUE)
d <- merge(d, setNames(kam[, c("date", "max_temp", "min_temp", "total_precip")],
                       c("date", "k_tmax", "k_tmin", "k_p")), all.x = TRUE)
d <- d[order(d$date), ]
d$month <- as.integer(format(d$date, "%m"))

# ---- monthly scaling factors from overlapping days -------------------------
sc <- data.frame(month = 1:12)
for (m in 1:12) {
  x  <- d[d$month == m, ]
  tx <- !is.na(x$max_temp) & !is.na(x$k_tmax)
  tn <- !is.na(x$min_temp) & !is.na(x$k_tmin)
  pp <- !is.na(x$total_precip) & !is.na(x$k_p)
  sc$tmax_offset[m]  <- mean(x$max_temp[tx]) - mean(x$k_tmax[tx])
  sc$tmin_offset[m]  <- mean(x$min_temp[tn]) - mean(x$k_tmin[tn])
  sc$precip_ratio[m] <- sum(x$total_precip[pp]) / sum(x$k_p[pp])
  sc$n_days_tmax[m]  <- sum(tx)
  sc$n_days_tmin[m]  <- sum(tn)
  sc$n_days_precip[m] <- sum(pp)
}
sc[, c("tmax_offset", "tmin_offset", "precip_ratio")] <-
  round(sc[, c("tmax_offset", "tmin_offset", "precip_ratio")], 3)
write.csv(sc, "data/processed/lornex_kamloops_scaling.csv", row.names = FALSE)
cat("Monthly scaling (Lornex vs Kamloops A):\n"); print(sc, row.names = FALSE)

# ---- fill -------------------------------------------------------------------
fill <- function(obs, kam_val, adj, op) {
  src <- ifelse(!is.na(obs), "OBS", NA)
  est <- if (op == "+") kam_val + adj else kam_val * adj
  use <- is.na(obs) & !is.na(est)
  obs[use] <- est[use]; src[use] <- "KAMLOOPS"
  list(val = obs, src = src)
}
interp <- function(v, src, dates) {
  miss <- is.na(v)
  if (any(miss)) {
    v[miss] <- approx(as.numeric(dates[!miss]), v[!miss], as.numeric(dates[miss]), rule = 2)$y
    src[miss] <- "INTERP"
  }
  list(val = v, src = src)
}

tx <- fill(d$max_temp, d$k_tmax, sc$tmax_offset[d$month], "+")
tx <- interp(tx$val, tx$src, d$date)
tn <- fill(d$min_temp, d$k_tmin, sc$tmin_offset[d$month], "+")
tn <- interp(tn$val, tn$src, d$date)
pr <- fill(d$total_precip, d$k_p, sc$precip_ratio[d$month], "*")
pr$src[is.na(pr$val)] <- "ZERO"; pr$val[is.na(pr$val)] <- 0

# Keep Tmin <= Tmax after filling (only the filled days can break this)
swap <- tn$val > tx$val
if (any(swap)) {
  tmp <- tx$val[swap]; tx$val[swap] <- tn$val[swap]; tn$val[swap] <- tmp
}

out <- data.frame(date = format(d$date),
                  TEMP_MAX = round(tx$val, 1), TEMP_MIN = round(tn$val, 1),
                  PRECIP = round(pr$val, 1),
                  TEMP_MAX_SRC = tx$src, TEMP_MIN_SRC = tn$src, PRECIP_SRC = pr$src)
write.csv(out, "data/processed/1123469_HighlandValleyLornex_filled_daily.csv", row.names = FALSE)

cat("\nRows:", nrow(out), " ", out$date[1], "to", out$date[nrow(out)], "\n")
cat("Tmin/Tmax swapped on", sum(swap), "filled days\n")
for (v in c("TEMP_MAX_SRC", "TEMP_MIN_SRC", "PRECIP_SRC")) {
  cat(v, ":", paste(names(table(out[[v]])), table(out[[v]]), collapse = ", "), "\n")
}
cat("Wrote data/processed/1123469_HighlandValleyLornex_filled_daily.csv\n")
