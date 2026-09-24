# Master datasets

## What a master is, and why a view

A study build does not read `bd.data.master.sas` fresh every time; it
reads a big rollup dataset, such as the cardiac-surgery or mitral
master, that some earlier program already built and that dozens of
downstream studies share. That sharing is exactly what makes a fix to it
valuable and dangerous at the same time: a chart-review correction found
by one study should reach every study reading that master, but a
hand-edit to the SAS build program reaches only the next person who
happens to rerun it. A warehouse view solves this the way a view usually
does, by giving every reader the same query instead of the same file:
`master_cardiac` sits over a frozen base table, corrections apply inside
the view definition, and the day the corrections table gains a new
accepted row, every study reading the view sees it without anyone
touching their own code. The design that worked this out, including why
the corrections model lives here rather than waiting for a future
warehouse-wide layer, is
`dev/specs/2026-09-23-cardiac-master-view-design.md`.

## `master.yml`

Everything the six exports need to know about one master lives in a
`master.yml` kept outside the package, next to the study configs,
because it names paths on a shared volume.
[`read_master_config()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/read_master_config.md)
reads and validates it:

``` r

cfg_path <- system.file("extdata", "master-example.yml", package = "hvtiRdatabuild")
writeLines(readLines(cfg_path))
#> # A synthetic master configuration, for examples and tests. No real paths.
#> name: master_example
#> key: [ccfid, dt_surg]
#> alt_keys:
#>   epic: [emrn, encounter_date]
#> parent:
#>   master: master_parent
#>   libref: master
#> snapshots: /tmp/master-example
#> current: built.sas7bdat
#> history: "^built_.*\\.sas7bdat$"
#> build_program: /tmp/master-example/bd.data.sas
```

``` r

cfg <- read_master_config(cfg_path)
cfg$key
#> [1] "ccfid"   "dt_surg"
cfg$alt_keys
#> $epic
#> [1] "emrn"           "encounter_date"
```

Field by field:

- `name` names the master, and also the warehouse view and the
  corrections tables built from it (`master_example_corrections`,
  `master_example_corrections_stale`, and so on).
- `key` is the one primary key corrections match on and the view joins
  on. Here it is two columns, `ccfid` and `dt_surg`, because a patient
  identifier alone does not name one surgery.
- `alt_keys` is a named list of bridges to other systems, Epic’s `emrn`
  and `encounter_date` in this example. Each is checked unique where it
  is non-null, and its columns ride along on every correction for
  reference, but nothing matches on them except through
  [`propose_correction()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/propose_correction.md)’s
  explicit `alt_key` argument.
- `parent` names an upstream master this one is built on top of
  (`master_parent`, read through the `master` libref), or is absent for
  a master with no parent.
- `snapshots`, `current`, and `history` locate the SAS builds: the
  directory, the current build’s file name, and a regular expression
  matching historical builds.
- `build_program` is the SAS program whose inline patient-level fixes
  [`backfill_corrections()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/backfill_corrections.md)
  reads.

## Phase 0: `snapshot_master()` and lineage from the log

Before anything reaches the warehouse, the SAS build is frozen as
parquet with \[snapshot_oracle()\], the same way
[`snapshot_oracle()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/snapshot_oracle.md)
freezes any oracle.
[`snapshot_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/snapshot_master.md)
adds two things a plain snapshot does not need: it checks the primary
and alternate keys, and it works out which release of the parent master
this build actually read.

That lineage question matters because a build program can be edited
after it ran, so the current text of `bd.data.master.sas` is not proof
of what happened the day the frozen dataset was produced.
[`snapshot_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/snapshot_master.md)
reads it from evidence, in order: the SAS log whose timestamp brackets
the dataset (SAS writes a `NOTE:` line for every dataset it reads),
then, for the current build only, the build program’s own `set`
statements, then a `parent_release` declared in `master.yml`. A current
build whose parent cannot be decided that way stops rather than guess; a
historical build, whose log is often long gone, is recorded `"unknown"`.
Only those `NOTE:` lines are ever read, never a data line, so nothing
printed here can carry a key or a value.

``` r

dir <- tempfile("master")
dir.create(dir)
file.copy(system.file("extdata", "oracle_small.sas7bdat", package = "hvtiRdatabuild"),
          file.path(dir, "built.sas7bdat"))
#> [1] TRUE
writeLines("data m; set base; run;", file.path(dir, "bd.data.sas"))
cfg_path <- file.path(dir, "master.yml")
writeLines(c("name: master_demo", "key: [ccfidu]",
             paste0("snapshots: ", dir), "current: built.sas7bdat",
             paste0("build_program: ", file.path(dir, "bd.data.sas"))),
           cfg_path)
snap <- snapshot_master(read_master_config(cfg_path), tempfile("out"), which = "current")
#> built.sas7bdat                           4 rows x 5 columns; key unique; parent NA (none)
snap[, c("file", "status", "n_rows", "key_verdict", "parent_source")]
#>             file  status n_rows key_verdict parent_source
#> 1 built.sas7bdat written      4      unique          none
```

With no `parent:` in this `master.yml`, `parent_source` reads `"none"`.
Give the master a parent and
[`snapshot_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/snapshot_master.md)
reports `"log"`, `"program"`, or `"declared"` instead, naming where it
found the answer, never the answer’s underlying data.

## Phases 1 and 2: `lift_master()` and `backfill_corrections()`, dry run first

[`lift_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/lift_master.md)
moves a snapshot into the warehouse. It checks the key is unique,
creates a base table named for the snapshot’s release, loads the parquet
a row group at a time, and only then proves the load equal to the
snapshot: a quick check first (counts, aggregates, a sample), a full
column-by-column comparison second. The master’s view is created only
after both pass. `dry_run = TRUE`, the default, stops after writing the
DDL next to the snapshot, so a hand-off to whoever holds warehouse write
rights costs nothing to try:

``` r

pq <- file.path(dir, "built_demo.parquet")
arrow::write_parquet(data.frame(id = c("K1", "K2"), x = c(1, 2)), pq)
jsonlite::write_json(
                     list(parquet_sha256 = digest::digest(pq, algo = "sha256", file = TRUE),
                          columns = list(list(variable = "id", r_class = "character"),
                                         list(variable = "x", r_class = "numeric"))),
                     file.path(dir, "built_demo.meta.json"), auto_unbox = TRUE)
cfg_path <- file.path(dir, "master.yml")
writeLines(c("name: master_demo2", "key: [id]", paste0("snapshots: ", dir),
             "current: built_demo.sas7bdat",
             paste0("build_program: ", file.path(dir, "bd.sas"))), cfg_path)
con <- DBI::dbConnect(duckdb::duckdb())
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp6DPoD3/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
dry <- lift_master(read_master_config(cfg_path), con, pq, dialect = "duckdb")
#> key id                               unique     rows 2, null key parts 0, duplicates 0
#> dry run: DDL for master_demo2_base_built_demo written to /tmp/Rtmp6DPoD3/master1ef42102482e/built_demo.parquet.ddl.sql
dry$dry_run
#> [1] TRUE
```

Once the DDL is right, the same call with `dry_run = FALSE` creates the
base table, loads it, checks parity, and publishes the view:

``` r

lifted <- lift_master(read_master_config(cfg_path), con, pq, dry_run = FALSE,
                      dialect = "duckdb")
#> key id                               unique     rows 2, null key parts 0, duplicates 0
#> load: 1 row groups loaded, 0 already present
#> parity pass: row count match; 0 of 2 columns mismatch; 0 of 2 sampled columns mismatch
#> parity_full: 0 of 2 columns mismatch
#> view master_demo2 -> master_demo2_base_built_demo
lifted$verdict
#> [1] "pass"
DBI::dbGetQuery(con, "SELECT * FROM master_demo2 ORDER BY id")
#>   id x
#> 1 K1 1
#> 2 K2 2
```

[`backfill_corrections()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/backfill_corrections.md)
closes the gap between a master newly in the warehouse and a build
program that still carries its patient-level fixes inline as
`if ccfid = 'K1' then age = 66;` statements. It reads those fixes,
resolves each one against the base table, and records the ones that
resolve to exactly one record as a correction with an unknown prior and
a `bake` decision, meaning it is already present in the snapshot rather
than something the view still needs to apply. A fix that changes a key
column, matches no record, matches more than one, or cannot be parsed is
reported by reason and line number, never recorded. It also requires a
passing parity record, so it only runs after
[`lift_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/lift_master.md)
has succeeded once. Dry run first, as with
[`lift_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/lift_master.md):

``` r

d <- data.frame(ccfid = c("K1", "K2", "K3"), dt_surg = as.Date("2020-01-01") + 0:2,
                emrn = c("E1", NA, "E3"), age = c(65.5, NA, 70),
                surgeon = c("S1", "S2", "S3"), stringsAsFactors = FALSE)
pq2 <- file.path(dir, "built_t.parquet")
arrow::write_parquet(d, pq2)
jsonlite::write_json(
  list(parquet_sha256 = digest::digest(pq2, algo = "sha256", file = TRUE), columns = list(
    list(variable = "ccfid", r_class = "character"),
    list(variable = "dt_surg", r_class = "Date"),
    list(variable = "emrn", r_class = "character"),
    list(variable = "age", r_class = "numeric"),
    list(variable = "surgeon", r_class = "character")
  )),
  file.path(dir, "built_t.meta.json"), auto_unbox = TRUE
)
writeLines(c("data m; set base;",
             "if ccfid = 'K1' then age = 66;",
             "if ccfid = 'K2' then ccfid = 'K9';",
             "run;"), file.path(dir, "bd.sas"))
cfg2_path <- file.path(dir, "master.yml")
writeLines(c("name: master_c", "key: [ccfid, dt_surg]", "alt_keys:", "  epic: [emrn]",
             paste0("snapshots: ", dir), "current: built_t.sas7bdat",
             paste0("build_program: ", file.path(dir, "bd.sas"))), cfg2_path)
cfg2 <- read_master_config(cfg2_path)
invisible(lift_master(cfg2, con, pq2, dry_run = FALSE, dialect = "duckdb"))
#> key ccfid + dt_surg                  unique     rows 3, null key parts 0, duplicates 0
#> load: 1 row groups loaded, 0 already present
#> parity pass: row count match; 0 of 5 columns mismatch; 0 of 5 sampled columns mismatch
#> parity_full: 0 of 4 columns mismatch
#> view master_c -> master_c_base_built_t
backfill_corrections(cfg2, con, dialect = "duckdb")
#> legacy: 2 facts parsed; 1 resolved; 1 unresolved
#>   unresolved by reason: key_variable 1
#>   at lines: 3
#> dry run: nothing written
```

The dry run above reports one fix resolved (the `age` fix) and writes
nothing. The `ccfid` remap is a key change, not a cell correction, so it
is not counted among the resolved facts; identity corrections of that
kind are designed separately (see the last section). Run it for real and
the correction and its `bake` decision land in the tables, and the
master’s view is regenerated:

``` r

backfill_corrections(cfg2, con, dry_run = FALSE, dialect = "duckdb")
#> legacy: 2 facts parsed; 1 resolved; 1 unresolved
#>   unresolved by reason: key_variable 1
#>   at lines: 3
#> recorded 1; 0 stale corrections
DBI::dbGetQuery(con, "SELECT decision FROM master_c_correction_decisions")
#>   decision
#> 1     bake
```

## The everyday workflow: `propose_correction()`, `decide_correction()`, the stale view

Once a master is lifted and backfilled, most corrections do not come
from a SAS build at all. They come from an investigator’s chart review,
one cell at a time, and
[`propose_correction()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/propose_correction.md)
is how that reaches the table:

``` r

prop <- propose_correction(cfg2, con,
                           key_values = list(emrn = "E3"), alt_key = "epic", variable = "age",
                           expected_prior = 70, new_value = 71, evidence_type = "chart_review",
                           evidence_ref = "invented", asserted_by = "tester", dialect = "duckdb")
#> Correction c46b09039391802fb appended.
prop$verdict
#> [1] "appended"
```

Finding the record by `emrn` through `alt_key` rather than by `ccfid`
and `dt_surg` resolves to the primary key before anything is written, so
the stored row still carries the primary key, with `emrn` filled in for
reference. A proposal writes no decision, so it does not apply until
someone accepts it:

``` r

decide_correction(cfg2, con, prop$correction_id, "accept", "tester", dialect = "duckdb")
#> Decision db190f83f4c704426 (accept) recorded on c46b09039391802fb.
DBI::dbGetQuery(con, "SELECT age FROM master_c WHERE emrn = 'E3'")
#>   age
#> 1  71
```

Not every accepted correction applies, and that is what the stale view
is for. A correction goes stale when its variable is not a correctable
column, its key no longer matches a row, its recorded prior does not
match what the base currently holds, or either value fails to cast to
the column’s type. Rather than silently skip a correction that no longer
fits,
[`lift_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/lift_master.md)
and
[`backfill_corrections()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/backfill_corrections.md)
publish a `<name>_corrections_stale` view alongside the master’s own,
naming exactly which corrections did not apply and why, so a stale
correction is a thing you can query, not a thing you have to notice went
quiet.

``` r

DBI::dbGetQuery(con, "SELECT * FROM master_c_corrections_stale")
#> [1] correction_id variable      reason       
#> <0 rows> (or 0-length row.names)
```

## What is not done yet

Three things this vignette does not show, because the package does not
do them yet:

- **The port.** Nothing here writes a study’s `bd.R`/`vars.R` against a
  master view; that is the next spec in the replacement path, once a
  master read function exists.
- **Identity corrections.**
  [`backfill_corrections()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/backfill_corrections.md)
  finds `ccfid`-remap statements and reports them unresolved rather than
  recording them, because a remapped key changes which row every other
  correction points at. Applying them before cell corrections is
  designed in the mitral port spec, not implemented here.
- **A stated limit of the lifted state.** A child master’s base is a
  snapshot with its parent’s values already baked in at build time. A
  correction made to the parent afterward does not reach the child until
  the child is ported to read the parent’s view directly, which is also
  part of that port.
