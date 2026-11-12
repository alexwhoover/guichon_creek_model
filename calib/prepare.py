"""Get the calib\\ folder ready for OSTRICH. Run from calib\\ :  python prepare.py

Does three things, all from the model files in the folder above (never edits them):
  1. Writes the OSTRICH templates (hbvec.rvp.tpl / .rvt.tpl): copies of the
     model files with each calibrated number replaced by its par_ name.
  2. Builds model\\ : the copy of the model that OSTRICH runs (calibration .rvi with
     output switched off, .rvc, data\\*.rvt, and the current .rvp/.rvt/.rvh for a test run).
  3. Checks ostIn.txt against the templates and prints the parameter table.

Re-run it whenever any model file (hbvec.rv*) or ostIn.txt changes.
It does not run Raven or OSTRICH.
"""
import os, re, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
NUM = r"-?\d+\.?\d*(?:[eE][-+]?\d+)?"

# file -> list of (regex for one line with a group per calibrated number, par_ names).
# Each regex must match exactly one line of the file.
SPEC = {
    "hbvec.rvp": [
        (rf"^:GlobalParameter\s+RAINSNOW_TEMP\s+({NUM})", ["par_TT"]),
        (rf"^\s*DEFAULT_P,\s*3,\s*TOPSOIL,\s*({NUM}),", ["par_THICK"]),
        # [DEFAULT] soil row: POROSITY, FIELD_CAPACITY, SAT_WILT, HBV_BETA
        (rf"^\s*\[DEFAULT\],\s*{NUM},\s*({NUM}),\s*{NUM},\s*({NUM}),\s*{NUM},\s*{NUM},\s*{NUM},\s*{NUM}\s*$",
         ["par_LP", "par_BETA"]),
        # FAST_RES row: ..., MAX_PERC_RATE, BASEFLOW_COEFF, BASEFLOW_N
        (rf"^\s*FAST_RES,.*,\s*({NUM}),\s*({NUM}),\s*({NUM})\s*$", ["par_PERC", "par_KF", "par_BFN"]),
        # SLOW_RES row: ..., BASEFLOW_COEFF, BASEFLOW_N
        (rf"^\s*SLOW_RES,.*,\s*({NUM}),\s*{NUM}\s*$", ["par_KS"]),
        # [DEFAULT] melt row: MELT_FACTOR, MIN_MELT_FACTOR, FOR_CORR, REFREEZE, ASP_CORR
        (rf"^\s*\[DEFAULT\],\s*({NUM}),\s*({NUM}),\s*{NUM},\s*{NUM},\s*{NUM}\s*$", ["par_CFMAX", "par_CFMIN"]),
    ],
    "hbvec.rvt": [
        (rf"^\s*:RainCorrection\s+({NUM})", ["par_RFCF"]),
        (rf"^\s*:SnowCorrection\s+({NUM})", ["par_SFCF"]),
    ],
}

def fail(msg):
    sys.exit("ERROR: " + msg)

# ---- 1. templates ------------------------------------------------------------
current = {}
for fname, rules in SPEC.items():
    lines = open(os.path.join(ROOT, fname)).read().split("\n")
    for rx, names in rules:
        hits = [i for i, l in enumerate(lines) if re.search(rx, l)]
        if len(hits) != 1:
            fail(f"{fname}: expected 1 line for {names}, found {len(hits)}. Update SPEC in prepare.py.")
        i = hits[0]
        m = re.search(rx, lines[i])
        if "#" in lines[i][:m.start(1)]:
            fail(f"{fname}: the line for {names} is commented out.")
        new = lines[i]
        for g in range(len(names), 0, -1):          # right to left keeps the positions valid
            current[names[g - 1]] = float(m.group(g))
            new = new[:m.start(g)] + names[g - 1] + new[m.end(g):]
        lines[i] = new
    if fname == "hbvec.rvp":
        for l in lines:
            if re.match(r"\s*:(LandUseChange|VegetationChange)\b", l):
                fail("hbvec.rvp has the solar scenario switched on. Calibrate the baseline: comment it out.")
    with open(os.path.join(HERE, fname + ".tpl"), "w", newline="\n") as fh:
        fh.write("\n".join(lines))
    print(f"wrote {fname}.tpl  ({', '.join(n for _, ns in rules for n in ns)})")

# ---- 2. model\ ----------------------------------------------------------------
model = os.path.join(HERE, "model")
if os.path.isdir(model):
    shutil.rmtree(model)
os.makedirs(os.path.join(model, "data"))
os.makedirs(os.path.join(model, "output"))

rvi = open(os.path.join(ROOT, "hbvec.rvi")).read().split("\n")
drop = (":WriteForcingFunctions", ":CustomOutput", ":SuppressOutput", ":SilentMode")
rvi = [l for l in rvi if not l.strip().startswith(drop)]
rvi += ["", "# Added by calib/prepare.py: write only Diagnostics.csv, and nothing to the console",
        ":SuppressOutput", ":SilentMode", ""]
with open(os.path.join(model, "hbvec.rvi"), "w", newline="\n") as fh:
    fh.write("\n".join(rvi))
for f in ("hbvec.rvc", "hbvec.rvp", "hbvec.rvt", "hbvec.rvh"):
    shutil.copy(os.path.join(ROOT, f), model)
redirects = []
for f in ("hbvec.rvt", "hbvec.rvh", "hbvec.rvp", "hbvec.rvi", "hbvec.rvc"):
    redirects += re.findall(r"^\s*:RedirectToFile\s+(\S+)", open(os.path.join(ROOT, f)).read(), re.M)
for r in redirects:
    dst = os.path.join(model, r)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy(os.path.join(ROOT, r), dst)
print(f"built model\\  (redirected files: {', '.join(redirects)})")

# ---- 3. check ostIn.txt -------------------------------------------------------
ost = open(os.path.join(HERE, "ostIn.txt")).read()
def block(name):
    m = re.search(rf"^Begin{name}\s*$(.*?)^End{name}\s*$", ost, re.M | re.S)
    if not m:
        fail(f"ostIn.txt has no Begin{name} block.")
    return [l.split("#")[0].split() for l in m.group(1).split("\n") if l.split("#")[0].strip()]

params = {p[0]: (float(p[1]), float(p[2]), float(p[3])) for p in block("Params")}
tied = {t[0]: t for t in block("TiedParams")}
problems = []

for name in current:
    if name not in params and name not in tied:
        problems.append(f"{name} is in a template but not in ostIn.txt")
for name in list(params) + list(tied):
    used_by_tie = any(name in t[2:2 + int(t[1])] for t in tied.values())
    if name not in current and not used_by_tie:
        problems.append(f"{name} is in ostIn.txt but not in any template")
names = list(params) + list(tied)
for a in names:
    for b in names:
        if a != b and a in b:
            problems.append(f"{a} is contained in {b}: OSTRICH would substitute it wrongly")

# value in the model files for each free parameter (tied ones are derived)
model_val = {n: current[n] for n in params if n in current}
for t in tied.values():                               # only 'linear' product ties are used here
    x1, x2 = t[2], t[3]
    free = x2 if x1 in current else x1
    known = x1 if x1 in current else x2
    if t[0] in current and known in current and current[known] != 0:
        model_val[free] = current[t[0]] / current[known]

print("\nparameter      model      init       low      high")
for n, (init, lo, hi) in params.items():
    v = model_val.get(n)
    flag = ""
    if v is None:
        flag = "  <-- no model value found"; problems.append(f"{n}: no model value")
    else:
        if abs(v - init) > 1e-9 * max(1, abs(v)):
            flag += "  <-- init differs from the model files"
            problems.append(f"{n}: init {init} differs from the model value {v:g}")
        if not lo <= init <= hi:
            flag += "  <-- init outside the bounds"; problems.append(f"{n}: init outside bounds")
    print(f"{n:12s} {'' if v is None else format(v, '9.4g'):>9s} {init:9.4g} {lo:9.4g} {hi:9.4g}{flag}")
for t in tied.values():
    print(f"{t[0]:12s} {current.get(t[0], float('nan')):9.4g}   (tied: {' x '.join(t[2:2 + int(t[1])])})")

metrics = re.search(r"^:EvaluationMetrics\s+(.*)$", "\n".join(rvi), re.M).group(1).split()
cols = {m: i + 3 for i, m in enumerate(metrics)}
for r in block("ResponseVars"):
    want = "KLING_GUPTA" if r[0].startswith("KGE") else "R2" if r[0].startswith("R2") else None
    col = int(r[-2])
    if want and cols.get(want) != col:
        problems.append(f"{r[0]} reads column {col} but {want} is column {cols.get(want)} in Diagnostics.csv")
print(f"\nDiagnostics.csv columns: " + ", ".join(f"{c} {m}" for m, c in cols.items()))

for exe in ("Ostrich.exe",):
    if not os.path.exists(os.path.join(HERE, exe)):
        problems.append(f"{exe} is missing from calib\\ (see README.md)")
if not shutil.which("Raven.exe"):
    problems.append("Raven.exe is not on the PATH")

if problems:
    print("\nPROBLEMS:"); [print("  - " + p) for p in problems]; sys.exit(1)
print("\nAll checks passed. Next: the test run in README.md, then Ostrich.exe")
