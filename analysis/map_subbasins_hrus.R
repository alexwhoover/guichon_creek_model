# Map of the model's subbasins and HRUs, including the split of subbasin 1 at WSC 08LG056.
#
# Usage (from Raven/HBVEC_Model):  Rscript analysis/map_subbasins_hrus.R
# Writes analysis/Guichon_subbasins_HRUs_map.pdf  (page 1 map, page 2 HRU table)
#
# HRU polygons: data/delineation_copy/hrus_final.shp, with bands 2-5 of subbasin 1 cut by
# data/delineation_copy/catchment_08LG056.shp (from data/scripts/split_08LG056_subbasin.R).
# Areas and elevations in the table are read from hbvec.rvh, so they are what Raven uses.

suppressMessages({library(sf); library(ggplot2); library(ggrepel); library(grid)})
sf_use_s2(FALSE)

crs  <- 3005                                   # BC Albers (equal area)
hru0 <- st_transform(st_make_valid(st_read("data/delineation_copy/hrus_final.shp", quiet = TRUE)), crs)
c56  <- st_geometry(st_transform(st_read("data/delineation_copy/catchment_08LG056.shp", quiet = TRUE), crs))

# ---- HRU polygons as modelled ------------------------------------------------
suppressWarnings({
  above <- st_intersection(hru0[hru0$subbasin == 1 & hru0$BAND > 0, ], c56)
  below <- st_difference(hru0[hru0$subbasin == 1 & hru0$BAND > 0, ], c56)
})
above <- above[order(above$HRU_ID), ]
above$HRU_ID <- 11 + seq_len(nrow(above)); above$subbasin <- 3
keep <- c("HRU_ID", "subbasin", "BAND")
hru  <- rbind(hru0[!(hru0$subbasin == 1 & hru0$BAND > 0), keep], below[, keep], above[, keep])
hru  <- st_collection_extract(hru, "POLYGON")
hru  <- aggregate(hru[, "geometry"], by = list(HRU_ID = hru$HRU_ID), FUN = function(x) x[1], do_union = TRUE)

# ---- attributes from hbvec.rvh -----------------------------------------------
rvh  <- readLines("hbvec.rvh")
rows <- grep("^\\s+\\d+,\\s+[0-9.]+,\\s+[0-9.]+,\\s+[0-9.]+,\\s+-", rvh, value = TRUE)
f    <- strsplit(sub("#.*", "", rows), ",")
tab  <- data.frame(HRU_ID = as.integer(sapply(f, `[`, 1)), area = as.numeric(sapply(f, `[`, 2)),
                   elev = as.numeric(sapply(f, `[`, 3)), sb = as.integer(sapply(f, `[`, 6)),
                   lu = trimws(sapply(f, `[`, 7)), note = trimws(sub(".*#", "", rows)))
hru  <- merge(hru, tab, by = "HRU_ID")
stopifnot(nrow(hru) == nrow(tab))

bands <- c("< 1000 m", "1000–1200 m", "1200–1400 m", "1400–1600 m", "1600 m and above")
band_of <- function(note) ifelse(grepl("solar", note), NA,
                          ifelse(grepl("<1000", note), 1, ifelse(grepl("1000-1200", note), 2,
                          ifelse(grepl("1200-1400", note), 3, ifelse(grepl("1400-1600", note), 4, 5)))))
hru$band  <- band_of(hru$note)
hru$class <- factor(ifelse(is.na(hru$band), "Solar site", bands[hru$band]), levels = c(bands, "Solar site"))

sb_name <- c("1" = "Subbasin 1\nGuichon_BelowSolar", "2" = "Subbasin 2\nGuichon_08LG041",
             "3" = "Subbasin 3\nGuichon_08LG056")
sb <- aggregate(hru[, "geometry"], by = list(sb = hru$sb), FUN = function(x) x[1], do_union = TRUE)
sb$area  <- tapply(hru$area, hru$sb, sum)[as.character(sb$sb)]
sb$label <- sprintf("%s\n%.1f km²", sb_name[as.character(sb$sb)], sb$area)

# ---- points ------------------------------------------------------------------
pts <- st_transform(st_as_sf(data.frame(
  label = c("WSC 08LG056\n(natural flow; calibration)", "WSC 08LG041\n(regulated; check only)"),
  lon = c(-120.91086, -120.80994), lat = c(50.60783, 50.36111)), coords = c("lon", "lat"), crs = 4326), crs)
# Subbasin 1 outlet: where subbasins 1 and 2 meet, nearest the solar HRUs
edge   <- st_intersection(st_boundary(sb[sb$sb == 1, ]), st_boundary(sb[sb$sb == 2, ]))
solar  <- st_union(hru[hru$HRU_ID %in% c(1, 6), ])
outlet <- st_nearest_points(solar, st_union(edge))
outlet <- st_sf(label = "Subbasin 1 outlet\n(below solar site)",
                geometry = st_cast(outlet, "POINT")[2])
pts <- rbind(pts, st_transform(outlet, crs))
pxy <- cbind(st_drop_geometry(pts), st_coordinates(pts))

# HRU ID labels: one per HRU, on its largest piece
parts <- st_cast(st_cast(hru[, c("HRU_ID", "class")], "MULTIPOLYGON"), "POLYGON", warn = FALSE)
parts$a <- as.numeric(st_area(parts))
big  <- do.call(rbind, lapply(split(parts, parts$HRU_ID), function(x) x[which.max(x$a), ]))
# label point = centre of the largest circle that fits inside the piece (never falls outside it)
inner <- function(g) t(sapply(seq_len(nrow(g)), function(i) {
  parts <- st_cast(st_cast(st_geometry(g)[i], "MULTIPOLYGON"), "POLYGON")
  big1  <- parts[which.max(st_area(parts))]
  st_coordinates(st_centroid(st_inscribed_circle(big1, dTolerance = 30)))[1, c("X", "Y")]
}))
lab  <- cbind(st_drop_geometry(big), inner(big))
small <- lab$HRU_ID %in% c(1, 6, 12)             # too small to hold a label: label beside, with a leader
sbl  <- cbind(st_drop_geometry(sb), inner(sb))

# ---- colours -----------------------------------------------------------------
# Elevation is ordered, so one hue light -> dark; the solar site is a different kind of
# thing, so it gets a contrasting hue. HRU numbers repeat the identity without colour.
fill <- c(setNames(c("#86b6ef", "#5598e7", "#2a78d6", "#1c5cab", "#0d366b"), bands), "Solar site" = "#eb6834")
ink  <- "#0b0b0b"; ink2 <- "#52514e"; surface <- "#fcfcfb"

bb <- st_bbox(hru); pad <- 2500
# Subbasin labels sit in the empty corners of the page, with a leader to the subbasin
fx <- function(f) bb["xmin"] + f * (bb["xmax"] - bb["xmin"])
fy <- function(f) bb["ymin"] + f * (bb["ymax"] - bb["ymin"])
sbl$lx <- fx(c(0.09, 0.90, 0.40))[sbl$sb]; sbl$ly <- fy(c(0.30, 0.90, 0.95))[sbl$sb]
# scale bar: 10 km, bottom left
sx <- bb["xmin"] + 1000; sy <- bb["ymin"] + 500
p <- ggplot() +
  geom_sf(data = hru, aes(fill = class), colour = surface, linewidth = 0.15) +
  geom_sf(data = sb, fill = NA, colour = ink, linewidth = 0.9) +
  geom_label(data = lab[!small, ], aes(X, Y, label = HRU_ID), size = 3, fontface = "bold", colour = ink,
             fill = alpha(surface, 0.88), linewidth = 0, label.padding = unit(0.14, "lines")) +
  geom_label_repel(data = lab[small, ], aes(X, Y, label = HRU_ID), size = 3, fontface = "bold", colour = ink,
                   fill = alpha(surface, 0.95), label.size = 0.2, label.padding = unit(0.14, "lines"),
                   nudge_x = c(2500, 4500, -3500), nudge_y = c(6000, 1500, 3500),
                   min.segment.length = 0, segment.colour = ink, segment.size = 0.4, seed = 1) +
  geom_point(data = pxy, aes(X, Y), shape = 21, size = 3.6, fill = ink, colour = surface, stroke = 1.1) +
  geom_label_repel(data = pxy, aes(X, Y, label = label), size = 2.9, colour = ink, lineheight = 0.95,
                   fill = surface, label.size = 0.2, label.padding = unit(0.25, "lines"),
                   nudge_x = c(-10000, 11000, 4000), nudge_y = c(7500, -2500, -9500),
                   segment.colour = ink, segment.size = 0.4, min.segment.length = 0, seed = 2) +
  geom_segment(data = sbl, aes(x = lx, y = ly, xend = X, yend = Y), colour = ink, linewidth = 0.4) +
  geom_point(data = sbl, aes(X, Y), shape = 16, size = 1.2, colour = ink) +
  geom_label(data = sbl, aes(lx, ly, label = label), size = 3.1, fontface = "bold", colour = ink,
             fill = surface, linewidth = 0.3, lineheight = 0.95, label.padding = unit(0.3, "lines")) +
  annotate("segment", x = sx, xend = sx + 10000, y = sy, yend = sy, colour = ink, linewidth = 1) +
  annotate("text", x = sx + 5000, y = sy + 900, label = "10 km", size = 3, colour = ink) +
  annotate("text", x = bb["xmax"], y = bb["ymax"] + 1500, label = "N ↑", size = 4, fontface = "bold",
           colour = ink, hjust = 1) +
  scale_fill_manual(values = fill, name = "HRU type", drop = FALSE) +
  coord_sf(datum = NA, xlim = c(bb["xmin"] - pad, bb["xmax"] + pad),
           ylim = c(bb["ymin"] - pad, bb["ymax"] + 2 * pad), expand = FALSE) +
  labs(title = "Guichon Creek model: subbasins and HRUs",
       subtitle = paste0("CALIBRATION branch. Subbasin 3 is the catchment of WSC 08LG056, split out of subbasin 1.\n",
                         "Numbers are HRU IDs. Each HRU is one elevation band within one subbasin; HRUs 1 and 6 are the solar site."),
       caption = paste0("Sources: hbvec.rvh; data/delineation_copy (HRUs, 08LG056 catchment from the CLRH hydrofabric). ",
                        "Projection: BC Albers (EPSG:3005).   ", format(Sys.Date()))) +
  theme_void(base_size = 10) +
  theme(plot.background = element_rect(fill = surface, colour = NA),
        plot.title = element_text(face = "bold", size = 15, colour = ink, margin = margin(b = 4)),
        plot.subtitle = element_text(size = 9.5, colour = ink2, lineheight = 1.1, margin = margin(b = 6)),
        plot.caption = element_text(size = 7.5, colour = ink2, hjust = 0),
        legend.position = "right", legend.title = element_text(face = "bold", size = 9.5, colour = ink),
        legend.text = element_text(size = 9, colour = ink), legend.key.size = unit(0.5, "cm"),
        plot.margin = margin(14, 14, 10, 14))

# ---- page 2: table -------------------------------------------------------------
t2 <- st_drop_geometry(hru)[order(hru$sb, hru$HRU_ID), ]
t2 <- data.frame(Subbasin = t2$sb, HRU = t2$HRU_ID, Type = as.character(t2$class),
                 `Land use class` = t2$lu, `Area (km²)` = sprintf("%.3f", t2$area),
                 `Mean elevation (m)` = sprintf("%.1f", t2$elev), check.names = FALSE)

draw_table <- function(d, title, note) {
  grid.newpage(); grid.rect(gp = gpar(fill = surface, col = NA))
  grid.text(title, x = 0.06, y = 0.93, just = "left", gp = gpar(fontsize = 15, fontface = "bold", col = ink))
  x <- c(0.06, 0.17, 0.26, 0.47, 0.72, 0.92); just <- c("left", "left", "left", "left", "right", "right")
  y0 <- 0.86; dy <- 0.036
  for (j in seq_along(d)) grid.text(names(d)[j], x[j], y0, just = just[j],
                                    gp = gpar(fontsize = 9.5, fontface = "bold", col = ink))
  grid.lines(c(0.06, 0.92), rep(y0 - dy * 0.45, 2), gp = gpar(col = "#c3c2b7"))
  y <- y0
  for (i in seq_len(nrow(d))) {
    y <- y - dy - if (i > 1 && d$Subbasin[i] != d$Subbasin[i - 1]) dy * 0.5 else 0
    grid.rect(0.045, y, width = 0.008, height = dy * 0.6, just = "left",
              gp = gpar(fill = fill[d$Type[i]], col = NA))
    for (j in seq_along(d)) grid.text(d[i, j], x[j], y, just = just[j], gp = gpar(fontsize = 9.5, col = ink))
  }
  tot <- tapply(as.numeric(d$`Area (km²)`), d$Subbasin, sum)
  y <- y - dy * 1.6
  grid.text(sprintf("Subbasin areas: 1 = %.1f km², 2 = %.1f km², 3 = %.1f km². Total %.1f km².",
                    tot["1"], tot["2"], tot["3"], sum(tot)), 0.06, y, just = "left",
            gp = gpar(fontsize = 9.5, col = ink))
  grid.text(note, 0.06, y - dy * 1.6, just = c("left", "top"), gp = gpar(fontsize = 9, col = ink2, lineheight = 1.15))
}

out <- "analysis/Guichon_subbasins_HRUs_map.pdf"
cairo_pdf(out, width = 11, height = 8.5, onefile = TRUE)
print(p)
draw_table(t2, "HRUs in hbvec.rvh",
           paste0("Subbasin 3 drains to subbasin 1, and subbasin 1 drains to subbasin 2.\n",
                  "HRUs 12–15 are the parts of the original subbasin 1 bands (HRUs 2–5) that lie above WSC 08LG056;\n",
                  "HRUs 2–5 are what is left of those bands below the gauge. HRUs 1 and 6 (solar site) are unchanged."))
invisible(dev.off())
cat("wrote", out, "\n")
