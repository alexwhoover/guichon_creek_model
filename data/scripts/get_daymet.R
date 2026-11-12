# Download Daymet V4 R1 daily weather (1 km grid) at sample points covering every model HRU.
#
# Daymet's NetCDF server (THREDDS) now requires a NASA Earthdata login, so this uses the
# open single-pixel API instead (https://daymet.ornl.gov/single-pixel/), one request per point.
# Points sit on a regular 2 km grid (BC Albers) clipped to each HRU, so each point stands for
# an equal share of its HRU's area; averaging the points in an HRU gives the area-weighted
# HRU mean, the same as Raven's :GriddedForcing + :GridWeights would compute.
# HRUs with fewer than MIN_PTS grid points (the solar HRUs, HRU 12) get a 250 m grid instead.
#
# HRU polygons are rebuilt as in analysis/map_subbasins_hrus.R: hrus_final.shp, with bands 2-5
# of subbasin 1 cut by catchment_08LG056.shp into HRUs 2-5 (below) and 12-15 (above).
#
# Outputs:
#   data/processed/daymet_points.csv     point_id, HRU_ID, lon, lat
#   data/raw/daymet/pt_NNNN.csv          raw API response per point (git-ignored, ~0.4 MB each)
#
# Usage (from Raven/HBVEC_Model):  Rscript data/scripts/get_daymet.R
# Next step: Rscript data/scripts/write_daymet_rvt.R

Sys.setenv(TZ = "America/Vancouver")
suppressMessages(library(sf))
sf_use_s2(FALSE)

START   <- "1980-01-01"   # Daymet starts 1980; model starts 1980-10-01 (WY1981 spin-up)
END     <- "2024-12-31"   # flow records (08LG041, 08LG056) end 2024-12-31
SPACING <- 2000      # m, main sampling grid
FINE    <- 250       # m, grid for small HRUs
MIN_PTS <- 5
RAW     <- "data/raw/daymet"
dir.create(RAW, showWarnings = FALSE, recursive = TRUE)

# ---- HRU polygons as modelled -----------------------------------------------
crs  <- 3005
hru0 <- st_transform(st_make_valid(st_read("data/delineation_copy/hrus_final.shp", quiet = TRUE)), crs)
c56  <- st_geometry(st_transform(st_read("data/delineation_copy/catchment_08LG056.shp", quiet = TRUE), crs))
suppressWarnings({
  above <- st_intersection(hru0[hru0$subbasin == 1 & hru0$BAND > 0, ], c56)
  below <- st_difference(hru0[hru0$subbasin == 1 & hru0$BAND > 0, ], c56)
})
above <- above[order(above$HRU_ID), ]
above$HRU_ID <- 11 + seq_len(nrow(above))
keep <- c("HRU_ID")
hru  <- rbind(hru0[!(hru0$subbasin == 1 & hru0$BAND > 0), keep], below[, keep], above[, keep])
hru  <- st_collection_extract(hru, "POLYGON")
hru  <- aggregate(hru[, "geometry"], by = list(HRU_ID = hru$HRU_ID), FUN = function(x) x[1], do_union = TRUE)
stopifnot(nrow(hru) == 15)

# ---- sample points -----------------------------------------------------------
grid_pts <- function(poly, d) {
  g <- st_make_grid(poly, cellsize = d, what = "centers")
  g[lengths(st_intersects(g, poly)) > 0]
}
pts <- do.call(rbind, lapply(seq_len(nrow(hru)), function(i) {
  g <- grid_pts(hru[i, ], SPACING)
  if (length(g) < MIN_PTS) g <- grid_pts(hru[i, ], FINE)
  ll <- st_coordinates(st_transform(g, 4326))
  data.frame(HRU_ID = hru$HRU_ID[i], lon = round(ll[, 1], 5), lat = round(ll[, 2], 5))
}))
pts <- pts[order(pts$HRU_ID), ]
pts$point_id <- seq_len(nrow(pts))
pts <- pts[, c("point_id", "HRU_ID", "lon", "lat")]
write.csv(pts, "data/processed/daymet_points.csv", row.names = FALSE)
cat("Sample points per HRU:\n"); print(table(pts$HRU_ID))

# ---- download ----------------------------------------------------------------
url <- "https://daymet.ornl.gov/single-pixel/api/data?lat=%.5f&lon=%.5f&vars=tmax,tmin,prcp&start=%s&end=%s"
# A file is complete if it starts in START's year and ends in END's year; anything else
# (missing, partial, or from an earlier period) is downloaded again.
complete <- function(f) {
  if (!file.exists(f) || file.size(f) < 100000) return(FALSE)
  ln <- readLines(f)
  first <- ln[grep("^year,", ln) + 1]
  startsWith(first, paste0(substr(START, 1, 4), ",")) &&
    startsWith(ln[length(ln)], paste0(substr(END, 1, 4), ","))
}
for (i in seq_len(nrow(pts))) {
  f <- file.path(RAW, sprintf("pt_%04d.csv", pts$point_id[i]))
  if (complete(f)) next
  for (try in 1:3) {
    ok <- tryCatch({
      download.file(sprintf(url, pts$lat[i], pts$lon[i], START, END), f, quiet = TRUE, mode = "wb")
      complete(f)
    }, error = function(e) FALSE)
    if (ok) break
    Sys.sleep(5 * try)
  }
  if (!ok) stop("Download failed for point ", pts$point_id[i])
  if (i %% 25 == 0) cat("  downloaded", i, "of", nrow(pts), "\n")
}
cat("Done:", nrow(pts), "points in", RAW, "\n")
