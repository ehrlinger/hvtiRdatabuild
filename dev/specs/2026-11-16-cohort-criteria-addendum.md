# Cohort criteria: inclusion and exclusion evaluated in the warehouse

**Date:** 2026-11-16
**Status:** design draft, not yet reviewed or planned.
**Amends:** `2026-11-16-master-views-design.md` §5 (study builds), and the cohort query
shipped in #106 (`cohort_query()`, `pull_master()`). Where they disagree, this addendum wins
for cohort selection; nothing else in the master-views design changes.
**Worked example:** a single-centre study of prophylactic temporary mechanical circulatory
support in cardiac surgery, whose criteria are aligned with a published randomized trial.
Its criteria came to us from the study's lead statistical programmer as a question: is
defining this cohort cheaper on the database side than in SAS?

> **Redacted for public release**, as the specs it amends. People are named by role, view
> names are illustrative, and **no patient value or identifier appears here.**

## 1. The problem

A study's cohort is rarely "every encounter with this procedure in this epoch". The worked
example has 6 inclusion criteria and 22 exclusion criteria. Fewer than half are fields of
the cardiac master. The rest are measurements, administrations and results in other sources,
each judged in a **window relative to the surgery date**: an LVEF within 30 days before
surgery, an inotrope within 72 hours, a positive culture with leukocytosis within 72 hours,
a COVID-19 test within two weeks. A few cannot be derived from data at all and need chart
review.

In SAS the cost is structural. The cohort does not exist until the criteria are applied, so
there is nothing to upload. Each criterion's variable is therefore pulled **for the whole
population of the epoch**, joined in SAS, and filtered there. Twenty criteria means twenty
population-sized pulls to keep a few hundred encounters.

The warehouse can do this the other way round. Once the cheap, selective criteria have run
(epoch, procedure, age, LVEF), every later criterion is an `EXISTS` against a candidate set
of a few hundred rows, and only a met or not-met flag leaves the database.

`cohort_query()` as shipped takes one `qualifying` condition on the master. It has no place
for a criterion on another source, no window, no per-criterion count, and no review step.
This addendum adds them.

## 2. Decisions

1. **Criteria are evaluated in the warehouse, in the pull's transaction.** Each criterion
   becomes a flag on the session cohort table (`#study_cohort`), computed in SQL inside the
   same snapshot-isolation transaction as the pull (master-views §6.1). Values never leave
   the database during selection. Only flags do.
2. **Each criterion is its own counted stage.** The cohort record gets one stage per
   criterion, in declared order, so the record *is* the CONSORT diagram. Nothing is
   excluded without a stage and a reason.
3. **The package holds no clinical defaults.** Which source holds LVEF, which echo counts
   when there are several, whether "72 hours" means 72 hours or the registry's shorter
   field: these questions may never be answered centrally, and where they are answered the
   answer is often study-dependent. So **every one of them is a required argument of the
   criterion, with no default**. A criterion that leaves one out is refused. The study's
   choice is recorded in the pull provenance, where a reader can see it and a later study can
   choose differently.
4. **Ambiguity is a stage, not a guess.** When a criterion cannot be decided for a unit (no
   measurement in the window, or tied measurements that disagree), the unit goes to that
   criterion's `undetermined` outcome. The study declares per criterion what happens to
   undetermined units: excluded, kept, or **sent to review**. The worked example's last
   exclusion, "inability to determine eligibility reliably after chart review", is exactly
   this route.
5. **Chart review is a stage of its own.** Criteria that need a person (the planned
   support strategy, "likely to be needed post-operatively", contraindication per the
   device's instructions) are declared as review criteria. They do not query anything.
   Their outcomes arrive as a decisions file, and the stage records that file's checksum.
6. **Criteria are written in the study's build script, in R.** They are versioned with the
   study, not stored in the package or the warehouse. The pull provenance carries each
   criterion's full definition.

## 3. The interface

### 3.1 A criterion

```r
criterion(
  id,           # stage id, e.g. "lvef_30d"
  label,        # CONSORT label, e.g. "LVEF within 30 days before surgery"
  role,         # "include" | "exclude"
  view,         # a view in the same database; NULL means the master row itself
  date_col,     # the view's date column; required unless view is NULL
  window,       # c(from, to) in days relative to the encounter date, e.g. c(-30, 0)
  condition,    # SQL boolean over the view's row (or the master row)
  pick,         # "any" | "nearest" | "all"; required unless view is NULL
  undetermined  # "exclude" | "keep" | "review"
)
```

None of `role`, `window`, `pick` or `undetermined` has a default (decision 3).

`pick` says which rows in the window are judged:

| `pick` | Met when | Undetermined when |
|---|---|---|
| `"any"` | at least one row in the window meets `condition` | no row in the window |
| `"all"` | every row in the window meets `condition` | no row in the window |
| `"nearest"` | the row nearest the encounter date meets `condition` | no row in the window, or rows tied for nearest disagree |

`role` turns met into a verdict: an `include` criterion keeps met units, an `exclude`
criterion drops them.

A criterion with `view = NULL` is a condition on the master row and has no window or pick.
It still gets its own stage, which is the point. Exclusions that live in the master (salvage
status, VSD, prior transplant, dialysis) are written as separate master criteria, not folded
into `qualifying`, so each one is counted.

`condition` is SQL written by the study programmer, as `qualifying` already is. It is never
built from data.

### 3.2 Combining criteria

Some criteria are compound. The worked example's LVEF inclusion is "LVEF ≤ 25%, **or** LVEF
≤ 35% with MR 3+ or 4+ and planned mitral surgery". `any_of()` and `all_of()` combine
criteria into one stage:

```r
lvef <- any_of(
  id = "lvef", label = "LVEF threshold within 30 days before surgery",
  criterion("lvef_le25", ..., view = "echo_measure", window = c(-30, 0),
            condition = "lvef <= 25", pick = "nearest", undetermined = "exclude"),
  all_of(
    criterion("lvef_le35", ..., condition = "lvef <= 35", pick = "nearest", ...),
    criterion("mr_3_4", ..., condition = "mr_grade >= 3", pick = "nearest", ...),
    criterion("mitral_planned", view = NULL, condition = "mitral_surgery = 1", ...)
  )
)
```

A combined stage is met, not met, or undetermined by three-valued logic: `any_of` is met if
any part is met, not met if all parts are not met, and undetermined otherwise. `all_of` is
the mirror image. The parts' own outcomes are kept in the provenance, so "excluded at LVEF"
can still be broken down.

### 3.3 Where criteria plug in

```r
cohort_query(qualifying, epoch, index, prior,
             criteria = list(...),      # criteria and combinations, in stage order
             index_on = c(...))         # "qualifying" | "eligible"; no default
```

`index_on` is the other study-dependent choice. With `index = "first"`:

- `"qualifying"`: take each patient's first qualifying encounter, then apply the criteria.
  A patient excluded at their first surgery is out, even if a later one would qualify. This
  is the trial-like reading.
- `"eligible"`: apply the criteria to every qualifying encounter, then take each patient's
  first encounter that survives. A patient excluded once can enter later.

The two give different cohorts, and neither is right for every study, so it has no default.

### 3.4 Sources outside the warehouse

The worked example expects some variables from sources other than the warehouse. Two routes,
in order of preference:

1. **Load them into a study schema in the same database** (plan 3, with data engineering).
   They then behave like any view, inside the transaction.
2. **A local criterion, evaluated in R after the pull** against the pulled candidates:
   `local_criterion(id, label, role, data, key, decide, undetermined)`, where `data` is a
   file the study holds and `decide` returns met, not met or undetermined per unit. Its stage
   source is `build`, and its provenance records the file's SHA-256. It sees only the
   candidates that survived the warehouse criteria, so the join is small.

A local criterion runs after the snapshot closes. The provenance says so, rather than
implying one snapshot covers it.

### 3.5 Review

```r
review_criterion(id, label, role)   # declared in order with the others
apply_review(pull, decisions)       # decisions: unit id, criterion id, outcome, reason code
```

Stages run in three groups, whatever order they are declared in: warehouse criteria (in
the transaction), then local criteria (§3.4), then review. Declared order holds within each
group. `pull_master()` finishes the warehouse group, pulls, and returns the pull with
`status = "awaiting review"` and the list of units that need it (unit ids only). The
reviewer records outcomes. `apply_review()` checks every pending unit has an outcome, and
appends the review stages. `build_from_master()` refuses a pull that is still awaiting
review.

Review reasons are **codes** from a list the study declares, not free text. Free-text chart
notes are PHI, and the decisions file is checksummed into the release provenance.

This needs a fourth stage source, `review`, in `cohort_record` (`R/cohort_record.R:270`
accepts `upstream`, `build`, `derive`). That is a small, deliberate change to a validated
vocabulary, and it ships in the same plan.

## 4. How a pull runs

Inside the transaction (master-views §6.1):

1. Select the candidate units into `#study_cohort` as now (`qualifying`, epoch, index,
   `prior_qualifying`), adding one nullable flag column per criterion.
2. For each warehouse criterion, in declared order, set its flag on the units still active
   after the previous stages: `1` met, `0` not met, `NULL` undetermined. One statement per
   criterion, an `UPDATE` with a correlated subquery over `view` joined on `mrn` and the date
   window. `nearest` uses `ROW_NUMBER()` ordered by distance from the encounter date, plus
   a check that the tied-nearest rows agree.
3. Read back `(mrn, encounter_date, flags)` only. The stages are built in R from the flags.
4. Pull the master columns for the active units, as now.

Evaluating only the active units at each step is what makes this cheaper than SAS. The order
of criteria changes the per-stage counts (each stage counts among the survivors of the ones
before it) but never the final cohort, because the criteria are a conjunction. With
`undetermined = "review"` the order matters to the review list too, so the study should put
the cheap, decisive criteria first.

All SQL stays in the subset that runs on SQL Server and duckdb (`EXISTS`, `ROW_NUMBER() OVER`,
`CASE`, date arithmetic through a dialect helper, bound parameters). Tests run on duckdb, as
plan 1 does.

## 5. The worked example, mapped

Views are **illustrative**: `echo_measure`, `med_admin`, `lab_result`, `micro_result`,
`dx_history` stand for whichever sources the study names. The study chooses each source,
window, pick and undetermined route. The choices below show the shape, not a ruling.

| Criterion | Kind | Shape |
|---|---|---|
| Epoch 2019-10 to 2026-01; procedure on CPB with cross-clamp and cardioplegia; isolated CABG, MV, bio-AVR, or ≥ 2 of CABG/MVR/AVR/TVR, with permitted concomitants | `qualifying` | master condition |
| Age ≥ 18 | master criterion | `include`, `view = NULL` |
| LVEF ≤ 25, or ≤ 35 with MR 3–4+ and planned mitral surgery, within 30 days | combined | `any_of(...)`, §3.2 |
| EF < 20 needs a viability assessment | windowed or review | study's choice: a criterion on an imaging view, or a review stage |
| Excl. 1 salvage; 7 TCA and excluded procedures; 9 VSD; 12 prior transplant or durable LVAD; 13 chronic dialysis | master criteria | `exclude`, one stage each (if the master holds them) |
| Excl. 3 any inotrope within 72 h | windowed | `med_admin`, `window = c(-3, 0)`, `pick = "any"` |
| Excl. 4 pre-op MCS device | master or windowed | master field, or a device view |
| Excl. 10 stroke within 30 days | windowed | `dx_history`, `c(-30, 0)`, `"any"` |
| Excl. 14 Child-Pugh B or C | windowed, compound | labs (bilirubin, albumin, INR) plus clinical findings; likely `undetermined = "review"` |
| Excl. 16 infection within 72 h | combined | `all_of(positive culture, leukocytosis)`, both `c(-3, 0)` |
| Excl. 17 COVID-19 within 14 days | windowed | `lab_result`, `c(-14, 0)`, `"any"` |
| Excl. 18 pregnancy | windowed | `lab_result`, study-chosen window |
| Excl. 2, 8, 11, 15, 19, 20 | master, windowed or review | by where the study finds them |
| Excl. 5, 6, 21 | review | `review_criterion()` |
| Excl. 22 inability to determine eligibility | the review route | every `undetermined = "review"` unit lands here |

Two things the example shows that the interface must handle:

- **Windows here are in days, and the encounter key is a date.** "Within 72 hours" becomes
  `c(-3, 0)` days, which is wider than 72 hours. A study that needs hour precision needs a
  surgery timestamp in the master and a timestamp column in the view. That is an open
  question (§7), and until it is settled the provenance records the day window actually
  used.
- **A registry field can look like a criterion and not be one.** A registry's pre-operative
  inotrope field may use a shorter window than the trial's 72 hours. Writing the criterion
  against the administration record, with the window stated, is the only way the stated
  window is the window used. Using the registry field is a legitimate study choice, and the
  provenance then says so.

## 6. Provenance and testing

The pull provenance's `cohort_definition` grows to hold each criterion's full definition
(view, date column, window, condition, pick, undetermined route, combination tree), each
local criterion's file checksum, and the review decisions' checksum. Counts per stage come
from the cohort record. **No value from a view is recorded**, only flags and counts.

Tests, on duckdb with invented fixtures that say so:

- each `pick` against rows inside, at the edge of, and outside the window;
- tied-nearest rows that agree (decided) and disagree (undetermined);
- three-valued `any_of`/`all_of`, including undetermined parts;
- each `undetermined` route, and review blocking `build_from_master()`;
- `index_on` giving different cohorts on a patient excluded at a first encounter but
  eligible at a second;
- a criterion with a missing required argument is refused, naming the argument and not any
  value;
- a wrapped `DBI::dbGetQuery` showing that only flags, not view values, leave the database
  during selection (as plan 1's out-of-cohort test does).

## 7. Open questions

These belong to studies or to data engineering, not to the package. The design does not
wait on any of them.

- **Hour-level windows**: whether masters carry a surgery timestamp, and which source views
  carry timestamps.
- **Source views**: which warehouse objects hold echo and MRI measurements, medication
  administrations, labs and microbiology, and whether they are indexed on `(mrn, date)`
  (plan 3, with data engineering).
- **A shared criteria library**: if the same criterion (LVEF within 30 days, nearest)
  recurs across studies, a library of named, versioned criteria may earn its place. Not
  before two studies have written the same one.
- **Review tooling**: the decisions file format is specified here. Any interface for the
  reviewer is not.

## 8. Out of scope

- Selecting the cohort from anything other than a master (§3.4 covers extra sources as
  criteria, not as the base).
- Variables pulled for analysis rather than selection. A criterion decides who is in. The
  study's analysis variables are pulled as columns, as now.
- Any change to the corrections contract or the parity gate.
