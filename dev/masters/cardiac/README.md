# The cardiac-surgery master: scripts

Implements phases 0 to 2 of `dev/specs/2026-09-23-cardiac-master-view-design.md`. These are
scripts, not exports. They are promoted into the package when the mitral master reuses
them (spec §4.1).

## Order

1. `run-phase0.R`: snapshot the current build to parquet and test the candidate keys.
2. `batch-snapshots.R`: the other eleven builds, in the background, on the scan host.
3. `run-phase1.R`: DDL, load, parity, and the `master_cardiac` view.
4. `run-phase2.R`: the corrections tables, the legacy facts as `bake` rows, and the
   corrections view.

## PHI

The parquet files, the warehouse tables and the corrections live outside this repository.
Nothing here holds a key or a value, and nothing prints one: output is counts, verdicts,
column names and line numbers. The legacy facts are read from the SAS program at run time
and written straight to the warehouse.

## Tests

Standalone, against duckdb, with invented data. Run them all:

    for f in dev/masters/cardiac/test-*.R; do Rscript "$f" || break; done

Each prints `all checks passed` or exits non-zero. A test skips (exit 0) when a package it
needs is missing; `install.packages("duckdb")` covers the usual case.
