# Interactive dygraph of the baseline and solar runs (zoomable HTML).
#
# Runs (from Raven/HBVEC_Model):
#   Raven.exe hbvec -o output\ -r baseline
#   Raven.exe hbvec -p hbvec_solar.rvp -o output\ -r solar
# Usage:  Rscript analysis/plot_solar_dygraph.R
# Writes: output/plots/solar_vs_baseline_dygraph.html (needs output/plots/lib)
#
# Three stacked charts with linked zoom (drag to zoom, double-click to reset, range
# selector under the last chart):
#   1. Subbasin 1 outlet (Guichon Creek below the solar site): baseline and solar
#   2. Subbasin 1 outlet: solar - baseline
#   3. Subbasin 2 outlet (Mamit Lake, includes solar HRU 6): baseline and solar

Sys.setenv(TZ = "America/Vancouver")
suppressPackageStartupMessages({ library(dygraphs); library(xts); library(htmltools) })

blue <- "#2a78d6"; orange <- "#eb6834"
rd <- function(run) {
  x <- read.csv(sprintf("output/%s_Hydrographs.csv", run), check.names = FALSE, strip.white = TRUE)
  x[-1, ]                                     # drop t = 0 (initial condition row)
}
b <- rd("baseline"); s <- rd("solar")
stopifnot(identical(b$date, s$date))
t <- as.Date(b$date)

q1 <- xts(cbind(Baseline = b[["Guichon_BelowSolar [m3/s]"]], Solar = s[["Guichon_BelowSolar [m3/s]"]]), t)
d1 <- xts(as.numeric(q1$Solar) - as.numeric(q1$Baseline), t); colnames(d1) <- "Solar - baseline"
q2 <- xts(cbind(Baseline = b[["Guichon_08LG041 [m3/s]"]], Solar = s[["Guichon_08LG041 [m3/s]"]]), t)

grp <- "solar"
base_opts <- function(g, ylab) g |>
  dyAxis("y", label = ylab) |>
  dyOptions(strokeWidth = 1.5, drawGrid = TRUE, gridLineColor = "#ecebe8") |>
  dyHighlight(highlightSeriesOpts = list(strokeWidth = 2.5), hideOnMouseOut = TRUE) |>
  dyLegend(show = "always", width = 420)

g1 <- dygraph(q1, main = "Guichon Creek below the solar site (subbasin 1 outlet)", group = grp,
              height = 320, width = "100%") |>
  dySeries("Baseline", color = blue) |> dySeries("Solar", color = orange) |>
  base_opts("Flow (m³/s)")
g2 <- dygraph(d1, main = "Subbasin 1 outlet: solar − baseline", group = grp, height = 220, width = "100%") |>
  dySeries("Solar - baseline", color = orange, fillGraph = TRUE) |>
  dyLimit(0, color = "#52514e") |>
  base_opts("Change (m³/s)")
g3 <- dygraph(q2, main = "Mamit Lake outlet (subbasin 2, includes solar HRU 6)", group = grp,
              height = 280, width = "100%") |>
  dySeries("Baseline", color = blue) |> dySeries("Solar", color = orange) |>
  base_opts("Flow (m³/s)") |>
  dyRangeSelector(height = 30)

page <- tagList(
  tags$head(tags$title("Baseline vs solar"),
            tags$style("body{font-family:Segoe UI,Arial,sans-serif;margin:16px 24px;color:#0b0b0b;background:#fff}
                        p{color:#52514e;font-size:13px;max-width:1000px} .dygraph-title{font-size:15px}")),
  tags$h2("Baseline vs solar (site fully impervious)"),
  tags$p(paste("Raven HBV-EC, Daymet forcing, 2026-11-12 calibration. Solar run: solar site HRUs 1 and 6 changed",
               "from 20% forest to fully impervious (IMPERM 1.0), a worst-case screening assumption.",
               "Charts are linked: drag to zoom on any chart, double-click to reset, or use the range selector",
               "at the bottom. WY1981 (Oct 1980 - Sep 1981) is model spin-up.")),
  g1, g2, g3)
dir.create("output/plots", showWarnings = FALSE)
out <- file.path(getwd(), "output/plots/solar_vs_baseline_dygraph.html")
save_html(page, out, libdir = "lib")
cat("wrote", out, "\n")
