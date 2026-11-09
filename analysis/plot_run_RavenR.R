# Plot the outputs of one Raven run with RavenR: interactive dygraph hydrographs.
#
# Usage (from Raven/HBVEC_Model):
#   Rscript analysis/plot_run_RavenR.R            # run name defaults to "baseline"
#   Rscript analysis/plot_run_RavenR.R solar
# Writes output/plots/<run>_dygraph_<i>.html (one per subbasin; needs output/plots/lib)

Sys.setenv(TZ = "America/Vancouver")
suppressPackageStartupMessages({ library(RavenR); library(htmlwidgets); library(dygraphs) })

run  <- if (length(commandArgs(TRUE))) commandArgs(TRUE)[1] else "baseline"
outd <- "output"
plt  <- file.path(outd, "plots"); dir.create(plt, showWarnings = FALSE)
f    <- function(x) file.path(outd, paste0(run, "_", x))

# ---- read --------------------------------------------------------------------
hy <- rvn_hyd_read(f("Hydrographs.csv"))

# ---- interactive hydrographs (zoomable HTML, one per subbasin) ---------------
# rvn_hyd_dygraph's automatic basin detection breaks on the reservoir-inflow
# column ("Guichon_08LG041_resinflow" -> bogus basin "Guichon_08LG041inflow"),
# and its `basins == ""` test fails for vectors in R >= 4.2. So pass the basin
# names explicitly, one at a time (sim columns = all except precip/_obs/_resinflow).
cols   <- colnames(hy$hyd)
basins <- cols[cols != "precip" & !grepl("_obs$|_resinflow$", cols)]
for (i in seq_along(basins)) {
  dg   <- rvn_hyd_dygraph(hy, basins = basins[i])[[1]]
  html <- file.path(getwd(), plt, paste0(run, "_dygraph_", i, ".html"))
  saveWidget(dg, html, selfcontained = FALSE, libdir = "lib")
  cat("  wrote", html, "\n")
}

# ---- fit statistics ----------------------------------------------------------
print(read.csv(f("Diagnostics.csv"))[, 1:6])
