# Compare the Lornex-station run with the Daymet run (same model, same parameters).
# This comparison is why Daymet replaced Lornex as the forcing (2026-11-12). The Lornex
# pipeline is archived in archive/lornex/ (not tracked by git).
#
# Runs (from Raven/HBVEC_Model):
#   Raven.exe hbvec -t archive/lornex/hbvec_lornex.rvt -o output\ -r lornex
#   Raven.exe hbvec -o output\ -r daymet
# Usage:  Rscript analysis/compare_lornex_daymet.R
# Writes: analysis/compare_lornex_daymet.pdf
#         analysis/compare_lornex_daymet_annual.csv (water-year forcing and flows)
# and prints the tables to the console.

Sys.setenv(TZ = "America/Vancouver")
suppressMessages({ library(ggplot2); library(grid) })

runs <- c(Lornex = "lornex", Daymet = "daymet")
cols <- c(Lornex = "#1b6ca8", Daymet = "#d1495b", Observed = "grey25")
wy   <- function(d) as.integer(format(d, "%Y")) + (as.integer(format(d, "%m")) >= 10)

# ---- diagnostics -------------------------------------------------------------
dg <- do.call(rbind, lapply(names(runs), function(r) {
  x <- read.csv(sprintf("output/%s_Diagnostics.csv", runs[r]), check.names = FALSE)
  x <- x[, colSums(!is.na(x)) > 0]
  data.frame(run = r, series = x$observed_data_series, NSE = x$DIAG_NASH_SUTCLIFFE,
             KGE = x$DIAG_KLING_GUPTA, PBIAS = x$DIAG_PCT_BIAS, R2 = x$DIAG_R2)
}))
dg$gauge  <- ifelse(grepl("\\[3\\]", dg$series), "08LG056 (natural)", "08LG041 (regulated)")
dg$period <- sub("HYDROGRAPH_|\\[.*", "", gsub("HYDROGRAPH_", "", dg$series))
dg <- dg[order(dg$gauge, dg$period, dg$run), c("gauge", "period", "run", "NSE", "KGE", "PBIAS", "R2")]
cat("\n== Diagnostics ==\n"); print(transform(dg, NSE = round(NSE, 2), KGE = round(KGE, 2),
                                             PBIAS = round(PBIAS, 1), R2 = round(R2, 2)), row.names = FALSE)

# ---- forcing (watershed means, after gauge corrections and orographic lapse) -
ff <- do.call(rbind, lapply(names(runs), function(r) {
  x <- read.csv(sprintf("output/%s_ForcingFunctions.csv", runs[r]), check.names = FALSE, strip.white = TRUE)
  names(x) <- trimws(names(x))
  data.frame(run = r, date = as.Date(x$date), P = x[["rain [mm/d]"]] + x[["snow [mm/d]"]],
             snow = x[["snow [mm/d]"]], T = x[["temp_daily_ave [C]"]], PET = x[["PET [mm/d]"]])
}))
ff$wy <- wy(ff$date)
ff <- ff[ff$wy >= 1984, ]   # skip spin-up year
fa <- aggregate(cbind(P, snow, PET) ~ run + wy, ff, sum)
fa$T <- aggregate(T ~ run + wy, ff, mean)$T

# ---- hydrographs -------------------------------------------------------------
gauges <- c("08LG056" = "Guichon_08LG056", "08LG041" = "Guichon_08LG041")
hy <- do.call(rbind, lapply(names(runs), function(r) {
  x <- read.csv(sprintf("output/%s_Hydrographs.csv", runs[r]), check.names = FALSE, strip.white = TRUE)
  do.call(rbind, lapply(names(gauges), function(g) {
    o <- x[[sprintf("%s (observed) [m3/s]", gauges[g])]]
    o[!is.na(o) & o < 0] <- NA
    data.frame(run = r, gauge = g, date = as.Date(x$date),
               sim = x[[sprintf("%s [m3/s]", gauges[g])]], obs = o)
  }))
}))
hy$wy <- wy(hy$date)
hy <- hy[hy$wy >= 1984 & !is.na(hy$obs), ]
ha <- aggregate(cbind(sim, obs) ~ run + gauge + wy, hy, mean)
ha$ratio <- ha$sim / ha$obs

ann <- merge(reshape(fa, idvar = "wy", timevar = "run", direction = "wide"),
             reshape(ha[ha$gauge == "08LG056", c("run", "wy", "sim", "obs")], idvar = "wy",
                     timevar = "run", direction = "wide"), by = "wy")
ann <- ann[, c("wy", "P.Lornex", "P.Daymet", "T.Lornex", "T.Daymet", "PET.Lornex", "PET.Daymet",
               "obs.Lornex", "sim.Lornex", "sim.Daymet")]
names(ann) <- c("water_year", "P_lornex_mm", "P_daymet_mm", "T_lornex_C", "T_daymet_C",
                "PET_lornex_mm", "PET_daymet_mm", "Q56_obs", "Q56_sim_lornex", "Q56_sim_daymet")
ann <- round(ann, 3)
write.csv(ann, "analysis/compare_lornex_daymet_annual.csv", row.names = FALSE)
cat("\n== Water years at 08LG056 (watershed P, T, PET; mean flow m3/s) ==\n")
print(transform(ann, P_lornex_mm = round(P_lornex_mm), P_daymet_mm = round(P_daymet_mm),
                T_lornex_C = round(T_lornex_C, 1), T_daymet_C = round(T_daymet_C, 1),
                PET_lornex_mm = round(PET_lornex_mm), PET_daymet_mm = round(PET_daymet_mm),
                Q56_obs = round(Q56_obs, 3), Q56_sim_lornex = round(Q56_sim_lornex, 3),
                Q56_sim_daymet = round(Q56_sim_daymet, 3)), row.names = FALSE)
per <- function(a, b) colMeans(ann[ann$water_year >= a & ann$water_year <= b, -1])
cat("\n== Period means ==\n")
print(round(rbind(`WY1984-2004` = per(1984, 2004), `WY2005-2011` = per(2005, 2011)), 3))

# ---- plots -------------------------------------------------------------------
theme_set(theme_minimal(base_size = 10) + theme(legend.position = "bottom", panel.grid.minor = element_blank()))
p_forc <- ggplot(fa, aes(wy, P, colour = run)) + geom_line() + geom_point(size = 1) +
  scale_colour_manual(values = cols, name = NULL) +
  labs(title = "Watershed-mean annual precipitation (as Raven applied it)",
       subtitle = "After :RainCorrection/:SnowCorrection and orographic lapse; water years",
       x = NULL, y = "mm / water year")
p_ann <- ggplot(ha, aes(wy)) +
  geom_line(aes(y = obs, colour = "Observed")) + geom_line(aes(y = sim, colour = run)) +
  facet_wrap(~gauge, ncol = 1, scales = "free_y") +
  scale_colour_manual(values = cols, name = NULL) +
  labs(title = "Annual mean flow", subtitle = "Days with observations only", x = NULL, y = "m³/s")
p_rat <- ggplot(ha, aes(wy, ratio, colour = run)) + geom_hline(yintercept = 1, colour = "grey50") +
  geom_line() + geom_point(size = 1) + facet_wrap(~gauge, ncol = 1) + scale_y_log10() +
  scale_colour_manual(values = cols, name = NULL) +
  labs(title = "Simulated / observed annual mean flow (log scale)", x = NULL, y = "ratio")

hy$doy <- as.integer(hy$date - as.Date(sprintf("%d-10-01", hy$wy - 1))) + 1
hy$era <- ifelse(hy$wy <= 2004, "WY1984–2004", "WY2005–2011")
reg <- aggregate(cbind(sim, obs) ~ run + gauge + era + doy, hy[hy$gauge == "08LG056", ], mean)
p_reg <- ggplot(reg, aes(doy)) + geom_line(aes(y = obs, colour = "Observed")) +
  geom_line(aes(y = sim, colour = run)) + facet_wrap(~era, ncol = 1) +
  scale_colour_manual(values = cols, name = NULL) +
  scale_x_continuous(breaks = c(1, 93, 185, 274), labels = c("Oct", "Jan", "Apr", "Jul")) +
  labs(title = "Mean daily hydrograph at 08LG056", x = NULL, y = "m³/s")

p_tab <- ggplot() + theme_void() +
  annotate("text", x = 0, y = 1, hjust = 0, vjust = 1, family = "mono", size = 3,
           label = paste(capture.output(print(transform(dg, NSE = round(NSE, 2), KGE = round(KGE, 2),
                                         PBIAS = round(PBIAS, 1), R2 = round(R2, 2)), row.names = FALSE)),
                         collapse = "\n")) +
  labs(title = "Diagnostics (Raven), Lornex vs Daymet forcing, same parameters") + xlim(0, 1) + ylim(0, 1)

pdf("analysis/compare_lornex_daymet.pdf", width = 8.5, height = 11)
print(p_tab); print(p_forc); print(p_ann); print(p_rat); print(p_reg)
invisible(dev.off())
cat("\nWrote analysis/compare_lornex_daymet.pdf and analysis/compare_lornex_daymet_annual.csv\n")
