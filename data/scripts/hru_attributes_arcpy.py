"""
Compute Raven :HRUs attributes from the HRU polygons and DEM.

Run with the ArcGIS Pro Python (arcpy + Spatial Analyst):
  "C:\\Program Files\\ArcGIS\\Pro\\bin\\Python\\envs\\arcgispro-py3\\python.exe" -I
      data/scripts/hru_attributes_arcpy.py <delineation_dir> <scratch_dir> <out_csv>

Inputs (in <delineation_dir>):
  hrus_final.shp       fields HRU_ID, HRU_Desc, subbasin, BAND
  subbasins_final.shp  field subbasin
  MRDEM30_dtm.tif      30 m DEM
Outputs:
  <out_csv> with HRU_ID, HRU_Desc, subbasin, BAND, AREA_km2 (EPSG:3005),
  ELEV_mean (zonal mean of DEM), DEM cell count, LAT/LON (WGS84, inside point)

<scratch_dir> must have no spaces in its path (Spatial Analyst ERROR 010819).
"""
import csv
import os
import sys

import arcpy
from arcpy.sa import ZonalStatisticsAsTable

src, scratch, out_csv = sys.argv[1], sys.argv[2], sys.argv[3]
hrus = os.path.join(src, "hrus_final.shp")
subs = os.path.join(src, "subbasins_final.shp")
dem = os.path.join(src, "MRDEM30_dtm.tif")

arcpy.env.overwriteOutput = True
arcpy.CheckOutExtension("Spatial")
gdb = os.path.join(scratch, "hru_work.gdb")
if not arcpy.Exists(gdb):
    arcpy.management.CreateFileGDB(scratch, "hru_work.gdb")
arcpy.env.workspace = gdb
arcpy.env.scratchWorkspace = gdb

bc_albers = arcpy.SpatialReference(3005)
wgs84 = arcpy.SpatialReference(4326)

# --- Copy inputs into the no-spaces gdb -------------------------------------
arcpy.management.CopyFeatures(hrus, "hrus")
arcpy.management.Project(hrus, "hrus_3005", bc_albers)
arcpy.management.Project(subs, "subs_3005", bc_albers)

# --- Attributes per HRU ------------------------------------------------------
rows = {}
with arcpy.da.SearchCursor("hrus_3005", ["HRU_ID", "HRU_Desc", "subbasin", "BAND", "SHAPE@AREA"]) as cur:
    for hid, desc, sb, band, area in cur:
        rows[hid] = dict(HRU_ID=hid, HRU_Desc=desc, subbasin=sb, BAND=band, AREA_km2=area / 1e6)

# Zonal mean elevation (zones rasterised on the DEM grid by the tool)
arcpy.env.snapRaster = dem
arcpy.env.cellSize = dem
ZonalStatisticsAsTable("hrus", "HRU_ID", dem, "zonal_elev", "DATA", "ALL")
with arcpy.da.SearchCursor("zonal_elev", ["HRU_ID", "MEAN", "MIN", "MAX", "COUNT"]) as cur:
    for hid, mean, mn, mx, cnt in cur:
        rows[hid].update(ELEV_mean=mean, ELEV_min=mn, ELEV_max=mx, DEM_cells=cnt)

# Representative point guaranteed inside each (multipart, ring-shaped) HRU
arcpy.management.FeatureToPoint("hrus", "hru_pts", "INSIDE")
with arcpy.da.SearchCursor("hru_pts", ["HRU_ID", "SHAPE@"], spatial_reference=wgs84) as cur:
    for hid, pt in cur:
        p = pt.firstPoint
        rows[hid].update(LAT=p.Y, LON=p.X)

# --- Checks ------------------------------------------------------------------
print("Subbasin polygons (EPSG:3005):")
sub_area = {}
with arcpy.da.SearchCursor("subs_3005", ["subbasin", "SHAPE@AREA"]) as cur:
    for sb, a in cur:
        sub_area[sb] = a / 1e6
        print(f"  subbasin field = {sb}: {a/1e6:.3f} km2")

# Which subbasin polygon contains each HRU (largest overlap)?
# (geometry intersect; Tabulate Intersection needs an Advanced licence)
sub_geoms = [(sb, g) for sb, g in arcpy.da.SearchCursor("subs_3005", ["subbasin", "SHAPE@"])]
best = {}
with arcpy.da.SearchCursor("hrus_3005", ["HRU_ID", "SHAPE@"]) as cur:
    for hid, g in cur:
        for sb, sg in sub_geoms:
            pct = 100.0 * g.intersect(sg, 4).area / g.area
            if hid not in best or pct > best[hid][1]:
                best[hid] = (sb, pct)
for hid in sorted(rows):
    rows[hid]["poly_subbasin"], rows[hid]["poly_overlap_pct"] = best.get(hid, (None, 0.0))

fields = ["HRU_ID", "HRU_Desc", "subbasin", "BAND", "AREA_km2", "ELEV_mean", "ELEV_min", "ELEV_max",
          "DEM_cells", "LAT", "LON", "poly_subbasin", "poly_overlap_pct"]
os.makedirs(os.path.dirname(out_csv), exist_ok=True)
with open(out_csv, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=fields)
    w.writeheader()
    for hid in sorted(rows):
        w.writerow({k: rows[hid].get(k) for k in fields})

print("\nHRUs:")
for hid in sorted(rows):
    r = rows[hid]
    print(f"  {hid:>2} {r['HRU_Desc']:<22} sb={r['subbasin']} band={r['BAND']} "
          f"A={r['AREA_km2']:.3f} z={r['ELEV_mean']:.1f} [{r['ELEV_min']:.0f}-{r['ELEV_max']:.0f}] "
          f"n={r['DEM_cells']} lat={r['LAT']:.4f} lon={r['LON']:.4f} "
          f"in_poly_sb={r['poly_subbasin']} ({r['poly_overlap_pct']:.1f}%)")
tot = {}
for r in rows.values():
    tot[r["subbasin"]] = tot.get(r["subbasin"], 0) + r["AREA_km2"]
print("\nHRU area totals by HRU 'subbasin' field:", {k: round(v, 3) for k, v in tot.items()})
print("Wrote", out_csv)
