# What studies change when they pull from the warehouse

**Date:** 2026-10-02
**Status:** findings. No design is decided here.
**Issue:** #72. It closes the gaps #70 left open.
**Evidence:** `artifacts/results/dwpull-census.json`, from `artifacts/dwpull-census-scan.R`
run over `/studies`.
**Feeds:** ehrlinger/hvtiRtemplates#223, the build job, and the `dw_pull()` module set.

> **Counts only.** This repository is public. The scan names views, columns and join keys
> only under `--emit-names`. The committed result was run without it, and so is this
> document. The named run is held internally and is not cited here. No patient value, study
> identifier or path appears.

---

## 1. Why this was measured

`dw_pull()` ports the data managers' template `tp.stXXXX_dwpull.sas`: its first five
PROC SQL blocks became the five modules in `inst/extdata/modules/`. A port of the template
answers what the template does. It cannot answer what studies do with it, and that is the
question the build job in hvtiRtemplates#223 has to answer. A job that reproduces an
unedited template would be correct for almost no study.

## 2. The corpus

| | files | studies |
|---|---:|---:|
| study instances (`stNNNN_dwpull.sas`) | 113 | 92 |
| template copies (`tp.stXXXX_dwpull.sas`) | 213 | n/a |

All 326 files were read and none failed to parse. 10 instance files sit outside any
taxonomy folder; they are counted, but they are not attributed to a study.

## 3. Findings

### 3.1 Almost every study edits the template

**Only 2 of 92 studies run it byte for byte, and 3 are structurally unedited.** 57 studies
drop at least one template pull, and 56 add a pull the template does not have. Pulls per
instance range from 0 to 23, with a median of 8, which is the template's own count.

So the template is a starting point that every study rewrites. It is not a program studies
run as is.

### 3.2 The additions concentrate in a few views

The studies reference 70 distinct tables and views, 62 of them beyond the template. **Most
of that is a long tail: 50 of the 62 appear in fewer than three studies.** Two views
outside the template each appear in about a third of the studies (33 and 32 studies). A
handful of event views appear in 4 to 15 studies each.

They join through key crosswalks rather than the template's `masterid` and `patid`: 18
distinct non-template key pairs, the most common in 65 studies.

**For the module set:** the two high-use views are the obvious next `dw_pull()` modules.
Below them, a general "extra columns from an event view in a window" module would serve
the tail better than one module per view.

### 3.3 Most studies upload their cohort

**75 of 92 studies write to `HVI_DM` through an ODBC libname**, which is the template's
seventh block. `dw_pull()` is read-only by design. That suits a study whose cohort table the
data managers created, which is a minority.

This is a decision, not a defect. Either the build gains a cohort-upload step, or cohorts
reach the warehouse another way and the build reads them.

### 3.4 The template's date windows were copied, not revised

**82 of the 83 studies that use a `datediff` window use the template's lopsided shape:**
`A <= N OR B >= 0`, which admits everything after the index date as well as `N` days
before it. Its two instances in the template are copied almost everywhere: the 180-day
window in 79 studies and the 60-day window in 61.

The `echo` module already records this as a logged divergence. The census changes what
that divergence means. **Whatever the template's author intended, "180 days before, and
everything after" is now the behaviour 79 studies rely on.** Before #223 reproduces it,
the stat programmers should confirm it is what they want.

The index column also varies: one name in 81 studies and another in 56. The template uses
both.

### 3.5 The inner joins are nearly universal

939 joins are inner and 4 are left. **No study changed the template's inner joins to the
Valve or Cabg views.** If either view lacks a row for some surgeries, every study using the
base pull silently loses those patients, and so does `base.yaml`, which ports it exactly.
One query against the warehouse settles it: the base view's row count against its inner
join with each of the two views. It is listed as an open item, not a finding.

### 3.6 The template barely drifted

The 213 copies fall into 8 byte variants and 6 structural ones, and 192 copies are the
canonical one. Six of the seven non-canonical variants differ only in the placeholder used
for the study number (`stNUM` against `stXXXX`). One, from 2024, drops a pull.

⚠️ **That makes `instances_nearest_drifted` (51) an artefact, not a lineage.** An instance
that renamed its cohort, or dropped a pull, scores closer to a cosmetic variant without
having descended from it. Do not read the 51 as "51 studies started from an old template".

## 4. What the scan cannot see

- **Implicit pass-through.** 64 studies also read through an ODBC libref inside a DATA
  step, which this reader does not parse. **Every view count above is therefore a lower
  bound.**
- **Anything outside a `dwpull` file.** A study that pulls in a differently named program
  is not in the corpus.
- **Intent.** The scan records what the code does, and §3.4 is the clearest case where that
  may differ from what was meant.

## 5. Open items

- [ ] Stat programmers: confirm the window behaviour in §3.4 before #223 reproduces it.
- [ ] Warehouse: the Valve/Cabg row-count check in §3.5.
- [ ] Maintainer: does the build gain a cohort upload step (§3.3)?
- [ ] `dw_pull()`: modules for the two high-use views, and a general windowed event-view
      module (§3.2). File these once §3.3 is decided, since an upload changes what a module
      joins against.
