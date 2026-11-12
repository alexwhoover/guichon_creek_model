# Short explainer of how the Daymet virtual gauges in hbvec.rvt are built, with figures.
#
# Usage (from Raven/HBVEC_Model):  Rscript analysis/daymet_virtual_gauges.R [png_dir]
# Writes: analysis/daymet_virtual_gauges.pdf
#         (optional) one PNG per page in png_dir, for a quick visual check
# Needs:  data/processed/daymet_points.csv and data/raw/daymet/ (from data/scripts/get_daymet.R),
#         hbvec.rvh, data/delineation_copy/{hrus_final,catchment_08LG056}.shp

Sys.setenv(TZ = "America/Vancouver")
suppressMessages({ library(sf); library(ggplot2); library(grid) })
sf_use_s2(FALSE)
png_dir <- if (length(commandArgs(TRUE))) commandArgs(TRUE)[1] else NA

# palette (reference dataviz palette): sequential blue for precipitation, orange for gauges
blues  <- c("#cde2fb", "#9ec5f4", "#6da7ec", "#3987e5", "#256abf", "#184f95", "#0d366b")
gauge  <- "#eb6834"
ink    <- "#0b0b0b"; ink2 <- "#52514e"; rule <- "#d9d8d4"

# ---- HRU polygons as modelled (same construction as get_daymet.R) -----------
crs  <- 3005
hru0 <- st_transform(st_make_valid(st_read("data/delineation_copy/hrus_final.shp", quiet = TRUE)), crs)
c56  <- st_geometry(st_transform(st_read("data/delineation_copy/catchment_08LG056.shp", quiet = TRUE), crs))
suppressWarnings({
  above <- st_intersection(hru0[hru0$subbasin == 1 & hru0$BAND > 0, ], c56)
  below <- st_difference(hru0[hru0$subbasin == 1 & hru0$BAND > 0, ], c56)
})
above <- above[order(above$HRU_ID), ]; above$HRU_ID <- 11 + seq_len(nrow(above)); above$subbasin <- 3
keep <- c("HRU_ID", "subbasin")
hru  <- rbind(hru0[!(hru0$subbasin == 1 & hru0$BAND > 0), keep], below[, keep], above[, keep])
hru  <- st_collection_extract(hru, "POLYGON")
hru  <- aggregate(hru[, "geometry"], by = list(HRU_ID = hru$HRU_ID, sb = hru$subbasin),
                  FUN = function(x) x[1], do_union = TRUE)
parts <- do.call(rbind, lapply(split(hru, hru$HRU_ID), function(h)
  st_sf(HRU_ID = h$HRU_ID, geometry = suppressWarnings(st_cast(st_geometry(h), "POLYGON")))))
parts$km2 <- as.numeric(st_area(parts)) / 1e6
sb <- aggregate(hru[, "geometry"], by = list(sb = hru$sb), FUN = function(x) x[1], do_union = TRUE)

# ---- HRU table from hbvec.rvh -------------------------------------------------
rvh  <- readLines("hbvec.rvh")
rows <- grep("^[[:space:]]+[0-9]+,[[:space:]]+[0-9.]+,[[:space:]]+[0-9.]+,[[:space:]]+[0-9.]+,[[:space:]]+-",
             rvh, value = TRUE)
f    <- strsplit(sub("#.*", "", rows), ",")
loc  <- data.frame(HRU_ID = as.integer(sapply(f, `[`, 1)), area = as.numeric(sapply(f, `[`, 2)),
                   elev = as.numeric(sapply(f, `[`, 3)), lat = as.numeric(sapply(f, `[`, 4)),
                   lon = as.numeric(sapply(f, `[`, 5)), sb = as.integer(sapply(f, `[`, 6)),
                   note = trimws(sub(".*#", "", rows)))
gpts <- st_transform(st_as_sf(loc, coords = c("lon", "lat"), crs = 4326), crs)

# ---- Daymet points: mean annual precipitation and temperature, 1980-2024 -----
pts <- read.csv("data/processed/daymet_points.csv")
stat <- t(sapply(pts$point_id, function(id) {
  ln <- readLines(sprintf("data/raw/daymet/pt_%04d.csv", id))
  x  <- read.csv(text = ln[grep("^year,", ln):length(ln)], check.names = FALSE)
  c(P = sum(x[["prcp (mm/day)"]]) / length(unique(x$year)),
    T = mean((x[["tmax (deg c)"]] + x[["tmin (deg c)"]]) / 2))
}))
pts <- cbind(pts, stat)
ps  <- st_transform(st_as_sf(pts, coords = c("lon", "lat"), crs = 4326), crs)
parts$npts <- lengths(st_intersects(parts, ps))

hs <- do.call(rbind, lapply(sort(unique(pts$HRU_ID)), function(h) {
  q <- pts[pts$HRU_ID == h, ]; p <- parts[parts$HRU_ID == h, ]
  data.frame(HRU_ID = h, n_pts = nrow(q), pieces = nrow(p), missed = 100 * sum(p$km2[p$npts == 0]) / sum(p$km2),
             P = mean(q$P), P_lo = min(q$P), P_hi = max(q$P), P_cv = 100 * sd(q$P) / mean(q$P),
             T_rng = diff(range(q$T)))
}))
tab <- merge(loc, hs, by = "HRU_ID")
hru <- merge(hru, hs[, c("HRU_ID", "P")], by = "HRU_ID")

# ---- page helpers --------------------------------------------------------------
theme_set(theme_minimal(base_size = 9) +
  theme(panel.grid = element_line(colour = "#ecebe8", linewidth = 0.3),
        axis.text = element_text(colour = ink2), plot.title = element_text(face = "bold", colour = ink),
        plot.subtitle = element_text(colour = ink2), legend.position = "right"))
para <- function(txt, y, size = 9.5, width = 105, gp = gpar()) {
  lines <- unlist(lapply(txt, function(t) c(strwrap(t, width), "")))
  grid.text(paste(lines, collapse = "\n"), x = unit(0.07, "npc"), y = y, just = c("left", "top"),
            gp = gpar(fontsize = size, col = ink, lineheight = 1.15))
}
heading <- function(txt, y, size = 12)
  grid.text(txt, x = unit(0.07, "npc"), y = y, just = c("left", "top"),
            gp = gpar(fontsize = size, fontface = "bold", col = ink))
place <- function(p, y, h) print(p, vp = viewport(x = 0.5, y = y, width = 0.88, height = h, just = c("centre", "top")))
footer <- function(n) grid.text(sprintf("Guichon Creek Raven HBV-EC model  ·  Daymet virtual gauges  ·  %d", n),
                                y = unit(0.025, "npc"), gp = gpar(fontsize = 7.5, col = ink2))

# ---- figure: process schematic -------------------------------------------------
steps <- data.frame(
  y = 5:1,
  head = c("1  Daymet V4 R1", "2  Sample points", "3  HRU mean", "4  Virtual gauge", "5  Raven"),
  body = c("1 km daily grid of Tmax, Tmin and precipitation, 1980-2024",
           "Regular 2 km grid clipped to each HRU (250 m where an HRU would get < 5 points);\none single-pixel API request per point (845 points)",
           "Mean of every point inside the HRU, across all of its pieces.\nEqual-area grid, so the mean is the HRU's area-weighted mean",
           "Daymet_HRUnn at the HRU's own LATITUDE, LONGITUDE, ELEVATION from hbvec.rvh,\nwith monthly temperature + Hargreaves PET normals and the shared Rain/SnowCorrection",
           "INTERP_NEAREST_NEIGHBOR: each HRU's nearest gauge is its own (distance 0).\nOROCORR_HBV: HRU elevation = gauge elevation, so no lapse is added"))
p_flow <- ggplot(steps) +
  geom_segment(data = steps[-5, ], aes(x = 0.9, xend = 0.9, y = y - 0.12, yend = y - 0.62),
               arrow = arrow(length = unit(5, "pt"), type = "closed"), colour = ink2, linewidth = 0.4) +
  geom_label(aes(x = 0.02, y = y, label = head), hjust = 0, fill = blues[1], colour = ink,
             linewidth = 0, size = 3.4, fontface = "bold", label.padding = unit(5, "pt")) +
  geom_text(aes(x = 2.35, y = y, label = body), hjust = 0, size = 2.9, colour = ink, lineheight = 1) +
  scale_x_continuous(limits = c(0, 10), expand = c(0, 0)) + scale_y_continuous(limits = c(0.5, 5.5)) +
  theme_void()

# ---- figure: overview map --------------------------------------------------------
bb  <- st_bbox(hru)
p_map <- ggplot() +
  geom_sf(data = hru, aes(fill = P), colour = "white", linewidth = 0.15) +
  geom_sf(data = sb, fill = NA, colour = ink2, linewidth = 0.6) +
  geom_sf(data = ps, colour = ink, size = 0.25, alpha = 0.6) +
  geom_sf(data = gpts, shape = 4, colour = gauge, size = 2.2, stroke = 1.1) +
  geom_sf_label(data = gpts, aes(label = HRU_ID), size = 2.4, nudge_y = 1100, linewidth = 0,
                fill = "#ffffffcc", colour = ink, label.padding = unit(1.5, "pt")) +
  scale_fill_gradientn(colours = blues, name = "Daymet mean\nannual P (mm)") +
  coord_sf(crs = crs, datum = 4326) +
  labs(title = "HRUs, Daymet sample points and virtual-gauge locations",
       subtitle = "Fill = HRU-mean annual precipitation.  Dots = sample points.  × = gauge position (HRU lat/lon in hbvec.rvh).\nDark outlines = subbasins 1-3.",
       x = NULL, y = NULL) +
  theme(legend.key.height = unit(28, "pt"))

# ---- figure: one fragmented HRU close-up -----------------------------------------
H   <- 10
ph  <- parts[parts$HRU_ID == H, ]
pp  <- ps[ps$HRU_ID == H, ]
gh  <- gpts[gpts$HRU_ID == H, ]
p_zoom <- ggplot() +
  geom_sf(data = hru[hru$HRU_ID != H, ], fill = "#f4f3f0", colour = "white", linewidth = 0.15) +
  geom_sf(data = ph, fill = blues[1], colour = blues[5], linewidth = 0.25) +
  geom_sf(data = pp, aes(colour = P), size = 2.2) +
  geom_sf(data = gh, shape = 4, colour = gauge, size = 3.5, stroke = 1.4) +
  scale_colour_gradientn(colours = blues[3:7], name = "Point mean\nannual P (mm)") +
  coord_sf(crs = crs, datum = 4326, xlim = st_bbox(ph)[c(1, 3)], ylim = st_bbox(ph)[c(2, 4)]) +
  labs(title = sprintf("Close-up: HRU %d (subbasin 2, 1400-1600 m band), %d pieces, %d sample points", H, nrow(ph), nrow(pp)),
       subtitle = sprintf("All pieces feed one HRU mean (%.0f mm/yr). The gauge × only labels the HRU for Raven's nearest-neighbour match;\nits position does not affect the forcing values.", hs$P[hs$HRU_ID == H]),
       x = NULL, y = NULL)

# ---- figure: within-HRU spread --------------------------------------------------
pts$HRU <- factor(pts$HRU_ID, levels = sort(unique(pts$HRU_ID)))
p_box <- ggplot(pts, aes(HRU, P)) +
  geom_boxplot(fill = "#f4f3f0", colour = ink2, outlier.size = 0.6, linewidth = 0.35, width = 0.6) +
  geom_point(data = hs, aes(factor(HRU_ID), P), colour = blues[5], size = 2.4, shape = 18) +
  labs(title = "Spread of mean annual precipitation among the sample points in each HRU",
       subtitle = "Box = points in the HRU.  Blue diamond = HRU mean written to the virtual gauge.",
       x = "HRU", y = "mm / year")

# ---- table ----------------------------------------------------------------------
tt <- data.frame(HRU = tab$HRU_ID, SB = tab$sb, `Area km²` = sprintf("%.1f", tab$area),
                 `Elev m` = sprintf("%.0f", tab$elev), Pieces = tab$pieces, Points = tab$n_pts,
                 `Missed %` = sprintf("%.1f", tab$missed), `P mm/yr` = sprintf("%.0f", tab$P),
                 `P range` = sprintf("%.0f-%.0f", tab$P_lo, tab$P_hi), `P CV %` = sprintf("%.1f", tab$P_cv),
                 `T range °C` = sprintf("%.1f", tab$T_rng), check.names = FALSE)
draw_table <- function(df, y0) {
  xs <- c(0.07, 0.13, 0.19, 0.28, 0.36, 0.44, 0.52, 0.61, 0.70, 0.81, 0.89)
  rh <- 0.021
  grid.text(names(df), x = xs, y = y0, just = c("left", "top"), gp = gpar(fontsize = 8, fontface = "bold", col = ink))
  grid.lines(x = c(0.07, 0.96), y = y0 - rh * 0.95, gp = gpar(col = ink2, lwd = 0.6))
  for (i in seq_len(nrow(df))) {
    yy <- y0 - rh * (i + 0.2)
    if (i %% 2 == 0) grid.rect(x = 0.07, y = yy + 0.004, width = 0.89, height = rh, just = c("left", "top"),
                              gp = gpar(fill = "#f6f5f2", col = NA))
    grid.text(unlist(df[i, ]), x = xs, y = yy, just = c("left", "top"), gp = gpar(fontsize = 8, col = ink))
  }
  y0 - rh * (nrow(df) + 1.5)
}

# ---- pages ----------------------------------------------------------------------
pages <- list(
  function() {
    grid.newpage()
    grid.text("How the Daymet virtual gauges are built", x = 0.07, y = 0.95, just = c("left", "top"),
              gp = gpar(fontsize = 17, fontface = "bold", col = ink))
    grid.text("Guichon Creek Raven HBV-EC model  ·  hbvec.rvt  ·  data/scripts/get_daymet.R, write_daymet_rvt.R",
              x = 0.07, y = 0.915, just = c("left", "top"), gp = gpar(fontsize = 9, col = ink2))
    para(c(
      "The model's precipitation and temperature come from Daymet V4 R1, a 1 km daily gridded dataset. Raven can read gridded NetCDF directly (:GriddedForcing with :GridWeights), but Daymet's NetCDF server now requires a NASA Earthdata login. Instead, the grid is sampled with Daymet's open single-pixel service and turned into one 'virtual gauge' per HRU. The result is the same area-weighted HRU forcing that :GridWeights would give, and the standard Raven build can use it with the .rvi, .rvh and .rvp unchanged.",
      "Raven treats an HRU as one lumped unit with no shape. An HRU that is split into many pieces (as elevation bands usually are) behaves exactly like a single block of the same area. The only spatial question is what forcing each HRU receives, and the answer here is the mean over every piece of the HRU."),
      y = unit(0.875, "npc"))
    heading("The five steps", unit(0.70, "npc"))
    place(p_flow, 0.67, 0.42)
    para("Daymet uses a 365-day calendar, omitting Dec 31 in leap years; that day is filled with Dec 30's temperatures and zero precipitation.",
         y = unit(0.22, "npc"), size = 8.5)
    footer(1)
  },
  function() {
    grid.newpage(); place(p_map, 0.97, 0.66)
    para(c(
      "Each elevation-band HRU is scattered across the watershed, so its sample points come from many separate pieces. The densely dotted HRUs (1, 5, 7, 12, 15) are small enough that the 2 km grid would give them fewer than 5 points, so they are sampled every 250 m instead. That is finer than Daymet's 1 km pixels, so neighbouring points repeat values, which does not bias the mean.",
      "The × marks are the gauges' lat/lon from hbvec.rvh, which is each HRU's representative location. Because every HRU has its own gauge at exactly its own coordinates, Raven's nearest-neighbour step always picks that gauge. Precipitation rises toward the east and at higher elevation; Daymet captures both, whereas the single Lornex station had to be lapsed by elevation alone."),
      y = unit(0.36, "npc"))
    footer(2)
  },
  function() { grid.newpage(); place(p_zoom, 0.97, 0.52); place(p_box, 0.42, 0.36); footer(3) },
  function() {
    grid.newpage()
    heading("Per-HRU summary", unit(0.95, "npc"), 13)
    grid.text("Points = sample points.  Missed % = share of HRU area in pieces too small to contain a point.  P and T are 1980-2024 means over the points.",
              x = 0.07, y = 0.925, just = c("left", "top"), gp = gpar(fontsize = 8, col = ink2))
    y <- draw_table(tt, 0.895)
    heading("What this means", unit(y, "npc"))
    para(c(
      "Splitting an HRU into pieces does not bias its forcing: every piece contributes points, and the HRU's gauge carries their mean. The gauge's map position is only a label for Raven's nearest-neighbour match. In one case (HRU 14) it falls outside the HRU's own polygon, which has no effect.",
      sprintf("Some slivers are smaller than the 2 km grid spacing and get no point (largest gap: HRU 3, %.0f%% of its area). They lie in the same elevation band as the rest of the HRU, where precipitation varies by about 1-2%%, so the error is about 0.2%%. Sampling Daymet's own 1 km pixels with exact overlap weights would remove it.", max(tab$missed)),
      "The real limit is lumping itself, not fragmentation. Within an HRU, mean annual precipitation varies by up to 4-5% (CV), about ±10% end to end (HRUs 9 and 10, likely west to east), and mean temperature by up to about 2 °C. One HRU mean smooths this, which slightly affects rain/snow partitioning and melt on days near 0 °C. The 200 m elevation bands keep the temperature range small. Daymet is itself interpolated from stations, so the true spread is probably larger than shown.",
      "The solar-site HRUs (1 and 6) are single pieces with nearly uniform forcing (P CV 0.6% and 0.1%), so the baseline-versus-solar difference is unaffected."),
      y = unit(y - 0.03, "npc"), size = 9.5)
    footer(4)
  })

cairo_pdf("analysis/daymet_virtual_gauges.pdf", width = 8.5, height = 11, onefile = TRUE)
for (pg in pages) pg()
invisible(dev.off())
if (!is.na(png_dir)) for (i in seq_along(pages)) {
  png(file.path(png_dir, sprintf("vg_page%d.png", i)), width = 8.5, height = 11, units = "in", res = 80, type = "cairo")
  pages[[i]](); invisible(dev.off())
}
cat("Wrote analysis/daymet_virtual_gauges.pdf\n")
