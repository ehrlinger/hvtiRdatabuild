# Analysis sets: a checkpointed, declared subset of `built`

**Status:** design, approved in conversation 2026-09-14. Not yet planned.
**Extends:** `2026-08-24-build-layer-design-capture.md` (Fork 2, "A varset is an
overlay, not a layer") and `2026-09-02-vars-port-and-attrition-design.md` (section 3).
**Consumer:** the hvtiRtemplates descriptive job templates (`dc-tables`, `dc-gfup`,
`dp-postage`), which are held until this ships.

## 1. What this decides

A study's jobs rarely analyse the whole built dataset. `built` may carry 300 columns;
the set a descriptive job reads may carry 71, with a handful of rows excluded for
reasons the study can name. Today every job re-cuts that subset itself, so three jobs
that should read "the same" data have no way to show that they did.

This spec adds one concept, the **analysis set**: a named, declared selection of
`built`'s columns and rows, materialized once, checkpointed against the `built` it was
cut from, and read by every job that needs it.

It decides:

- an analysis set is **select-only**: columns kept and rows excluded, never new
  variables;
- it is **declared in `_study.yml`**, under `analysis_sets:`;
- exclusions are **R predicate strings**, applied first-match-wins with an
  attrition record;
- the set is **materialized** to parquet with a sidecar recording its parent;
- writing is **explicit**, and reading is **strict**: a stale set stops, it is not
  silently rebuilt.

## 2. Why select-only

The build-layer capture settles the lifetime question for derived variables:
"variables created in `build` are permanent members of the built dataset; variables
created in `vars` exist only if the caller invokes the macro." Derivation is the
varset overlay, `derive_vars()`, and its grouping question and the build's target
language are both still open (build-layer capture, "Open questions, revised
2026-08-24").

Selection needs neither answer. A select-only set is a pure function of two inputs,
the `built` file and the declaration, so the same two inputs always give the same set.
That property is what makes a checkpoint meaningful. Allowing derivation would make the
set depend on code that can change underneath it, and would pull the open questions in.

The target-language question does not reach this either. The vault records, 2026-09-04,
"analysis is in R, settled; the open language question is the build only." A set is
cut after the build, on the analysis side.

## 3. Declaration

```yaml
# _study.yml, beside the keys study_init() writes
analysis_sets:
  eda:
    id: ccfid
    vars: [age, female, nyha_pr, aggrc_pr, dead, iv_dead]
    exclude:
      - reason: "No aggrecan measured"
        when:   "is.na(aggrc_pr)"
      - reason: "Age under 18"
        when:   "age < 18"
    expect:
      n: 2696
```

| key | required | meaning |
|---|---|---|
| `id` | yes | Patient identifier column. Must exist in `built` and be unique. Used only inside the exclusion tracker; never written to the set, the sidecar or any report unless it is also listed in `vars`. |
| `vars` | yes | Columns kept, in this order. Every one must exist in `built` (after `read_built()`'s lower-casing). |
| `exclude` | no | Ordered list of `{reason, when}`. Empty or absent means no rows are excluded. |
| `expect` | no | Any of `n`, `n_events`, `n_censored`. When present, a mismatch fails the write. |

`study_config()` in hvtiRutilities validates only its required keys and returns a
fixed list, so `analysis_sets:` neither breaks it nor passes through it. This package
reads the block from `cfg$file` with `yaml::read_yaml()`. **No change to hvtiRutilities.**

⚠️ This is not hvtiRdatabuild's own `study.yaml`, whose `varsets:` key is parsed and
unused. `study.yaml` exists only for studies built in R through `dw_pull()`. The studies
this serves have a SAS-built `built` and a `_study.yml` from `study_init()`, and no
`study.yaml`. `_study.yml` is the one file every study has.

## 4. Exclusion semantics

- Each `when` is parsed with `str2lang()` and evaluated with the data as the
  environment and `baseenv()` as its parent: columns and base functions are visible,
  the global environment is not. A predicate naming an object that is neither is an
  error, not a silent lookup.
- The result must be a logical vector with one value per row. Anything else is an
  error naming the set and the rule.
- **`NA` means not excluded.** SAS `if <missing> then delete` does not delete, and this
  is a port of that behaviour.
- **First match wins.** A row excluded by an earlier rule is not counted by a later
  one, matching sequential `if ... then delete`. Rule order is therefore significant
  and is part of the declaration hash.
- Rules run through `hvtiPlotR::hv_consort_start()` and `hv_consort_exclude()`, as the
  vars-port spec requires, so the CONSORT diagram and the attrition record come from one
  mechanism. `hv_consort_summary()` counts per stage, not per reason
  ([hvtiPlotR#129](https://github.com/ehrlinger/hvtiPlotR/issues/129), open), so until
  that lands the per-rule counts are tabulated from the tracker's exclusion column, and
  that tabulation is removed when #129 ships.

## 5. Functions

Two exports.

### `write_analysis_set(name, cfg = study_config())`

1. Read the declaration for `name`; error if absent, naming the sets that exist.
2. `d <- read_built(cfg)`.
3. Validate `id` (present, unique) and `vars` (all present).
4. Apply the exclusions (section 4) and keep `vars`.
5. Derive counts: `n` always; `n_events` and `n_censored` when the study's
   `cohort$event` column is among `vars`.
6. If `expect` is present and any stated count differs, stop. **Nothing is written.**
7. Write, each atomically (temporary name in the destination, then rename):
   `datasets/<name>.parquet`, then `datasets/<name>.set.yml`, then the manifest entry
   through `hvtiRutilities::update_manifest(file = <parquet>, n_rows =, n_cols =,
   source = "analysis set <name> of <built>")`.
8. Return the sidecar contents invisibly; the attrition table is in the returned
   sidecar and nothing is printed (no chatty output in function bodies).

### `read_analysis_set(name, cfg = study_config())`

Reads `datasets/<name>.parquet` after three checks. Any failure **stops**, naming
`write_analysis_set("<name>")` as the fix:

| check | stale when |
|---|---|
| parent | the sidecar's `parent.sha256` differs from `built`'s current manifest entry `sha256`, or `built`'s size or mtime differs from the sidecar's |
| declaration | the sidecar's `declaration_sha256` differs from the hash of the set's current `_study.yml` block |
| integrity | the parquet's SHA-256 differs from its manifest entry |

The parent check reads `built`'s SHA-256 from `manifest.yaml`, which the
`read_built()` cache keeps current by file stat, so a large SAS `built` is never
re-hashed on a render. Reading the set is cheap to hash: it is the smaller file.

Returns a data frame with `read_built()`'s conventions (lower-case names, no logicals,
labels as attributes), with the attrition table attached as `attr(, "attrition")`.

## 6. The sidecar

```yaml
# datasets/eda.set.yml
set: eda
parent:
  file: built080426.sas7bdat
  sha256: <64 hex>
  size: <bytes>
  mtime: <timestamp>
declaration_sha256: <64 hex>
written: 2026-09-14T15:02:11
counts: {n: 2696, n_events: 412, n_censored: 2284}
n_cols: 6
attrition:
  - {rule: 1, reason: "No aggrecan measured", n_before: 2744, n_excluded: 41, n_after: 2703}
  - {rule: 2, reason: "Age under 18",         n_before: 2703, n_excluded: 7,  n_after: 2696}
packages: {hvtiRdatabuild: 0.2.1, hvtiRutilities: 1.1.8, arrow: 21.0.0}
```

The declaration hash is SHA-256 over the set's block re-serialized with
`yaml::as.yaml()`, so whitespace and comment edits do not make a set stale while any
change to `id`, `vars`, `exclude` or `expect` does.

The sidecar holds counts only. **No identifier is written**, which keeps it safe to
commit beside `manifest.yaml`.

## 7. Dependencies

Imports are unchanged. `arrow` is already in Suggests; `hvtiPlotR` is added there. Both
functions need `arrow`; only `write_analysis_set()` needs `hvtiPlotR`, and only for a
set whose `exclude` is non-empty. Each checks `requireNamespace()` for what it needs
and stops with an install hint,
the pattern `hvtiR` uses for `pak`. No hvtiRutilities internals are called with `:::`;
the atomic write is a few lines local to this package.

## 8. Errors

Every one of these stops before anything is written:

- unknown set name (the message lists the declared ones);
- `id` missing from `built`, or not unique;
- a `vars` column missing from `built` (all missing names listed);
- a `when` that does not parse, or evaluates to the wrong type or length;
- an `expect` mismatch (stated against derived, per count);
- `arrow` or `hvtiPlotR` not installed.

## 9. Testing

Fixtures are temporary studies made with `hvtiRutilities::study_init()` over a CSV
`built`, so the tests exercise the real data contract with no network and no SAS.

- write then read round-trips the kept columns and rows;
- rewriting `built` makes `read_analysis_set()` stop with the parent message;
- editing a rule makes it stop with the declaration message; editing a comment does not;
- corrupting the parquet makes it stop with the integrity message;
- an `expect` mismatch writes nothing (no parquet, no sidecar, no manifest entry);
- first-match-wins: a row matching rules 1 and 2 is counted only under rule 1;
- `NA` in a predicate excludes nothing;
- a predicate naming a global variable errors;
- a non-unique `id` errors;
- the sidecar and manifest contain no value from the `id` column.

## 10. Out of scope

- Derived variables: the varset overlay, `derive_vars()`, and its grouping question.
- The build's target language.
- Any change to hvtiRutilities, including exporting its atomic parquet writer.
- A CONSORT figure. The tracker makes one possible; drawing it is a job template's call.
- A job template that writes sets (a `datasets/` job). `write_analysis_set()` is called
  from the console or from a study's build script until one is asked for.

## 11. What it changes downstream

The hvtiRtemplates descriptive templates read data as:

```r
verify_manifest(file.path(.root, "manifest.yaml"))
# EDIT: the analysis set this job reads, declared in _study.yml. read_built()
# instead reads the whole study cohort.
d <- hvtiRdatabuild::read_analysis_set("eda")
```

That adds `hvtiRdatabuild` to hvtiRtemplates' Suggests and Remotes, and puts a
`verify_manifest()` call in the templates, none of which call it today.
