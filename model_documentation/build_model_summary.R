# Build model_documentation/model_summary.pdf: data sources, inputs, structure, calibration,
# final parameters, catchment/HRU map, scenario results and limitations.
#
# Usage (from Raven/HBVEC_Model):  Rscript model_documentation/build_model_summary.R
# Reads (does not change) the model files, calib/results_2026-11-12_daymet/, data/, and the
# baseline/solar run outputs in output/. Map geometry comes from the project geodatabase
# (cleaned hrus_v3_08LG056 / subbasins_v3_08LG056) if it is reachable, otherwise it is rebuilt
# from data/delineation_copy/.

Sys.setenv(TZ = "America/Vancouver")
suppressMessages({ library(sf); library(ggplot2); library(grid); library(ggrepel) })
sf_use_s2(FALSE)
OUT <- "model_documentation/model_summary.pdf"
RES <- "calib/results_2026-11-12_daymet"

ink <- "#0b0b0b"; ink2 <- "#52514e"; rule <- "#d9d8d4"; zebra <- "#f6f5f2"
blue <- "#2a78d6"; orange <- "#eb6834"; aqua <- "#1baf7a"; grey <- "#8a8984"
seqb <- c("#cde2fb", "#9ec5f4", "#6da7ec", "#3987e5", "#256abf", "#184f95", "#0d366b")

# =============================================================================
# 1. Read the model
# =============================================================================
rvh <- readLines("hbvec.rvh"); rvi <- readLines("hbvec.rvi"); rvp <- readLines("hbvec.rvp"); rvt <- readLines("hbvec.rvt")
hr  <- grep("^\\s+\\d+,\\s+[0-9.]+,\\s+[0-9.]+,\\s+[0-9.]+,\\s+-", rvh, value = TRUE)
f   <- lapply(strsplit(sub("#.*", "", hr), ","), trimws)
g   <- function(i) sapply(f, `[`, i)
hru <- data.frame(HRU = as.integer(g(1)), area = as.numeric(g(2)), elev = as.numeric(g(3)),
                  lat = as.numeric(g(4)), lon = as.numeric(g(5)), sb = as.integer(g(6)),
                  lu = g(7), veg = g(8), soil = g(9), desc = trimws(sub(".*#", "", hr)))
sbr <- grep("^\\s+\\d+,\\s+Guichon_", rvh, value = TRUE)
s   <- lapply(strsplit(sub("#.*", "", sbr), ","), trimws)
sbt <- data.frame(id = as.integer(sapply(s, `[`, 1)), name = sapply(s, `[`, 2), down = as.integer(sapply(s, `[`, 3)))
tcr <- grep("^\\s+\\d+,\\s+[0-9.]+,\\s+[0-9.]+\\s*(#.*)?$", rvh, value = TRUE)
tc  <- lapply(strsplit(sub("#.*", "", tcr), ","), trimws)
sbt <- merge(sbt, data.frame(id = as.integer(sapply(tc, `[`, 1)), tc = as.numeric(sapply(tc, `[`, 2)),
                             tp = as.numeric(sapply(tc, `[`, 3))), by = "id")
sbt$area <- tapply(hru$area, hru$sb, sum)[as.character(sbt$id)]
sbt$drain <- sapply(sbt$id, function(i) { up <- function(j) { k <- sbt$id[sbt$down %in% j]; if (length(k)) c(j, up(k)) else j }
                                          sum(sbt$area[sbt$id %in% up(i)]) })
sbt$elev <- sapply(sbt$id, function(i) weighted.mean(hru$elev[hru$sb == i], hru$area[hru$sb == i]))
val <- function(lines, rx) as.numeric(sub(rx, "\\1", grep(rx, lines, value = TRUE)[1]))
start <- sub("^:StartDate\\s+(\\S+).*", "\\1", grep("^:StartDate", rvi, value = TRUE))
end   <- sub("^:EndDate\\s+(\\S+).*", "\\1", grep("^:EndDate", rvi, value = TRUE))
evp   <- grep("^:EvaluationPeriod", rvi, value = TRUE)
solar_area <- sum(hru$area[hru$HRU == 1])

# calibration
ost <- readLines(file.path(RES, "OstOutput0.txt"))
best <- {i <- grep("Optimal Parameter Set", ost); x <- ost[(i + 2):(i + 15)]; x <- x[grepl("^par_", x)]
         setNames(as.numeric(sub(".*:\\s*", "", x)), trimws(sub(":.*", "", x)))}
oin <- readLines("calib/ostIn.txt")
pb  <- oin[(grep("^BeginParams", oin) + 1):(grep("^EndParams", oin) - 1)]; pb <- pb[!grepl("^\\s*#", pb)]
pr  <- do.call(rbind, lapply(strsplit(trimws(sub("#.*", "", pb)), "\\s+"), function(x) data.frame(par = x[1], lo = as.numeric(x[3]), hi = as.numeric(x[4]))))
res_oin <- readLines(file.path(RES, "ostIn.txt"))
rb  <- res_oin[(grep("^BeginParams", res_oin) + 1):(grep("^EndParams", res_oin) - 1)]; rb <- rb[!grepl("^\\s*#", rb)]
st0 <- do.call(rbind, lapply(strsplit(trimws(sub("#.*", "", rb)), "\\s+"), function(x) data.frame(par = x[1], start = as.numeric(x[2]))))
om  <- read.table(file.path(RES, "OstModel0.txt"), header = TRUE)
om$best <- cummin(om$obj.function)

# runs
rdh <- function(run) { x <- read.csv(sprintf("output/%s_Hydrographs.csv", run), check.names = FALSE, strip.white = TRUE)[-1, ]
                       x$date <- as.Date(x$date); x }
hb <- rdh("baseline"); hs <- rdh("solar")
diag <- read.csv("output/baseline_Diagnostics.csv", check.names = FALSE)
diag <- diag[grepl("\\[3\\]", diag$observed_data_series), ]
wy <- function(d) as.integer(format(d, "%Y")) + (as.integer(format(d, "%m")) >= 10)

# forcing (HRU-mean Daymet, area-weighted over the modelled HRUs)
dm <- read.csv("data/processed/daymet_hru_daily.csv"); dm$date <- as.Date(dm$date)
dm <- dm[dm$HRU_ID %in% hru$HRU, ]
dm$w <- hru$area[match(dm$HRU_ID, hru$HRU)] / sum(hru$area)
bas <- aggregate(cbind(P = prcp * w, T = (tmax + tmin) / 2 * w) ~ date, dm, sum)
bas$wy <- wy(bas$date); bas <- bas[bas$wy >= 1981 & bas$wy <= 2024, ]
pts <- read.csv("data/processed/daymet_points.csv"); npts <- sum(pts$HRU_ID %in% hru$HRU)

# =============================================================================
# 2. Page helpers
# =============================================================================
W <- 8.5; H <- 11; L <- 0.07
page_n <- 0
TW <- 1 - 2 * L                                   # text width (npc)
# measured text layout: wrap to a width in npc, and measure real heights
gw <- function(t, gp) convertWidth(grobWidth(textGrob(t, gp = gp)), "npc", valueOnly = TRUE)
wrapw <- function(s, w, gp) {
  out <- character()
  for (para in strsplit(as.character(s), "\n", fixed = TRUE)[[1]]) {
    words <- strsplit(para, " ", fixed = TRUE)[[1]]; cur <- ""
    for (wd in words) { t <- if (cur == "") wd else paste(cur, wd)
                        if (cur != "" && gw(t, gp) > w) { out <- c(out, cur); cur <- wd } else cur <- t }
    out <- c(out, cur)
  }
  paste(out, collapse = "\n")
}
gh <- function(t, gp) convertHeight(grobHeight(textGrob(t, gp = gp)), "npc", valueOnly = TRUE)
pt2npc <- function(pt) pt / (72 * H)
newpage <- function(title) {
  grid.newpage(); page_n <<- page_n + 1
  grid.text(title, x = L, y = 0.955, just = c("left", "top"), gp = gpar(fontsize = 15, fontface = "bold", col = ink))
  grid.lines(x = c(L, 1 - L), y = 0.928, gp = gpar(col = rule, lwd = 0.8))
  grid.text(sprintf("Guichon Creek Raven HBV-EC model  ·  model summary  ·  %s  ·  page %d", format(Sys.Date()), page_n),
            y = 0.02, gp = gpar(fontsize = 7.5, col = ink2))
  0.91
}
txt <- function(y, s, size = 9.3, col = ink, face = "plain", gap = 0.8, mono = FALSE) {
  gp <- gpar(fontsize = size, col = col, fontface = face, lineheight = 1.25, fontfamily = if (mono) "mono" else "")
  for (para in s) {
    t <- wrapw(para, TW, gp)
    grid.text(t, x = L, y = y, just = c("left", "top"), gp = gp)
    y <- y - gh(t, gp) - pt2npc(gap * size)
  }
  y - pt2npc(0.3 * size)
}
head2 <- function(y, s) { gp <- gpar(fontsize = 11.5, fontface = "bold", col = ink)
                          grid.text(s, x = L, y = y - pt2npc(4), just = c("left", "top"), gp = gp)
                          y - gh(s, gp) - pt2npc(12) }
bullets <- function(y, items, size = 9.1) {
  gp <- gpar(fontsize = size, col = ink, lineheight = 1.25)
  for (it in items) {
    t <- wrapw(it, TW - 0.025, gp)
    grid.text("•", x = L + 0.004, y = y, just = c("left", "top"), gp = gpar(fontsize = size, col = ink2))
    grid.text(t, x = L + 0.025, y = y, just = c("left", "top"), gp = gp)
    y <- y - gh(t, gp) - pt2npc(0.75 * size)
  }
  y - pt2npc(4)
}
# table: relative column widths; text wrapped to each column's measured width
tbl <- function(y, df, widths, wrap = NULL, size = 8.2, head_size = size) {
  x0 <- L; xs <- x0 + c(0, cumsum(widths / sum(widths) * TW)); cw <- diff(xs) - 0.012
  pad <- pt2npc(5)
  ghd <- gpar(fontsize = head_size, fontface = "bold", col = ink, lineheight = 1.15)
  gcl <- gpar(fontsize = size, col = ink, lineheight = 1.15)
  hdr <- mapply(function(v, w) wrapw(v, w, ghd), names(df), cw)
  hh <- max(sapply(hdr, gh, gp = ghd))
  grid.text(hdr, x = xs[-length(xs)] + 0.004, y = y, just = c("left", "top"), gp = ghd)
  y <- y - hh - pad
  grid.lines(x = c(x0, 1 - L), y = y + pad / 2, gp = gpar(col = ink2, lwd = 0.7))
  for (i in seq_len(nrow(df))) {
    cs <- mapply(function(v, w) wrapw(v, w, gcl), unlist(df[i, ]), cw)
    rh <- max(sapply(cs, gh, gp = gcl)) + pad
    if (i %% 2 == 0) grid.rect(x = x0, y = y, width = TW, height = rh, just = c("left", "top"), gp = gpar(fill = zebra, col = NA))
    grid.text(cs, x = xs[-length(xs)] + 0.004, y = y - pad / 2, just = c("left", "top"), gp = gcl)
    y <- y - rh
  }
  grid.lines(x = c(x0, 1 - L), y = y, gp = gpar(col = rule, lwd = 0.6))
  y - pt2npc(10)
}
plot_at <- function(p, y, h) { print(p, vp = viewport(x = 0.5, y = y, width = 1 - 2 * L + 0.02, height = h, just = c("centre", "top"))); y - h }
theme_set(theme_minimal(base_size = 8.5) + theme(panel.grid.minor = element_blank(),
  panel.grid.major = element_line(colour = "#ecebe8", linewidth = 0.3), axis.text = element_text(colour = ink2),
  plot.title = element_text(face = "bold", colour = ink, size = 9.5), plot.subtitle = element_text(colour = ink2, size = 8),
  legend.position = "top", legend.justification = "left"))
f2 <- function(x, d = 2) formatC(x, format = "f", digits = d, big.mark = ",")

# =============================================================================
# 3. Figures
# =============================================================================
crs <- 3005
gdb <- "../../ArcGIS/mahatemEEwuh/mahatemEEwuh.gdb"
geo_src <- "project geodatabase (hrus_v3_08LG056, cleaned 2026-11-12)"
hp <- tryCatch(st_transform(st_read(gdb, "hrus_v3_08LG056", quiet = TRUE), crs), error = function(e) NULL)
if (is.null(hp)) {
  geo_src <- "rebuilt from data/delineation_copy/"
  h0 <- st_transform(st_make_valid(st_read("data/delineation_copy/hrus_final.shp", quiet = TRUE)), crs)
  c56 <- st_geometry(st_transform(st_read("data/delineation_copy/catchment_08LG056.shp", quiet = TRUE), crs))
  cut <- h0$subbasin == 1 & h0$BAND > 0
  suppressWarnings({ ab <- st_intersection(h0[cut, ], c56); be <- st_difference(h0[cut, ], c56) })
  ab <- ab[order(ab$HRU_ID), ]; ab$HRU_ID <- 11 + seq_len(nrow(ab))
  hp <- rbind(h0[!cut, "HRU_ID"], be[, "HRU_ID"], ab[, "HRU_ID"])
}
hp <- hp[hp$HRU_ID %in% hru$HRU, ]
hp <- merge(hp[, "HRU_ID"], hru, by.x = "HRU_ID", by.y = "HRU")
hp$class <- ifelse(hp$HRU_ID == 1, "Solar site (HRU 1)",
            ifelse(grepl("1000-1200", hp$desc), "1000-1200 m", ifelse(grepl("1200-1400", hp$desc), "1200-1400 m",
            ifelse(grepl("1400-1600", hp$desc), "1400-1600 m", "1600 m and above"))))
hp$class <- factor(hp$class, levels = c("1000-1200 m", "1200-1400 m", "1400-1600 m", "1600 m and above", "Solar site (HRU 1)"))
sbp <- do.call(rbind, lapply(split(hp, hp$sb), function(x) st_sf(sb = x$sb[1], geometry = st_union(st_geometry(x)))))
sbp$label <- ifelse(sbp$sb == 1, sprintf("Subbasin 1  Guichon_BelowSolar\n%.1f km² (%.1f km² drainage)", sbt$area[sbt$id == 1], sbt$drain[sbt$id == 1]),
                    sprintf("Subbasin 3  Guichon_08LG056\n%.1f km²", sbt$area[sbt$id == 3]))
lab_pt <- suppressWarnings(st_point_on_surface(sbp))
pts_map <- st_transform(st_as_sf(data.frame(label = c("WSC 08LG056\n(calibration gauge)", "Model outlet\n(below solar site)"),
                                            lon = c(-120.91086, -120.8576), lat = c(50.60783, 50.5184)),
                                 coords = c("lon", "lat"), crs = 4326), crs)
hl <- suppressWarnings(st_point_on_surface(hp)); hl <- cbind(hl, st_coordinates(hl))
sl <- cbind(lab_pt, st_coordinates(lab_pt)); pm <- cbind(pts_map, st_coordinates(pts_map))
p_map <- ggplot() +
  geom_sf(data = hp, aes(fill = class), colour = "white", linewidth = 0.12) +
  geom_sf(data = sbp, fill = NA, colour = ink, linewidth = 0.7) +
  geom_sf(data = pts_map, shape = 21, size = 2.8, fill = orange, colour = "white", stroke = 0.8) +
  geom_text_repel(data = hl, aes(X, Y, label = HRU_ID), size = 2.5, colour = ink, min.segment.length = 0.2,
                  bg.color = "white", bg.r = 0.12, seed = 1) +
  geom_label_repel(data = pm, aes(X, Y, label = label), size = 2.4, colour = ink, fill = "#ffffffdd", linewidth = 0,
                   nudge_x = 6000, nudge_y = -2500, seed = 2, segment.colour = ink2) +
  geom_label(data = sl, aes(X, Y, label = label), size = 2.6, fill = "#ffffffdd", linewidth = 0, colour = ink,
             nudge_x = ifelse(sl$sb == 3, 10000, 0), nudge_y = ifelse(sl$sb == 3, 6500, -9000),
             fontface = "bold", lineheight = 0.95) +
  scale_fill_manual(values = c(seqb[c(1, 3, 5, 7)], orange), name = "HRU (elevation band)") +
  coord_sf(crs = crs, datum = 4326) + labs(x = NULL, y = NULL) +
  theme(legend.position = "right", legend.key.size = unit(10, "pt"), panel.grid.major = element_line(colour = "#ecebe8", linewidth = 0.25))

# forcing
fa <- aggregate(cbind(P, T) ~ wy, bas, function(v) v[1]); fa$P <- tapply(bas$P, bas$wy, sum); fa$T <- tapply(bas$T, bas$wy, mean)
p_forc <- ggplot(fa[fa$wy >= 1982, ], aes(wy, P)) + geom_col(fill = blue, width = 0.7) +
  geom_hline(yintercept = mean(fa$P[fa$wy >= 1982]), colour = ink2, linetype = 2, linewidth = 0.3) +
  labs(title = "Model-area precipitation (Daymet, HRU area-weighted), by water year",
       subtitle = sprintf("Before :RainCorrection/:SnowCorrection. Mean %.0f mm/yr (dashed); mean temperature %.1f °C.",
                          mean(fa$P[fa$wy >= 1982]), mean(fa$T[fa$wy >= 1982])), x = NULL, y = "mm")

# calibration convergence
p_conv <- ggplot(om, aes(Run)) + geom_point(aes(y = -obj.function), colour = "#c9c8c4", size = 0.5) +
  geom_line(aes(y = -best), colour = blue, linewidth = 0.8) +
  labs(title = "OSTRICH DDS search", subtitle = "Grey = KGE of each trial; blue = best so far", x = "Trial", y = "KGE at 08LG056 (calibration period)") +
  coord_cartesian(ylim = c(max(-1, min(-om$obj.function)), 0.9))

# fit at 08LG056
q <- data.frame(date = hb$date, sim = hb[["Guichon_08LG056 [m3/s]"]], obs = hb[["Guichon_08LG056 (observed) [m3/s]"]])
q$obs[!is.na(q$obs) & q$obs < 0] <- NA
q$wy <- wy(q$date); q <- q[q$wy >= 1982 & !is.na(q$obs), ]
q$per <- ifelse(q$wy >= 2005, "Calibration WY2005-2024", "Validation WY1982-2004")
q$doy <- as.integer(q$date - as.Date(sprintf("%d-10-01", q$wy - 1))) + 1
cl <- aggregate(cbind(sim, obs) ~ per + doy, q[q$doy <= 365, ], mean)
cll <- rbind(data.frame(per = cl$per, doy = cl$doy, v = cl$obs, s = "Observed"), data.frame(per = cl$per, doy = cl$doy, v = cl$sim, s = "Simulated"))
xb <- scale_x_continuous(breaks = c(1, 93, 183, 274), labels = c("Oct", "Jan", "Apr", "Jul"))
p_clim <- ggplot(cll, aes(doy, v, colour = s)) + geom_line(linewidth = 0.6) + facet_wrap(~per, nrow = 1) + xb +
  scale_colour_manual(values = c(Observed = ink, Simulated = blue), name = NULL) +
  labs(title = "Mean daily hydrograph at WSC 08LG056", x = NULL, y = "m³/s")
an <- aggregate(cbind(sim, obs) ~ wy, q, mean)
anl <- rbind(data.frame(wy = an$wy, v = an$obs, s = "Observed"), data.frame(wy = an$wy, v = an$sim, s = "Simulated"))
p_ann <- ggplot(anl, aes(wy, v, colour = s)) + annotate("rect", xmin = 2004.5, xmax = 2024.5, ymin = -Inf, ymax = Inf, fill = "#eef4fd") +
  geom_line(linewidth = 0.5) + geom_point(size = 1) +
  scale_colour_manual(values = c(Observed = ink, Simulated = blue), name = NULL) +
  annotate("text", x = 2014.5, y = Inf, label = "calibration period", vjust = 1.5, size = 2.6, colour = ink2) +
  labs(title = "Annual mean flow at WSC 08LG056 (days with observations)", x = "Water year", y = "m³/s")

# scenario
sc <- data.frame(date = hb$date, b = hb[["Guichon_BelowSolar [m3/s]"]], s = hs[["Guichon_BelowSolar [m3/s]"]])
sc$wy <- wy(sc$date); sc <- sc[sc$wy >= 1982, ]
ss <- function(v) { a <- tapply(v, sc$wy, mean); p <- tapply(v, sc$wy, max)
                    l <- tapply(v, sc$wy, function(z) min(stats::filter(z, rep(1 / 7, 7), sides = 2), na.rm = TRUE))
                    c(mean(a), mean(p), mean(l)) }
sb_ <- ss(sc$b); ssol <- ss(sc$s)
sc_tab <- data.frame(Statistic = c("Mean annual flow", "Mean annual peak daily flow", "Mean annual 7-day low flow"),
                     `Baseline (m³/s)` = f2(sb_, 4), `Solar (m³/s)` = f2(ssol, 4),
                     `Change (m³/s)` = sprintf("%+.4f", ssol - sb_), `Change (%)` = sprintf("%+.1f", 100 * (ssol - sb_) / sb_), check.names = FALSE)
sc$doy <- as.integer(sc$date - as.Date(sprintf("%d-10-01", sc$wy - 1))) + 1
scc <- aggregate(cbind(b, s) ~ doy, sc[sc$doy <= 365, ], mean)
p_sc <- ggplot(scc, aes(doy)) + geom_line(aes(y = s - b), colour = orange, linewidth = 0.7) +
  geom_hline(yintercept = 0, colour = ink2, linewidth = 0.3) + xb +
  labs(title = "Mean change in daily flow at the model outlet (solar - baseline), WY1982-2024", x = NULL, y = "m³/s")

# =============================================================================
# 4. Tables
# =============================================================================
band_of <- function(d) ifelse(grepl("solar", d), "Solar site", ifelse(grepl("1000-1200", d), "1000–1200 m",
           ifelse(grepl("1200-1400", d), "1200–1400 m", ifelse(grepl("1400-1600", d), "1400–1600 m", "1600 m +"))))
hru_tab <- data.frame(HRU = hru$HRU, Subbasin = hru$sb, Band = band_of(hru$desc), `Area (km²)` = f2(hru$area, 3),
                      `Elev. (m)` = f2(hru$elev, 0), Lat = f2(hru$lat, 4), Lon = f2(hru$lon, 4),
                      `Land use / vegetation` = paste(hru$lu, hru$veg, sep = " / "),
                      `Sample points` = sapply(hru$HRU, function(h) sum(pts$HRU_ID == h)), check.names = FALSE)
sb_tab <- data.frame(ID = sbt$id, Name = sbt$name, `Downstream` = ifelse(sbt$down < 0, "outlet", as.character(sbt$down)),
                     `Area (km²)` = f2(sbt$area, 2), `Drainage area (km²)` = f2(sbt$drain, 2), `Mean elev. (m)` = f2(sbt$elev, 0),
                     `TIME_CONC / TIME_TO_PEAK (d)` = paste(sbt$tc, sbt$tp, sep = " / "),
                     Gauge = ifelse(sbt$id == 3, "WSC 08LG056 (calibration)", "none (deliverable outlet)"), check.names = FALSE)

src_tab <- data.frame(
  Dataset = c("Elevation", "Subbasins and HRUs", "08LG056 catchment", "Streamflow", "Meteorology",
              "Soil porosity", "Forest cover, land use", "Solar footprint"),
  Source = c("NRCan MRDEM 30 m DTM (data/delineation_copy/MRDEM30_dtm.tif)",
             "GIS delineation from the DEM in ArcGIS Pro (hrus_final.shp, subbasins_final.shp); attributes by hru_attributes_arcpy.py",
             "Canadian Lake-River Hydrofabric (CLRH) finalcat_info v1-1, catchments draining to Obs_NM = 08LG056 (split_08LG056_subbasin.R)",
             "WSC HYDAT 08LG056 daily mean discharge via ECCC GeoMet API, retrieved 2026-11-12; 1982-01-01 to 2024-12-31 (get_obs_08LG056.py)",
             sprintf("Daymet V4 R1 1 km daily Tmax, Tmin, precip (Thornton et al. 2022, doi:10.3334/ORNLDAAC/2129), single-pixel API, 1980-2024; %d sample points in the modelled HRUs (get_daymet.R)", npts),
             "BC Soil Information Finder Tool (SIFT) texture mix with Rawls et al. (1982) porosities, less 23% coarse fragments: POROSITY 0.36",
             "Assumed 20% forest cover for all HRUs (judgment, 2026-11-12); interception rates are Raven defaults",
             "Project footprint polygon clipped to the watershed (HRU 1)"),
  Used = c("HRU elevation, area, map", "Model geometry (.rvh)", "Subbasin 3 / HRUs 12-15", "Calibration target",
           "hbvec.rvt (one gauge per HRU)", "hbvec.rvp", "hbvec.rvp", "Solar scenario"),
  check.names = FALSE)

nm <- c(par_TT = "RAINSNOW_TEMP (°C)", par_CFMAX = "MELT_FACTOR (mm/d/K)", par_MINFRAC = "MIN_MELT_FACTOR / MELT_FACTOR",
        par_SFCF = ":SnowCorrection", par_RFCF = ":RainCorrection", par_THICK = "TOPSOIL thickness (m)",
        par_BETA = "HBV_BETA", par_LP = "FIELD_CAPACITY (HBV LP)", par_PERC = "MAX_PERC_RATE (mm/d)",
        par_KF = "BASEFLOW_COEFF fast (1/d)", par_BFN = "BASEFLOW_N fast", par_KS = "BASEFLOW_COEFF slow (1/d)")
modelv <- c(par_TT = val(rvp, "^:GlobalParameter RAINSNOW_TEMP\\s+([0-9.]+).*"),
            par_CFMAX = NA, par_MINFRAC = NA, par_SFCF = val(rvt, "^\\s*:SnowCorrection\\s+([0-9.]+).*"),
            par_RFCF = val(rvt, "^\\s*:RainCorrection\\s+([0-9.]+).*"), par_THICK = val(rvp, "^\\s*DEFAULT_P,\\s*3,\\s*TOPSOIL,\\s*([0-9.]+),.*"))
pt <- merge(merge(pr, st0, by = "par"), data.frame(par = names(best), best = best), by = "par")
pt <- pt[match(names(nm), pt$par), ]
fmt <- function(x) ifelse(abs(x) < 0.1, formatC(x, format = "g", digits = 3), formatC(x, format = "f", digits = 3))
at_bound <- with(pt, ifelse(abs(best - lo) / (hi - lo) < 0.02 | abs(best - hi) / (hi - lo) < 0.02, " (at bound)", ""))
par_tab <- data.frame(`OSTRICH name` = pt$par, `Raven parameter` = nm[pt$par], Range = paste(fmt(pt$lo), "–", fmt(pt$hi)),
                      Start = fmt(pt$start), `Calibrated (in model)` = paste0(fmt(pt$best), at_bound), check.names = FALSE)

d3 <- data.frame(Period = c("Calibration WY2005–2024", "Validation WY1982–2004", "All WY1982–2024"),
                 NSE = f2(diag$DIAG_NASH_SUTCLIFFE, 2), KGE = f2(diag$DIAG_KLING_GUPTA, 2),
                 `Bias (%)` = sprintf("%+.1f", diag$DIAG_PCT_BIAS), `RMSE (m³/s)` = f2(diag$DIAG_RMSE, 3), R2 = f2(diag$DIAG_R2, 2), check.names = FALSE)

fixed_tab <- data.frame(
  Parameter = c("POROSITY", "SAT_WILT", "MAX_CAP_RISE_RATE", "RAINSNOW_DELTA / SNOW_SWI", "ADIABATIC_LAPSE / PRECIP_LAPSE",
                "HBV_MELT_FOR_CORR / REFREEZE_FACTOR / HBV_MELT_ASP_CORR", "FOREST_COV (all HRUs, baseline)", "RAIN_ICEPT_PCT / SNOW_ICEPT_PCT",
                "TIME_CONC / TIME_TO_PEAK", ":AvgAnnualRunoff"),
  Value = c("0.36", "0.0", "1.0 mm/d", "2.0 °C / 0.05", "6.5 °C/km / 0.0 (no lapse: gauges at HRU elevation)",
            "0.5 / 2.0 mm/d/K / 0.48", "0.2", "0.12 / 0.10 (Raven defaults)", "SB1 2.0 / 1.0 d; SB3 1.3 / 0.65 d", "75 mm/yr (08LG056 mean)"),
  Basis = c("Soil survey (SIFT)", "HBV-EC template", "HBV-EC template", "HBV-EC template", "HBV-EC template; Daymet already elevation-adjusted",
            "Template / not identifiable from flow", "Judgment", "Not set explicitly", "Guess (SB3 scaled by sqrt of area)", "Reference discharge only"),
  check.names = FALSE)

proc_tab <- data.frame(
  Process = c("Snow refreeze", "Precipitation partitioning", "Canopy evaporation / sublimation", "Snow balance", "Snow liquid overflow",
              "Infiltration", "Flush to upper zone", "Soil evaporation", "Capillary rise", "Percolation",
              "Fast baseflow", "Slow baseflow", "Within-subbasin routing", "Channel routing"),
  Algorithm = c("FREEZE_DEGREE_DAY", "PRECIP_RAVEN, RAINSNOW_HBV", "CANEVP_ALL (intercepted water all evaporates)", "SNOBAL_SIMPLE_MELT, POTMELT_HBV",
                "OVERFLOW_RAVEN", "INF_HBV (IMPERM bypasses soil)", "RAVEN_DEFAULT", "SOILEVAP_HBV", "CRISE_HBV", "PERC_CONSTANT",
                "BASE_POWER_LAW (FAST_RESERVOIR = SOIL[1])", "BASE_LINEAR (SLOW_RESERVOIR = SOIL[2])",
                "ROUTE_TRI_CONVOLUTION", "ROUTE_NONE"),
  check.names = FALSE)

# =============================================================================
# 5. Pages
# =============================================================================
png_dir <- commandArgs(TRUE)[1]          # optional: write PNG pages to this folder instead (for checking)
if (!is.na(png_dir)) png(file.path(png_dir, "summary_p%02d.png"), width = W, height = H, units = "in", res = 75, type = "cairo") else
  cairo_pdf(OUT, width = W, height = H, onefile = TRUE)

# --- 1. Title / summary
grid.newpage(); page_n <- 1
grid.text("Guichon Creek Raven HBV-EC Model", x = L, y = 0.92, just = c("left", "top"), gp = gpar(fontsize = 22, fontface = "bold", col = ink))
grid.text("Model summary: data, inputs, structure, calibration and solar scenario", x = L, y = 0.875, just = c("left", "top"), gp = gpar(fontsize = 12, col = ink2))
grid.text(sprintf("m.ah a temEEwuh Solar Project  ·  Swiftwater Consulting scope SWC-1-43-01-P-001  ·  generated %s", format(Sys.Date())),
          x = L, y = 0.85, just = c("left", "top"), gp = gpar(fontsize = 9, col = ink2))
y <- 0.80
y <- head2(y, "Purpose")
y <- txt(y, "Assess how the m.ah a temEEwuh Solar Project's land-cover change affects flows in Guichon Creek, BC, about 5 km north of Logan Lake. The deliverable is before/after hydrographs at a model outlet on Guichon Creek immediately below the solar site. A small change is expected, so results are reported as differences between runs, not absolute flows.")
y <- head2(y, "Model at a glance")
glance <- data.frame(Item = c("Model", "Domain", "Spatial units", "Forcing", "Time step and period", "Calibration",
                              "Fit at 08LG056 (KGE)", "Solar scenario", "Result (model outlet)"),
  Description = c("Raven v4.1 (build 2025-12-08), HBV-EC emulation (manual App. F.2)",
                  sprintf("Guichon Creek to the outlet below the solar site: %.1f km² in 2 subbasins", sum(sbt$area)),
                  sprintf("%d HRUs: 200 m elevation bands, split at WSC 08LG056, plus the solar site (HRU 1, %.2f km²)", nrow(hru), solar_area),
                  "Daymet V4 R1 gridded Tmax/Tmin/precip, area-averaged into one virtual gauge per HRU",
                  sprintf("Daily, %s to %s (WY1981 spin-up)", start, end),
                  "OSTRICH DDS, 1000 trials, 12 parameters, maximize KGE at WSC 08LG056 for WY2005–2024",
                  sprintf("%.2f calibration (WY2005–2024), %.2f validation (WY1982–2004)", diag$DIAG_KLING_GUPTA[1], diag$DIAG_KLING_GUPTA[2]),
                  "Solar site from 20% forest to fully impervious (IMPERM 1.0): worst-case screening",
                  sprintf("Mean annual flow %+.1f%%, mean annual peak %+.1f%% (WY1982–2024)",
                          100 * (ssol[1] - sb_[1]) / sb_[1], 100 * (ssol[2] - sb_[2]) / sb_[2])), check.names = FALSE)
y <- tbl(y, glance, c(1.2, 4.2), c(22, 95), size = 8.8, head_size = 8.8)
y <- head2(y, "Contents")
y <- txt(y, paste("1 Summary  ·  2 Catchment and HRUs  ·  3 Data sources  ·  4 Model structure  ·  5 Forcing  ·",
                  "6 Calibration  ·  7 Calibrated fit  ·  8 Final parameters  ·  9 Solar scenario  ·  10 Limitations and files"), size = 9)

# --- 2. Catchment and HRUs
y <- newpage("2  Catchment and HRUs")
y <- plot_at(p_map, y, 0.45)
y <- txt(y - 0.005, sprintf("Map geometry: %s. Subbasin 3 is the catchment of WSC 08LG056 cut out of subbasin 1 with the CLRH hydrofabric; HRUs 2–5 are the parts of each elevation band below the gauge and HRUs 12–15 the parts above it. HRU IDs follow the GIS layers. The model outlet is the downstream end of subbasin 1 (50.5184 N, 120.8576 W).", geo_src), size = 8.3, col = ink2)
y <- head2(y, "Subbasins")
y <- tbl(y, sb_tab, c(0.4, 1.6, 0.8, 0.8, 1, 0.8, 1.3, 1.6), c(4, 20, 10, 10, 10, 8, 14, 18), size = 7.8)
y <- head2(y, "HRUs (hbvec.rvh)")
y <- tbl(y, hru_tab, c(0.4, 0.6, 1, 0.7, 0.6, 0.7, 0.8, 1.7, 0.7), c(4, 8, 14, 8, 6, 8, 10, 22, 8), size = 7.8)

# --- 3. Data sources
y <- newpage("3  Data sources")
y <- tbl(y, src_tab, c(1.1, 4.1, 1.3), c(16, 80, 20), size = 8.1)
y <- txt(y, "Raw downloads are kept unedited in data/raw/; the scripts in data/scripts/ rebuild every model input (see data/README.md). The Daymet point downloads (data/raw/daymet/) are not in git.", size = 8.5, col = ink2)

# --- 4. Model structure
y <- newpage("4  Model structure")
y <- txt(y, c("HBV-EC emulation from the Raven v4.1 manual (Appendix F.2). Each HRU has a snowpack, a canopy, a soil moisture box (TOPSOIL, SOIL[0]) and two conceptual groundwater stores: the fast (upper zone, SOIL[1]) and slow (lower zone, SOIL[2]) reservoirs. Runoff from each HRU is routed to its subbasin outlet with a triangular unit hydrograph; there is no channel routing between subbasins (ROUTE_NONE), so subbasin 3's outflow is added to subbasin 1's.",
              "Key options: :Method ORDERED_SERIES; :Interpolation INTERP_NEAREST_NEIGHBOR; :Evaporation PET_FROMMONTHLY (monthly Hargreaves normals per gauge); :OroTempCorrect / :OroPrecipCorrect / :OroPETCorrect OROCORR_HBV (zero lapse, because each gauge sits at its HRU's elevation); :PrecipIceptFract PRECIP_ICEPT_USER; :SoilModel SOIL_MULTILAYER 3."))
y <- head2(y, "Hydrologic processes (hbvec.rvi)")
y <- tbl(y, proc_tab, c(1.6, 3.4), c(34, 80), size = 8.3)
y <- head2(y, "Scenario method")
y <- txt(y, "hbvec.rvp is the baseline. hbvec_solar.rvp includes it (:RedirectToFile hbvec.rvp) and adds :LandUseChange SOLAR_SITE SOLAR and :VegetationChange SOLAR_SITE SOLAR_VEG dated 1900-01-01, which Raven applies at t = 0. The two runs therefore share every parameter and forcing and differ only in the solar HRU's land cover.")

# --- 5. Forcing
y <- newpage("5  Forcing: Daymet virtual gauges")
y <- bullets(y, c(
  sprintf("Daymet V4 R1 (1 km daily grid) was sampled on a 2 km grid in each HRU (250 m where an HRU would get fewer than 5 points) through the open single-pixel API, because the NetCDF server needs a NASA Earthdata login. %d points cover the modelled HRUs.", npts),
  "Each HRU's daily Tmax, Tmin and precipitation is the mean of its points; the grid is equal-area, so this is the area-weighted HRU mean, as Raven's :GriddedForcing + :GridWeights would compute.",
  "hbvec.rvt holds one gauge per HRU (Daymet_HRUnn) at that HRU's own latitude, longitude and elevation. Nearest-neighbour interpolation therefore gives each HRU its own gauge, and OROCORR_HBV adds no lapse.",
  sprintf("All gauges share :RainCorrection %.3f and :SnowCorrection %.3f (calibrated). Monthly temperature and Hargreaves PET normals are computed per HRU over WY1981–2024.", modelv["par_RFCF"], modelv["par_SFCF"]),
  "Daymet omits Dec 31 in leap years; it is filled with Dec 30's temperatures and zero precipitation."))
y <- plot_at(p_forc, y, 0.32)

# --- 6. Calibration
y <- newpage("6  Calibration")
y <- bullets(y, c(
  "Target: WSC 08LG056, Guichon Creek above Tunkwa Lake Diversion (76.06 km², natural flow, RHBN reference station), the outlet of subbasin 3.",
  "Objective: maximize Kling-Gupta efficiency (KGE) of daily flow over the CALIBRATION period, WY2005–2024 (present-day conditions, which the project acts on). VALIDATION is WY1982–2004. Observed flow at 08LG056 roughly doubled after about 2004 while precipitation did not (pine beetle, mine operations suspected but unverified), so the two periods are different regimes.",
  "Method: OSTRICH v17.12.19, Dynamically Dimensioned Search (DDS), 1000 trials, perturbation 0.20, random seed 20261112, started from the values of an earlier calibration. Setup and checks in calib/ (prepare.py, ostIn.txt); results in calib/results_2026-11-12_daymet/.",
  "Calibrated: 12 parameters (table below). MIN_MELT_FACTOR is tied as a fraction of MELT_FACTOR so it cannot exceed it. Solar-site parameters are not calibrated."))
y <- tbl(y, par_tab, c(0.9, 1.9, 1.0, 0.7, 1.2), c(14, 32, 16, 10, 20), size = 8.2)
y <- plot_at(p_conv, y, 0.27)

# --- 7. Calibrated fit
y <- newpage("7  Calibrated fit at WSC 08LG056")
y <- tbl(y, d3, c(1.8, 0.6, 0.6, 0.8, 0.9, 0.6), size = 8.6, head_size = 8.6)
y <- plot_at(p_clim, y, 0.3)
y <- plot_at(p_ann, y - 0.01, 0.3)
y <- txt(y - 0.005, "The calibration reproduces the higher post-2004 flows by letting more water leave the soil (HBV_BETA ≈ 1.0, FIELD_CAPACITY ≈ 0.80), and as a result over-predicts the earlier regime (validation bias about +80%). Diagnostics are from the baseline run with the rounded parameters in hbvec.rvp/.rvt.", size = 8.3, col = ink2)

# --- 8. Final parameters
y <- newpage("8  Final parameters")
y <- head2(y, "Calibrated (as written in hbvec.rvp / hbvec.rvt)")
fin <- data.frame(`Raven parameter` = nm[pt$par], `File` = ifelse(pt$par %in% c("par_RFCF", "par_SFCF"), "hbvec.rvt (all gauges)", "hbvec.rvp"),
                  Value = paste0(fmt(round(pt$best, ifelse(pt$par %in% c("par_KF", "par_KS"), 4, 3))), at_bound), check.names = FALSE)
fin$Value[fin$`Raven parameter` == nm["par_MINFRAC"]] <- sprintf("%.3f (MIN_MELT_FACTOR = %.3f mm/d/K)", pt$best[pt$par == "par_MINFRAC"],
                                                                   round(pt$best[pt$par == "par_MINFRAC"] * pt$best[pt$par == "par_CFMAX"], 3))
y <- tbl(y, fin, c(2.2, 1.4, 2), size = 8.4)
y <- head2(y, "Fixed (not calibrated)")
y <- tbl(y, fixed_tab, c(2, 2.2, 2), c(34, 34, 34), size = 8.2)
y <- head2(y, "Land use and vegetation classes")
lu <- data.frame(Class = c("MIX20_LU / MIX20_VEG", "SOLAR / SOLAR_VEG"),
                 `Used for` = c("All HRUs (baseline), including the solar site", "Solar site HRU 1 in the solar run only"),
                 FOREST_COV = c("0.2", "0.0"), IMPERM = c("0.0", "1.0"), `MAX_HT / MAX_LAI` = c("5.4 m / 2.0", "0.5 m / 1.0"), check.names = FALSE)
y <- tbl(y, lu, c(1.6, 2.6, 0.8, 0.7, 1.1), size = 8.4)
y <- txt(y, "MAX_HT and MAX_LAI have no effect in this configuration; forest cover acts only through FOREST_COV (interception losses and the HBV forest melt correction).", size = 8.3, col = ink2)

# --- 9. Solar scenario
y <- newpage("9  Solar scenario")
y <- bullets(y, c(
  sprintf("Baseline: the solar site (HRU 1, %.2f km², in subbasin 1) has 20%% forest cover like the rest of the watershed.", solar_area),
  "Solar: HRU 1 becomes land use SOLAR (FOREST_COV 0, IMPERM 1.0). All rain and snowmelt on the site bypasses the soil and goes to the fast reservoir. This is a worst-case screening assumption, not an estimate of the real effect.",
  sprintf("The project footprint clipped to the watershed was given as about 2.1 km²; HRU 1 is %.2f km². If 2.1 km² is right, the modelled change is about %.1f times too large.", solar_area, solar_area / 2.1)))
y <- tbl(y, sc_tab, c(2.2, 1, 1, 1, 0.8), size = 8.6, head_size = 8.6)
y <- plot_at(p_sc, y, 0.28)
y <- txt(y - 0.005, c("Why the solar run is higher every day: removing soil evaporation on the site (roughly 160 mm/yr) adds water to the fast reservoir, which also percolates to the slow reservoir; the slow reservoir drains a fixed fraction daily, so flow rises on every day of the record.",
                      "Caveat on low flows: in this HBV structure impervious runoff still recharges the slow reservoir, so the model cannot show the loss of groundwater recharge that a real impervious surface causes. The volume and peak increases are a reasonable worst case; the low-flow increase is a model artifact and its real sign may be negative."), size = 8.6)

# --- 10. Limitations and files
y <- newpage("10  Limitations and files")
y <- head2(y, "Limitations")
y <- bullets(y, c(
  "One calibration gauge. 08LG056 drains the higher, wetter headwaters (mostly 1200–1750 m); the solar site (about 1215 m) and the rest of subbasin 1 are lower and drier and are assumed to share its parameters. There is no gauge at the model outlet.",
  "Regime shift. Calibrated to WY2005–2024; the same parameters over-predict WY1982–2004 by about 80%.",
  "Two calibrated parameters finished at their bounds (:RainCorrection lower bound 0.80; slow BASEFLOW_COEFF upper bound 0.05).",
  "Tunkwa Lake diversion just below 08LG056 (historic WSC 08LG014) is not modelled; if it still operates, outlet flows are overstated in both runs.",
  "Forest cover (20%) and interception rates are assumed, not mapped (BC VRI could replace the assumption).",
  "No channel routing between subbasins (ROUTE_NONE); daily time step only, so sub-daily storm peaks are not represented.",
  "The solar scenario is a bound: fully impervious site, no panel or depression storage, no evaporation from impervious surfaces, and recharge not reduced (see section 9)."))
y <- head2(y, "Run commands (from HBVEC_Model/)")
y <- txt(y, c("Raven.exe hbvec -o output\\ -r baseline", "Raven.exe hbvec -p hbvec_solar.rvp -o output\\ -r solar",
              "Rscript analysis/plot_solar_dygraph.R      (interactive baseline vs solar)",
              "Rscript model_documentation/build_model_summary.R      (this document)"), size = 8.6, gap = 0.2)
y <- head2(y - 0.01, "Files")
files <- data.frame(File = c("hbvec.rvi", "hbvec.rvh", "hbvec.rvp", "hbvec_solar.rvp", "hbvec.rvt", "hbvec.rvc", "data/", "calib/", "analysis/", "CLAUDE.md"),
  Contents = c("Options, periods, processes, outputs", "Subbasins, HRUs, HRU groups", "Parameters (baseline)",
               "Solar run: includes hbvec.rvp + land-cover change", "Daymet gauges and 08LG056 observations (data/daymet/*.rvt)",
               "Initial conditions (defaults)", "Raw data, processed data and build scripts (data/README.md)",
               "OSTRICH setup and saved results (calib/README.md)", "Plot scripts", "Project conventions, decisions and Raven gotchas"), check.names = FALSE)
y <- tbl(y, files, c(1.3, 4.2), size = 8.3)

invisible(dev.off())
cat("wrote", if (!is.na(png_dir)) file.path(png_dir, "summary_pNN.png") else OUT, "(", page_n, "pages )\n")
