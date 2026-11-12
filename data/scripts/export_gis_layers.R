# Write the model's subbasins and HRUs (as in hbvec.rvh, including the split of subbasin 1
# at WSC 08LG056) to a file geodatabase as two polygon feature classes:
#   hrus_v3_08LG056        HRUs in hbvec.rvh (15 until 2026-11-12; 9 after subbasin 2 was removed)
#   subbasins_v3_08LG056   subbasins in hbvec.rvh (3, now 2)
# Only HRUs and subbasins present in hbvec.rvh are written. NOTE: re-running this replaces the
# current geodatabase layers (which still show subbasin 2, and had clipping slivers removed by
# hand on 2026-11-12); the slivers along the 08LG056 boundary come back if this is re-run.
#
# Usage (from Raven/HBVEC_Model):
#   Rscript data/scripts/export_gis_layers.R [path to .gdb]
# Default .gdb: ../../ArcGIS/mahatemEEwuh/mahatemEEwuh.gdb
# CLOSE ArcGIS Pro first if the geodatabase is open in it. Existing feature classes with
# these two names are replaced; nothing else in the geodatabase is touched.
#
# Geometry: data/delineation_copy/hrus_final.shp, with bands 2-5 of subbasin 1 cut by
# data/delineation_copy/catchment_08LG056.shp. Projection: BC Albers (EPSG:3005).
# Model attributes are read from hbvec.rvh; the GIS_ and ELEV_MIN/MAX fields are measured here.

suppressMessages({library(sf); library(terra)})
sf_use_s2(FALSE)

gdb <- commandArgs(TRUE)[1]
if (is.na(gdb)) gdb <- "../../ArcGIS/mahatemEEwuh/mahatemEEwuh.gdb"
crs <- 3005

# ---- HRU polygons as modelled ------------------------------------------------
hru0 <- st_transform(st_make_valid(st_read("data/delineation_copy/hrus_final.shp", quiet = TRUE)), crs)
c56  <- st_geometry(st_transform(st_read("data/delineation_copy/catchment_08LG056.shp", quiet = TRUE), crs))
cut  <- hru0$subbasin == 1 & hru0$BAND > 0
suppressWarnings({
  above <- st_intersection(hru0[cut, ], c56)
  below <- st_difference(hru0[cut, ], c56)
})
above <- above[order(above$HRU_ID), ]
above$SPLIT_FROM <- above$HRU_ID; above$HRU_ID <- 11L + seq_len(nrow(above))
below$SPLIT_FROM <- below$HRU_ID
rest <- hru0[!cut, ]; rest$SPLIT_FROM <- NA_integer_
keep <- c("HRU_ID", "SPLIT_FROM")
hru  <- rbind(rest[, keep], below[, keep], above[, keep])
hru  <- st_cast(st_collection_extract(hru, "POLYGON"), "MULTIPOLYGON")
hru  <- hru[order(hru$HRU_ID), ]
stopifnot(!anyDuplicated(hru$HRU_ID))

# ---- model attributes from hbvec.rvh -----------------------------------------
rvh  <- readLines("hbvec.rvh")
rows <- grep("^\\s+\\d+,\\s+[0-9.]+,\\s+[0-9.]+,\\s+[0-9.]+,\\s+-", rvh, value = TRUE)
f    <- lapply(strsplit(sub("#.*", "", rows), ","), trimws)
g    <- function(i) sapply(f, `[`, i)
tab  <- data.frame(HRU_ID = as.integer(g(1)), AREA_KM2 = as.numeric(g(2)), ELEV_MEAN = as.numeric(g(3)),
                   LATITUDE = as.numeric(g(4)), LONGITUDE = as.numeric(g(5)), SUBBASIN_ID = as.integer(g(6)),
                   LAND_USE_CLASS = g(7), VEG_CLASS = g(8), SOIL_PROFILE = g(9),
                   SLOPE = as.numeric(g(12)), ASPECT = as.numeric(g(13)),
                   HRU_DESC = trimws(sub(".*#", "", rows)))
hru <- hru[hru$HRU_ID %in% tab$HRU_ID, ]          # HRUs removed from the model are not exported
stopifnot(setequal(tab$HRU_ID, hru$HRU_ID))

sb_rows <- grep("^\\s+\\d+,\\s+Guichon_", rvh, value = TRUE)
s  <- lapply(strsplit(sub("#.*", "", sb_rows), ","), trimws)
sbt <- data.frame(SUBBASIN_ID = as.integer(sapply(s, `[`, 1)), SUBBASIN_NAME = sapply(s, `[`, 2),
                  DOWNSTREAM_ID = as.integer(sapply(s, `[`, 3)), REACH_LENGTH_KM = as.numeric(sapply(s, `[`, 4)),
                  GAUGED = as.integer(sapply(s, `[`, 5)))
tc_rows <- grep("^\\s+\\d+,\\s+[0-9.]+,\\s+[0-9.]+\\s*(#.*)?$", rvh, value = TRUE)
tc <- lapply(strsplit(sub("#.*", "", tc_rows), ","), trimws)
tct <- data.frame(SUBBASIN_ID = as.integer(sapply(tc, `[`, 1)), TIME_CONC_D = as.numeric(sapply(tc, `[`, 2)),
                  TIME_TO_PEAK_D = as.numeric(sapply(tc, `[`, 3)))
sbt <- merge(sbt, tct, by = "SUBBASIN_ID")
stopifnot(nrow(sbt) >= 1, all(tab$SUBBASIN_ID %in% sbt$SUBBASIN_ID))

band <- function(d) ifelse(grepl("solar", d), "Solar site",
                    ifelse(grepl("<1000", d), "< 1000 m", ifelse(grepl("1000-1200", d), "1000-1200 m",
                    ifelse(grepl("1200-1400", d), "1200-1400 m", ifelse(grepl("1400-1600", d), "1400-1600 m",
                    "1600 m and above")))))
tab$ELEV_BAND <- band(tab$HRU_DESC)
tab$SUBBASIN_NAME <- sbt$SUBBASIN_NAME[match(tab$SUBBASIN_ID, sbt$SUBBASIN_ID)]
tab$SOLAR_SITE <- as.integer(tab$HRU_ID %in% c(1, 6))   # HRU 6 is no longer in the model
tab$PCT_OF_SUBBASIN <- round(100 * tab$AREA_KM2 / ave(tab$AREA_KM2, tab$SUBBASIN_ID, FUN = sum), 2)

# ---- measured in GIS -----------------------------------------------------------
dem <- rast("data/delineation_copy/MRDEM30_dtm.tif")
z   <- terra::extract(dem, vect(st_transform(hru, crs(dem))), fun = function(x) c(min(x, na.rm = TRUE), max(x, na.rm = TRUE)))
hru$GIS_AREA_KM2 <- round(as.numeric(st_area(hru)) / 1e6, 3)
hru$ELEV_MIN <- round(z[, 2], 1); hru$ELEV_MAX <- round(z[, 3], 1)

hru <- merge(hru, tab, by = "HRU_ID")
hru <- hru[order(hru$HRU_ID), c("HRU_ID", "HRU_DESC", "SUBBASIN_ID", "SUBBASIN_NAME", "ELEV_BAND", "SOLAR_SITE",
                                "LAND_USE_CLASS", "VEG_CLASS", "SOIL_PROFILE", "AREA_KM2", "PCT_OF_SUBBASIN",
                                "ELEV_MEAN", "ELEV_MIN", "ELEV_MAX", "LATITUDE", "LONGITUDE", "SLOPE", "ASPECT",
                                "SPLIT_FROM", "GIS_AREA_KM2")]

# ---- subbasins -----------------------------------------------------------------
sb <- aggregate(hru[, "GIS_AREA_KM2"], by = list(SUBBASIN_ID = hru$SUBBASIN_ID), FUN = sum, do_union = TRUE)
sb <- st_cast(sb, "MULTIPOLYGON")
h  <- st_drop_geometry(hru)
agg <- do.call(rbind, lapply(split(h, h$SUBBASIN_ID), function(x) data.frame(
  SUBBASIN_ID = x$SUBBASIN_ID[1], AREA_KM2 = round(sum(x$AREA_KM2), 3),
  ELEV_MEAN = round(weighted.mean(x$ELEV_MEAN, x$AREA_KM2), 1),
  ELEV_MIN = min(x$ELEV_MIN), ELEV_MAX = max(x$ELEV_MAX), N_HRUS = nrow(x),
  HRU_IDS = paste(x$HRU_ID, collapse = ","),
  SOLAR_AREA_KM2 = round(sum(x$AREA_KM2[x$SOLAR_SITE == 1]), 3))))
sbt <- merge(sbt, agg, by = "SUBBASIN_ID")
upstream <- function(id) { k <- sbt$SUBBASIN_ID[sbt$DOWNSTREAM_ID %in% id]; if (length(k)) c(id, upstream(k)) else id }
sbt$DRAINAGE_AREA_KM2 <- sapply(sbt$SUBBASIN_ID, function(i) round(sum(sbt$AREA_KM2[sbt$SUBBASIN_ID %in% upstream(i)]), 3))
sbt$WSC_GAUGE <- c("1" = NA, "2" = "08LG041", "3" = "08LG056")[as.character(sbt$SUBBASIN_ID)]
sbt$ROLE <- c("1" = "Main output: Guichon Creek below the solar site",
              "2" = "Regulated gauge at Mamit Lake outlet; uncalibrated check",
              "3" = "Natural-flow gauge; calibration target")[as.character(sbt$SUBBASIN_ID)]
sb <- merge(sb, sbt, by = "SUBBASIN_ID")
sb <- sb[order(sb$SUBBASIN_ID), c("SUBBASIN_ID", "SUBBASIN_NAME", "DOWNSTREAM_ID", "WSC_GAUGE", "GAUGED", "ROLE",
                                  "AREA_KM2", "DRAINAGE_AREA_KM2", "ELEV_MEAN", "ELEV_MIN", "ELEV_MAX",
                                  "N_HRUS", "HRU_IDS", "SOLAR_AREA_KM2", "REACH_LENGTH_KM", "TIME_CONC_D",
                                  "TIME_TO_PEAK_D", "GIS_AREA_KM2")]

# ---- write ---------------------------------------------------------------------
wr <- function(x, layer) st_write(x, gdb, layer = layer, driver = "OpenFileGDB", delete_layer = TRUE, quiet = TRUE,
                                  layer_options = "TARGET_ARCGIS_VERSION=ALL")
wr(hru, "hrus_v3_08LG056")
wr(sb,  "subbasins_v3_08LG056")
cat("wrote hrus_v3_08LG056 (", nrow(hru), ") and subbasins_v3_08LG056 (", nrow(sb), ") to ", gdb, "\n", sep = "")
print(st_drop_geometry(sb)[, c("SUBBASIN_ID", "SUBBASIN_NAME", "AREA_KM2", "DRAINAGE_AREA_KM2", "ELEV_MEAN", "N_HRUS", "GIS_AREA_KM2")], row.names = FALSE)
