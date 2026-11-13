# Carve the catchment of WSC 08LG056 (Guichon Creek above Tunkwa Lake Diversion)
# out of subbasin 1, so the model has an outlet at that gauge (subbasin 3).
#
# 08LG056 is a natural-flow reference station (RHBN) in the headwaters of subbasin 1.
# Its catchment is taken from the Canadian Lake-River Hydrofabric (CLRH) product that
# was downloaded for 08LG041: all CLRH catchments that drain to the one tagged
# Obs_NM = "08LG056".
#
# Each subbasin-1 elevation-band HRU (2-5) is split into
#   - the part above the gauge  -> new HRU in subbasin 3 (IDs 12-15)
#   - the remainder             -> keeps its HRU ID in subbasin 1
# Areas are scaled so that part + remainder equals the HRU area already in hbvec.rvh.
# The solar HRUs (1, 6) are not touched; the script stops if the catchment overlaps them.
#
# Inputs:
#   ../../ArcGIS/mahatemEEwuh/Inputs/CLRH_08LG041/finalcat_info_v1-1.shp
#   data/gis/hrus_final.shp, MRDEM30_dtm.tif
#   data/processed/hru_attributes.csv   (areas used in hbvec.rvh)
# Outputs:
#   data/processed/hru_split_08LG056.csv        HRU rows to paste into hbvec.rvh
#   data/gis/catchment_08LG056.shp  catchment polygon (for checking in GIS)
#
# Usage (from Raven/HBVEC_Model):  Rscript data/scripts/split_08LG056_subbasin.R

suppressMessages({library(sf); library(terra)})
sf_use_s2(FALSE)

clrh <- "../../ArcGIS/mahatemEEwuh/Inputs/CLRH_08LG041/finalcat_info_v1-1.shp"
fc   <- st_read(clrh, quiet = TRUE)
d    <- st_drop_geometry(fc)

# ---- catchment above the gauge ---------------------------------------------
upstream <- function(id) {
  k <- d$SubId[d$DowSubId %in% id]
  if (length(k)) c(id, upstream(k)) else id
}
gauge_sub <- d$SubId[which(d$Obs_NM == "08LG056")]
ids <- unique(upstream(gauge_sub))

hru <- st_make_valid(st_read("data/gis/hrus_final.shp", quiet = TRUE))
cat56 <- st_union(st_make_valid(fc[fc$SubId %in% ids, ])) |> st_transform(st_crs(hru))
# hrus_final is in a conformal projection (areas ~1% small), so measure area in BC Albers
km2_56 <- as.numeric(st_area(st_transform(cat56, 3005))) / 1e6
cat(sprintf("CLRH catchments above 08LG056: %d, area %.2f km2 (WSC gross area 76.06 km2)\n",
            length(ids), km2_56))

# Main-stem length above the gauge: follow the largest upstream drainage area
len <- 0; cur <- gauge_sub
repeat {
  len <- len + d$RivLength[d$SubId == cur]
  up  <- d[d$DowSubId == cur, ]
  if (!nrow(up)) break
  cur <- up$SubId[which.max(up$DrainArea)]
}
cat(sprintf("Main-stem length above the gauge: %.1f km\n", len / 1000))

# ---- split the HRUs ---------------------------------------------------------
suppressWarnings({
  above <- st_intersection(hru, cat56)
  below <- st_difference(hru[hru$HRU_ID %in% above$HRU_ID, ], cat56)
})
if (any(above$HRU_ID %in% c(1, 6))) stop("Catchment overlaps a solar HRU - check by hand.")
if (any(above$subbasin != 1))       stop("Catchment extends outside subbasin 1.")

dem  <- rast("data/gis/MRDEM30_dtm.tif")
attr <- read.csv("data/processed/hru_attributes.csv")

describe <- function(x) {
  x <- x[order(x$HRU_ID), ]
  ll <- st_coordinates(st_transform(suppressWarnings(st_centroid(st_geometry(x))), 4326))
  data.frame(HRU_ID = x$HRU_ID, BAND = x$BAND,
             poly_km2 = as.numeric(st_area(x)) / 1e6,
             ELEV = terra::extract(dem, vect(x), fun = mean, na.rm = TRUE)[, 2],
             LAT = ll[, "Y"], LON = ll[, "X"])
}
a <- describe(above); b <- describe(below)
frac   <- a$poly_km2 / (a$poly_km2 + b$poly_km2)          # share of each HRU above the gauge
rvh_km2 <- attr$AREA_km2[match(a$HRU_ID, attr$HRU_ID)]    # areas currently in hbvec.rvh

band_name <- c("2" = "1000-1200", "3" = "1200-1400", "4" = "1400-1600", "5" = "1600+")
out <- rbind(
  data.frame(HRU_ID = a$HRU_ID, subbasin = 1, part = "remainder below 08LG056",
             band = band_name[as.character(a$BAND)], AREA_km2 = rvh_km2 * (1 - frac),
             ELEV_mean = b$ELEV, LAT = b$LAT, LON = b$LON),
  data.frame(HRU_ID = 11 + seq_len(nrow(a)), subbasin = 3, part = "above 08LG056",
             band = band_name[as.character(a$BAND)], AREA_km2 = rvh_km2 * frac,
             ELEV_mean = a$ELEV, LAT = a$LAT, LON = a$LON))
out$split_from <- rep(a$HRU_ID, 2)
out$AREA_km2 <- round(out$AREA_km2, 3); out$ELEV_mean <- round(out$ELEV_mean, 1)
out$LAT <- round(out$LAT, 4);           out$LON <- round(out$LON, 4)

write.csv(out, "data/processed/hru_split_08LG056.csv", row.names = FALSE)
st_write(st_sf(station = "08LG056", area_km2 = km2_56, geometry = cat56),
         "data/gis/catchment_08LG056.shp", delete_layer = TRUE, quiet = TRUE)

print(out, row.names = FALSE)
cat(sprintf("Subbasin 3 area: %.3f km2;  subbasin 1 bands 2-5 before %.3f, after %.3f + %.3f km2\n",
            sum(out$AREA_km2[out$subbasin == 3]), sum(rvh_km2),
            sum(out$AREA_km2[out$subbasin == 1]), sum(out$AREA_km2[out$subbasin == 3])))
