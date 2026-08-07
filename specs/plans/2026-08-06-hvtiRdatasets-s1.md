# hvtiRdatasets S1 (Pull) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the warehouse pull — read a validated `study.yaml`, open a credentialed ODBC connection without ever storing or echoing a secret, execute one query per enabled module, and record what was pulled in a manifest.

**Architecture:** Four public functions and one data directory. `read_study_config()` loads and schema-validates `study.yaml`. `dw_connect()` walks a credential ladder and returns a `DBIConnection`. Module queries ship as **data** (`inst/extdata/modules/*.yaml`) parameterised by warehouse, schema, and cohort table, so no site-specific identifier lives in R source. `dw_pull()` executes the enabled modules against a connection and returns a named list of raw tables plus a pull manifest. Every database path is mocked in tests; the suite runs with no warehouse.

**Tech Stack:** R (>= 4.1.0), DBI, yaml, odbc (Suggests), testthat edition 3, roxygen2.

**Spec:** `specs/2026-08-04-hvtiRdatasets-design.md`

**Scope decisions taken 2026-08-06, by the maintainer:**

1. **S1 is read-only.** The cohort write-back is deferred to a later slice with its own review. `dw_pull()` never writes to the warehouse.
2. **`tp.stXXXX_dwpull.sas` is the target variant.** `snapshotpull` and `ccfpull` both *require* uploading a cohort before they can join, so neither is compatible with a read-only slice; both are also re-pull paths that take an existing `library.built` as input. They become a later re-pull slice.

---

## Global Constraints

- Package version ends S1 at `0.1.1`. Always a straight three-digit semantic version — never a `.9000` suffix or a fourth digit. **Bump the patch digit only; the minor and major digits are the maintainer's call, not this plan's.**
- `R (>= 4.1.0)` in `Depends`. Licence `GPL (>= 3)`. Maintainer `John Ehrlinger <john.ehrlinger@gmail.com>`.
- `odbc` is in **Suggests**, not Imports. Every use is guarded by `requireNamespace("odbc", quietly = TRUE)`; every test touching it calls `skip_if_not_installed("odbc")`. `DBI` and `yaml` go to **Imports** — both are small, pure-R, and used unconditionally.
- **Add a package to `Imports` in the same task that first uses it, never earlier.** `R CMD check` notes a declared import that no code uses, which breaks the 0/0/0 gate.
- `testthat` edition 3 (`Config/testthat/edition: 3`).
- Every exported object has a roxygen `@return`. Internal helpers are `@keywords internal` + `@noRd`, matching `.read_sas_dataset()` and `.validate_snapshot()`.
- Errors use `stop(..., call. = FALSE)` and say what to do about it, matching the S0 house style.
- Maximum 2 cores anywhere.
- **No PHI in any fixture, test, or vignette.** All data is synthetic.
- **No credential value in any file, log line, error message, or commit.** Connection strings are never echoed, not even on error.
- **No site-specific infrastructure identifier in the repository.** No server hostname, port, database name, schema name, or fully-qualified view name. This repo is public. The spec's placeholders (`<DW-SERVER>`, `<PORT>`, `<DW-DB>`, `<SCHEMA>`, `<AD-DOMAIN>`) are the only permitted forms in prose; in code, these values arrive from `study.yaml` at runtime. Commit `7562a08` did this redaction once already — do not undo it.
- **Preserve SAS variable names exactly.** S0–S4 are under the naming freeze (spec § Variable naming policy). `compare_built()` joins by variable name; renaming destroys the ruler.
- **No test requires warehouse access.** Every DB path is mocked with `testthat::local_mocked_bindings()`. The gated real-study test in Task 6 skips unless an environment variable points at real data.
- **`lintr::lint_package()` must be clean.** CI runs it with `LINTR_ERROR_ON_LINT: true`, so a single lint fails the build. The repo's `.lintr` is `linters_with_defaults(line_length_linter(100))` — defaults plus a 100-character line limit. Run `Rscript -e 'lintr::lint_package()'` before every commit and expect no output.
- **Every new exported topic must be added to `_pkgdown.yml`'s `reference:` index in the same task that exports it.** The index is explicit, and pkgdown fails the build on a topic that exists but is not listed. The `pkgdown.yaml` workflow runs on every push.
- **Documentation must be committed in sync with its roxygen sources.** The `docs-current` CI job runs `roxygen2::roxygenise()` and then `git diff --exit-code man/ NAMESPACE DESCRIPTION`. Always `devtools::document()` and commit `man/` and `NAMESPACE` alongside the code. Local roxygen2 must be **8.1.0** — CI pins it, and roxygen stamps its own version into `Config/roxygen2/version`, so a mismatched local version fails the check on a version line rather than a doc change.
- **Plain `R CMD check` must finish 0 errors / 0 warnings / 0 notes** before each commit that touches package code. **Not `--as-cran`** — that runs CRAN incoming feasibility, which emits an unavoidable "New submission" NOTE. `hvtiRdatasets` is not a CRAN target.
- **Put LaTeX on `PATH` before checking: `export PATH="/Library/TeX/texbin:$PATH"`.** A non-interactive shell does not inherit it, and without it the PDF-manual step fails with `1 ERROR, 1 WARNING` that looks like a package defect and is not. **Pass `manual = TRUE` explicitly** — `devtools::check()` defaults it to `FALSE`, so the plain call silently skips the PDF manual, which is the step that catches raw Unicode in `.Rd` and unresolvable `\link{}` cross-references. Never reach for `--no-manual`.
- Work happens on branch `feat/s1-pull`. Never commit to `main`.
- Development is on macOS; execution is on the SAS/RStudio server. No task in this slice opens a real connection.

---

## File Structure

| File | Responsibility |
|---|---|
| `R/study_config.R` | `read_study_config()` — load and schema-validate `study.yaml`. Unknown key is an error. |
| `R/dw_credentials.R` | Internal credential ladder: source resolution, file-mode enforcement, `.Renviron` shadow warning. No DBI. |
| `R/dw_connect.R` | `dw_connect()` — assemble the connection and return a `DBIConnection`. |
| `R/dw_modules.R` | `dw_modules()` + `.module_sql()` — load module definitions from data, interpolate placeholders. |
| `R/dw_pull.R` | `dw_pull()` — execute enabled modules, build the pull manifest. |
| `inst/extdata/modules/*.yaml` | One file per module: join keys, view suffix, column policy, optionality. **Data, not code.** |
| `tests/testthat/test-study_config.R` | Config loading and validation. |
| `tests/testthat/test-dw_credentials.R` | Ladder order, mode enforcement, shadow warning. |
| `tests/testthat/test-dw_connect.R` | Connection assembly, credential non-disclosure. |
| `tests/testthat/test-dw_modules.R` | Module data integrity, SQL interpolation. |
| `tests/testthat/test-dw_pull.R` | Pull behaviour against a mocked DBI. |
| `tests/testthat/test-integration-real-study.R` | *Modify* — extend the gated harness to pull-stage datasets. |
| `_pkgdown.yml` | *Modify* — add a "Pull: Warehouse to R" reference section. Every task that exports a topic adds it here in the same commit. |

**New reference section.** Tasks 1, 3, 4, and 5 each export at least one topic. Add this section to `_pkgdown.yml` under `reference:`, after the existing "Verify: R Build vs. SAS Oracle" block, growing its `contents:` as each task lands:

```yaml
- title: "Pull: Warehouse to R"
  desc: >
    Read a study's configuration, open a credentialed warehouse connection,
    and pull the modules the study declares. The pull is read-only.
  contents:
  - read_study_config
  - dw_connect
  - dw_modules
  - dw_pull
  - print.pull_result
```

Module SQL lives in `inst/extdata/modules/` rather than in R source for the same reason the variable-list fragments do (spec § The corpus is three populations): it is data with a provenance, it changes independently of the code that executes it, and keeping it out of R source is what lets the repo stay free of site identifiers.

---

### Task 1: Study configuration

**Files:**
- Create: `R/study_config.R`
- Create: `tests/testthat/test-study_config.R`
- Modify: `DESCRIPTION` (add `yaml` to `Imports`, remove it from `Suggests`)

**Interfaces:**
- Consumes: nothing.
- Produces: `read_study_config(path)` → object of class `study_config`, a list with elements `study` (character scalar), `cohort_table` (character scalar), `warehouse` (character scalar), `view_schema` (character scalar), `pull_date` (`Date`), `modules` (character vector), `varsets` (character vector), `derive` (named logical vector). Task 5 consumes all of these.

**Deliberate extension of the spec's example.** The spec's `study.yaml` sketch (§ Configuration model) has six keys: `study`, `cohort_table`, `pull_date`, `modules`, `varsets`, `derive`. This task adds two — `warehouse` and `view_schema` — because the module SQL in Task 4 must name the warehouse database and view schema, and this repository is public. Putting those two values in `study.yaml`, which lives in the study directory rather than in the package, is what keeps them out of the repo. Nothing else about the spec's model changes.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-study_config.R`:

```r
.write_config <- function(..., .extra = NULL) {
  cfg <- utils::modifyList(
    list(
      study        = "st1234",
      cohort_table = "<DW-DB>.<SCHEMA>.st1234_cohort",
      warehouse    = "<WAREHOUSE>",
      view_schema  = "dbo",
      pull_date    = "2026-08-04",
      modules      = list("base", "fup"),
      varsets      = list("core"),
      derive       = list(missing = TRUE, transform = TRUE, propensity = FALSE)
    ),
    list(...)
  )
  if (!is.null(.extra)) cfg <- c(cfg, .extra)
  path <- withr::local_tempfile(fileext = ".yaml", .local_envir = parent.frame())
  yaml::write_yaml(cfg, path)
  path
}

test_that("a well-formed study.yaml loads with the documented types", {
  cfg <- read_study_config(.write_config())

  expect_s3_class(cfg, "study_config")
  expect_identical(cfg$study, "st1234")
  expect_identical(cfg$modules, c("base", "fup"))
  expect_s3_class(cfg$pull_date, "Date")
  expect_identical(cfg$derive[["propensity"]], FALSE)
})

test_that("an unknown key is an error, not a silent no-op", {
  path <- .write_config(.extra = list(modulez = list("base")))

  expect_error(read_study_config(path), "Unknown key.*modulez")
})

test_that("a missing required key names the key", {
  cfg  <- list(study = "st1234")
  path <- withr::local_tempfile(fileext = ".yaml")
  yaml::write_yaml(cfg, path)

  expect_error(read_study_config(path), "cohort_table")
})

test_that("an unparseable pull_date is an error", {
  path <- .write_config(pull_date = "04/08/2026")

  expect_error(read_study_config(path), "pull_date.*YYYY-MM-DD")
})

test_that("a non-logical derive flag is an error", {
  path <- .write_config(derive = list(missing = "yes"))

  expect_error(read_study_config(path), "derive.*missing.*logical")
})

test_that("a missing file names the path", {
  expect_error(read_study_config("/nonexistent/study.yaml"), "does not exist")
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Rscript -e 'devtools::test(filter = "study_config")'`
Expected: FAIL — `could not find function "read_study_config"`.

- [ ] **Step 3: Add `yaml` to Imports**

In `DESCRIPTION`, add `yaml` to the `Imports:` block (alphabetical, after `tools`) and **delete it from `Suggests:`**. A package listed in both is a check NOTE.

```
Imports:
    digest,
    haven,
    hvtiRutilities,
    tools,
    utils,
    yaml
```

- [ ] **Step 4: Write the implementation**

Create `R/study_config.R`:

```r
#' Read and validate a study configuration
#'
#' Loads the `study.yaml` that declares which warehouse modules a study pulls
#' and which derivation steps it runs. The SAS templates expressed this as a
#' catalogue of optional blocks, commented in or out; this makes it an explicit,
#' diffable, committed file.
#'
#' Validation is strict by design. An unknown key is an error rather than a
#' warning, because a typo'd module name must not silently disable a module —
#' that failure mode produces a quietly incomplete dataset with no signal.
#'
#' @param path Path to a `study.yaml` file.
#'
#' @return An object of class `study_config`: a list with elements `study`,
#'   `cohort_table`, `warehouse`, `view_schema`, `pull_date` (a `Date`),
#'   `modules`, `varsets`, and `derive` (a named logical vector).
#'
#' @seealso [dw_pull()]
#'
#' @examples
#' path <- tempfile(fileext = ".yaml")
#' yaml::write_yaml(list(
#'   study = "st1234", cohort_table = "db.schema.st1234_cohort",
#'   warehouse = "warehouse", view_schema = "dbo",
#'   pull_date = "2026-08-04", modules = list("base"),
#'   varsets = list("core"), derive = list(missing = TRUE)
#' ), path)
#' read_study_config(path)
#'
#' @export
read_study_config <- function(path) {
  if (!file.exists(path)) {
    stop("Study configuration does not exist: ", path, call. = FALSE)
  }

  raw <- yaml::read_yaml(path)
  if (!is.list(raw) || is.null(names(raw))) {
    stop("Study configuration must be a YAML mapping: ", path, call. = FALSE)
  }

  required <- c("study", "cohort_table", "warehouse", "view_schema",
                "pull_date", "modules")
  optional <- c("varsets", "derive")

  unknown <- setdiff(names(raw), c(required, optional))
  if (length(unknown)) {
    stop("Unknown key(s) in study configuration: ",
         paste(unknown, collapse = ", "),
         ". Known keys are: ", paste(c(required, optional), collapse = ", "),
         ". A typo must not silently disable a step, so this is an error.",
         call. = FALSE)
  }

  missing_keys <- setdiff(required, names(raw))
  if (length(missing_keys)) {
    stop("Study configuration is missing required key(s): ",
         paste(missing_keys, collapse = ", "), ".", call. = FALSE)
  }

  for (k in c("study", "cohort_table", "warehouse", "view_schema")) {
    if (!is.character(raw[[k]]) || length(raw[[k]]) != 1L || !nzchar(raw[[k]])) {
      stop("Study configuration key '", k,
           "' must be a single non-empty string.", call. = FALSE)
    }
  }

  pull_date <- as.Date(as.character(raw$pull_date), format = "%Y-%m-%d")
  if (is.na(pull_date)) {
    stop("Study configuration key 'pull_date' must be YYYY-MM-DD, got: ",
         as.character(raw$pull_date), call. = FALSE)
  }

  cfg <- list(
    study        = raw$study,
    cohort_table = raw$cohort_table,
    warehouse    = raw$warehouse,
    view_schema  = raw$view_schema,
    pull_date    = pull_date,
    modules      = .as_character_vector(raw$modules, "modules"),
    varsets      = .as_character_vector(raw$varsets %||% list(), "varsets"),
    derive       = .as_derive_flags(raw$derive)
  )

  structure(cfg, class = "study_config")
}

#' Null-coalescing helper
#'
#' @param x,y Values; `y` is returned when `x` is `NULL`.
#'
#' @return `x` unless it is `NULL`, otherwise `y`.
#'
#' @keywords internal
#' @noRd
`%||%` <- function(x, y) if (is.null(x)) y else x

#' Coerce a YAML sequence to a character vector
#'
#' @param x Value read from YAML.
#' @param what Key name, used in the error message.
#'
#' @return A character vector, possibly of length zero.
#'
#' @keywords internal
#' @noRd
.as_character_vector <- function(x, what) {
  if (length(x) == 0L) {
    return(character(0))
  }
  out <- unlist(x, use.names = FALSE)
  if (!is.character(out)) {
    stop("Study configuration key '", what,
         "' must be a list of strings.", call. = FALSE)
  }
  out
}

#' Coerce and validate the derive block
#'
#' @param x Value read from YAML; may be `NULL`.
#'
#' @return A named logical vector, possibly of length zero.
#'
#' @keywords internal
#' @noRd
.as_derive_flags <- function(x) {
  if (is.null(x) || length(x) == 0L) {
    return(stats::setNames(logical(0), character(0)))
  }
  if (is.null(names(x)) || any(!nzchar(names(x)))) {
    stop("Study configuration key 'derive' must be a mapping of ",
         "name: true/false.", call. = FALSE)
  }
  for (k in names(x)) {
    if (!is.logical(x[[k]]) || length(x[[k]]) != 1L) {
      stop("Study configuration key 'derive: ", k,
           "' must be logical (true or false).", call. = FALSE)
    }
  }
  vapply(x, isTRUE, logical(1))
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "study_config")'`
Expected: PASS, 6 tests.

- [ ] **Step 6: Document and check**

First add this task's newly exported topic(s) to the `Pull: Warehouse to R` section of `_pkgdown.yml` (create the section on the first task that needs it, using the YAML in the File Structure block above). pkgdown fails the build on a topic that exists but is not in the index, and the index in this repo is explicit.

```bash
Rscript -e 'devtools::document()'
Rscript -e 'lintr::lint_package()'
export PATH="/Library/TeX/texbin:$PATH" && Rscript -e 'devtools::check(cran = FALSE, manual = TRUE)'
```
Expected: no lint output, then 0 errors, 0 warnings, 0 notes.

- [ ] **Step 7: Commit**

```bash
git add DESCRIPTION NAMESPACE _pkgdown.yml R/study_config.R man/ tests/testthat/test-study_config.R
git commit -m "feat: read_study_config(), where an unknown key is an error"
```

---

### Task 2: Credential ladder

**Files:**
- Create: `R/dw_credentials.R`
- Create: `tests/testthat/test-dw_credentials.R`

**Interfaces:**
- Consumes: nothing.
- Produces: `.resolve_credentials(dsn = NULL, interactive_ok = interactive())` → list with `method` (one of `"kerberos"`, `"dsn"`, `"renviron"`, `"keyring"`, `"prompt"`), and, for the `renviron` and `keyring` methods only, `uid` and `pwd`. **The `dsn` and `kerberos` methods deliberately carry no secret** — the driver holds it. Also produces `.check_file_mode(path)` and `.warn_renviron_shadow()`. Task 3 consumes all three.

This task builds the ladder as pure functions with no database involved, so the security properties are testable without DBI. Ladder order is fixed by the spec: Kerberos, named DSN, `.Renviron`, `keyring`, interactive prompt.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-dw_credentials.R`:

```r
test_that("a credential file more permissive than 600 is an error", {
  path <- withr::local_tempfile()
  writeLines("HVI_DW_UID=someone", path)
  Sys.chmod(path, "644")
  skip_if(file.mode(path) != as.octmode("644"), "Filesystem ignored chmod.")

  expect_error(.check_file_mode(path), "600")
})

test_that("a credential file at 600 passes", {
  path <- withr::local_tempfile()
  writeLines("HVI_DW_UID=someone", path)
  Sys.chmod(path, "600")

  expect_silent(.check_file_mode(path))
})

test_that("the error for a loose file never shows the file's contents", {
  path <- withr::local_tempfile()
  writeLines("HVI_DW_PWD=hunter2", path)
  Sys.chmod(path, "644")
  skip_if(file.mode(path) != as.octmode("644"), "Filesystem ignored chmod.")

  msg <- tryCatch(.check_file_mode(path), error = conditionMessage)
  expect_false(grepl("hunter2", msg, fixed = TRUE))
})

test_that("a named DSN outranks .Renviron and carries no secret", {
  withr::local_envvar(c(HVI_DW_UID = "someone", HVI_DW_PWD = "hunter2"))

  res <- .resolve_credentials(dsn = "HVI_DW", interactive_ok = FALSE)

  expect_identical(res$method, "dsn")
  expect_null(res$pwd)
})

test_that(".Renviron variables are used when no DSN is given", {
  withr::local_envvar(c(HVI_DW_UID = "someone", HVI_DW_PWD = "hunter2"))

  res <- .resolve_credentials(dsn = NULL, interactive_ok = FALSE)

  expect_identical(res$method, "renviron")
  expect_identical(res$uid, "someone")
})

test_that("no resolvable source in a non-interactive session is an error", {
  withr::local_envvar(c(HVI_DW_UID = NA, HVI_DW_PWD = NA))

  expect_error(
    .resolve_credentials(dsn = NULL, interactive_ok = FALSE),
    "No credential source"
  )
})

test_that("a project-level .Renviron shadowing the user one warns with both paths", {
  proj <- withr::local_tempdir()
  writeLines("HVI_DW_UID=someone", file.path(proj, ".Renviron"))
  withr::local_dir(proj)

  expect_warning(.warn_renviron_shadow(home = "/home/someone"),
                 "shadow")
})

test_that("no shadow warning fires when there is no project .Renviron", {
  proj <- withr::local_tempdir()
  withr::local_dir(proj)

  expect_silent(.warn_renviron_shadow(home = "/home/someone"))
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Rscript -e 'devtools::test(filter = "dw_credentials")'`
Expected: FAIL — `could not find function ".check_file_mode"`.

- [ ] **Step 3: Write the implementation**

Create `R/dw_credentials.R`:

```r
#' Resolve warehouse credentials
#'
#' Walks the credential ladder and stops at the first resolvable source. The
#' order is deliberate and is fixed by the design spec:
#'
#' 1. Kerberos integrated authentication — no stored secret at all.
#' 2. A named ODBC DSN, where the *driver* holds the credentials.
#' 3. `HVI_DW_UID` / `HVI_DW_PWD` from `~/.Renviron`.
#' 4. `keyring`, if configured. Documented, not default: it assumes a Secret
#'    Service daemon that a headless server does not provide.
#' 5. An interactive prompt.
#'
#' A DSN outranks `.Renviron` because `.Renviron` places the password in the R
#' process environment, where `Sys.getenv()` prints it and any handler that
#' dumps the environment on error captures it. A DSN password is read by the
#' driver and never enters R's memory. `Sys.getenv()` cannot leak what it never
#' held.
#'
#' @param dsn Optional name of an ODBC DSN in `~/.odbc.ini`.
#' @param interactive_ok Whether prompting is permitted.
#'
#' @return A list with element `method`, and for the `renviron` and `keyring`
#'   methods, `uid` and `pwd`. The `kerberos` and `dsn` methods carry no secret.
#'
#' @keywords internal
#' @noRd
.resolve_credentials <- function(dsn = NULL, interactive_ok = interactive()) {
  if (isTRUE(as.logical(Sys.getenv("HVI_DW_KERBEROS", "false")))) {
    return(list(method = "kerberos"))
  }

  if (!is.null(dsn) && nzchar(dsn)) {
    odbc_ini <- path.expand("~/.odbc.ini")
    if (file.exists(odbc_ini)) {
      .check_file_mode(odbc_ini)
    }
    return(list(method = "dsn", dsn = dsn))
  }

  uid <- Sys.getenv("HVI_DW_UID", unset = "")
  pwd <- Sys.getenv("HVI_DW_PWD", unset = "")
  if (nzchar(uid) && nzchar(pwd)) {
    renviron <- path.expand("~/.Renviron")
    if (file.exists(renviron)) {
      .check_file_mode(renviron)
    }
    return(list(method = "renviron", uid = uid, pwd = pwd))
  }

  if (requireNamespace("keyring", quietly = TRUE) && nzchar(uid)) {
    pwd <- tryCatch(keyring::key_get("hvti_dw", username = uid),
                    error = function(e) "")
    if (nzchar(pwd)) {
      return(list(method = "keyring", uid = uid, pwd = pwd))
    }
  }

  if (isTRUE(interactive_ok)) {
    return(list(method = "prompt"))
  }

  stop("No credential source resolved. Configure one of: a named ODBC DSN ",
       "in ~/.odbc.ini, or HVI_DW_UID and HVI_DW_PWD in ~/.Renviron ",
       "(mode 600). Note that .Renviron is read only at session start, so ",
       "restart R after editing it.", call. = FALSE)
}

#' Refuse a credential file more permissive than 600
#'
#' @param path Path to a credential-bearing file.
#'
#' @return `NULL`, invisibly. Called for the error it raises.
#'
#' @keywords internal
#' @noRd
.check_file_mode <- function(path) {
  mode <- file.mode(path)
  # Any bit set outside owner read/write is too permissive.
  if (bitwAnd(as.integer(mode), as.integer(as.octmode("077"))) != 0L) {
    stop("Credential file is more permissive than 600: ", path,
         " (currently ", format(as.octmode(mode)), "). ",
         "Fix it with: chmod 600 ", path, call. = FALSE)
  }
  invisible(NULL)
}

#' Warn when a project-level .Renviron shadows the user-level one
#'
#' R reads exactly one user `.Renviron`, and a project-level file *overrides*
#' the home one rather than merging with it. A stray `.Renviron` in a study
#' repository therefore silently hides `~/.Renviron`, and the failure presents
#' as "my credentials vanished" rather than as a shadowed file.
#'
#' @param home Home directory to report in the warning.
#'
#' @return `NULL`, invisibly. Called for the warning it raises.
#'
#' @keywords internal
#' @noRd
.warn_renviron_shadow <- function(home = path.expand("~")) {
  project <- file.path(getwd(), ".Renviron")
  if (!file.exists(project)) {
    return(invisible(NULL))
  }
  warning("A project-level .Renviron is shadowing the user-level one. ",
          "R reads only one: ", project, " overrides ",
          file.path(home, ".Renviron"),
          ". If credentials appear to be missing, this is why.",
          call. = FALSE)
  invisible(NULL)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "dw_credentials")'`
Expected: PASS, 8 tests.

- [ ] **Step 5: Check**

```bash
Rscript -e 'lintr::lint_package()'
export PATH="/Library/TeX/texbin:$PATH" && Rscript -e 'devtools::check(cran = FALSE, manual = TRUE)'
```
Expected: no lint output, then 0/0/0.

- [ ] **Step 6: Commit**

```bash
git add R/dw_credentials.R tests/testthat/test-dw_credentials.R
git commit -m "feat: credential ladder, where a loose file mode is an error"
```

---

### Task 3: `dw_connect()`

**Files:**
- Create: `R/dw_connect.R`
- Create: `tests/testthat/test-dw_connect.R`
- Modify: `DESCRIPTION` (add `DBI` to `Imports`, `odbc` to `Suggests`)

**Interfaces:**
- Consumes: `.resolve_credentials()`, `.check_file_mode()`, `.warn_renviron_shadow()` from Task 2.
- Produces: `dw_connect(server, database, dsn = NULL, port = NULL, encrypt = TRUE, trust_certificate = TRUE, ...)` → a `DBIConnection`. Also `.build_connection_args(...)` → named list of arguments destined for `DBI::dbConnect()`. Task 5 consumes the connection object only.

**Driver 18 note, load-bearing.** Microsoft flipped the `Encrypt` default from `no` (driver 17) to `yes` (driver 18). A connection string that worked under the older driver fails with a certificate error under 18 unless it sets `Encrypt=no` or trusts the server certificate. The legacy SAS `CONNECT TO ODBC` string carries `TrustServerCertificate=Yes` — added in 2022 when the group moved SAS servers. **That setting is why the pull works and must survive into `dw_connect()`.** It is therefore the default here, with an argument to turn it off, not a hardcoded constant.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-dw_connect.R`:

```r
test_that("connection arguments carry TrustServerCertificate by default", {
  withr::local_envvar(c(HVI_DW_UID = "someone", HVI_DW_PWD = "hunter2"))

  args <- .build_connection_args(
    server = "<DW-SERVER>", database = "<DW-DB>", port = 1433L
  )

  expect_identical(args$TrustServerCertificate, "Yes")
  expect_identical(args$Encrypt, "yes")
})

test_that("trust_certificate = FALSE is honoured", {
  withr::local_envvar(c(HVI_DW_UID = "someone", HVI_DW_PWD = "hunter2"))

  args <- .build_connection_args(
    server = "<DW-SERVER>", database = "<DW-DB>",
    trust_certificate = FALSE
  )

  expect_identical(args$TrustServerCertificate, "No")
})

test_that("a DSN connection carries no uid or pwd argument", {
  args <- .build_connection_args(
    server = "<DW-SERVER>", database = "<DW-DB>", dsn = "HVI_DW"
  )

  expect_identical(args$dsn, "HVI_DW")
  expect_null(args$uid)
  expect_null(args$pwd)
})

test_that("printing the argument list never reveals the password", {
  withr::local_envvar(c(HVI_DW_UID = "someone", HVI_DW_PWD = "hunter2"))

  args <- .build_connection_args(server = "<DW-SERVER>", database = "<DW-DB>")
  shown <- paste(utils::capture.output(print(.redact(args))), collapse = "\n")

  expect_false(grepl("hunter2", shown, fixed = TRUE))
  expect_true(grepl("<redacted>", shown, fixed = TRUE))
})

test_that("dw_connect() errors without odbc rather than failing obscurely", {
  skip_if(requireNamespace("odbc", quietly = TRUE), "odbc is installed.")

  expect_error(
    dw_connect(server = "<DW-SERVER>", database = "<DW-DB>", dsn = "HVI_DW"),
    "odbc"
  )
})

test_that("dw_connect() passes assembled arguments to DBI::dbConnect", {
  skip_if_not_installed("odbc")
  seen <- NULL
  testthat::local_mocked_bindings(
    dbConnect = function(drv, ...) {
      seen <<- list(...)
      structure(list(), class = "FakeConnection")
    },
    .package = "DBI"
  )

  conn <- dw_connect(server = "<DW-SERVER>", database = "<DW-DB>",
                     dsn = "HVI_DW")

  expect_s3_class(conn, "FakeConnection")
  expect_identical(seen$TrustServerCertificate, "Yes")
})

test_that("a failed connection message never contains the password", {
  skip_if_not_installed("odbc")
  withr::local_envvar(c(HVI_DW_UID = "someone", HVI_DW_PWD = "hunter2"))
  # The stub must embed the password, the way a real driver quoting the
  # connection string back would. A mock whose message cannot contain the
  # secret makes this test pass with the tryCatch wrapper deleted -- it
  # would assert nothing, on the one property that matters most here.
  testthat::local_mocked_bindings(
    dbConnect = function(drv, ...) {
      stop("login failed; connection string was 'UID=someone;PWD=hunter2'")
    },
    .package = "DBI"
  )

  msg <- tryCatch(
    dw_connect(server = "<DW-SERVER>", database = "<DW-DB>"),
    error = conditionMessage
  )

  expect_false(grepl("hunter2", msg, fixed = TRUE))
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Rscript -e 'devtools::test(filter = "dw_connect")'`
Expected: FAIL — `could not find function ".build_connection_args"`.

- [ ] **Step 3: Add DBI and odbc to DESCRIPTION**

Add `DBI` to `Imports:` (alphabetically first) and `odbc` to `Suggests:`:

```
Imports:
    DBI,
    digest,
    haven,
    hvtiRutilities,
    tools,
    utils,
    yaml
Suggests:
    arrow,
    dplyr,
    knitr,
    odbc,
    quarto,
    testthat (>= 3.0.0),
    withr
```

- [ ] **Step 4: Write the implementation**

Create `R/dw_connect.R`:

```r
#' Open a connection to the data warehouse
#'
#' Resolves credentials through the ladder documented in the design spec and
#' opens an ODBC connection. Credentials never appear in a function argument,
#' a configuration file, a log line, or an error message, and the connection
#' string is never echoed.
#'
#' `trust_certificate` defaults to `TRUE` for a specific reason. Microsoft
#' changed the `Encrypt` default from `no` in *ODBC Driver 17 for SQL Server*
#' to `yes` in driver 18. A connection string that worked under the older
#' driver fails with a certificate error under 18 unless it either disables
#' encryption or trusts the server certificate. The legacy SAS connection
#' carried `TrustServerCertificate=Yes`, which is why the pull works today.
#' Whether trusting the certificate is the right long-term posture, versus
#' installing the institutional CA chain, is a question for whoever
#' administers the DSN — but changing it silently would break every pull.
#'
#' @param server Warehouse host name.
#' @param database Database name.
#' @param dsn Optional named ODBC DSN. When supplied, the driver holds the
#'   credentials and none enters R's memory.
#' @param port Optional port number.
#' @param encrypt Whether to request an encrypted connection.
#' @param trust_certificate Whether to trust the server certificate without
#'   validating it against a CA chain.
#' @param ... Further arguments passed to [DBI::dbConnect()].
#'
#' @return A [DBI::DBIConnection-class] object.
#'
#' @seealso [dw_pull()]
#'
#' @examples
#' \donttest{
#' if (requireNamespace("odbc", quietly = TRUE)) {
#'   # Requires a configured DSN and warehouse access; not run in checks.
#'   # conn <- dw_connect(server = "<DW-SERVER>", database = "<DW-DB>",
#'   #                    dsn = "HVI_DW")
#' }
#' }
#'
#' @export
dw_connect <- function(server, database, dsn = NULL, port = NULL,
                       encrypt = TRUE, trust_certificate = TRUE, ...) {
  if (!requireNamespace("odbc", quietly = TRUE)) {
    stop("Package 'odbc' is required to connect to the warehouse. ",
         "Install it with install.packages('odbc').", call. = FALSE)
  }

  .warn_renviron_shadow()

  args <- .build_connection_args(
    server = server, database = database, dsn = dsn, port = port,
    encrypt = encrypt, trust_certificate = trust_certificate
  )

  # tryCatch, not a bare call: a driver error can quote the connection string
  # back at us, and that string may hold a password.
  tryCatch(
    do.call(DBI::dbConnect, c(list(odbc::odbc()), args, list(...))),
    error = function(e) {
      stop("Could not connect to the warehouse. The driver reported a ",
           "failure; the connection string is not shown because it may ",
           "carry a credential. Check the DSN, server, and database.",
           call. = FALSE)
    }
  )
}

#' Assemble DBI connection arguments
#'
#' @inheritParams dw_connect
#'
#' @return A named list of arguments for [DBI::dbConnect()].
#'
#' @keywords internal
#' @noRd
.build_connection_args <- function(server, database, dsn = NULL, port = NULL,
                                   encrypt = TRUE,
                                   trust_certificate = TRUE) {
  cred <- .resolve_credentials(dsn = dsn, interactive_ok = FALSE)

  args <- list(
    Driver                 = "ODBC Driver 18 for SQL Server",
    Server                 = server,
    Database               = database,
    Encrypt                = if (isTRUE(encrypt)) "yes" else "no",
    TrustServerCertificate = if (isTRUE(trust_certificate)) "Yes" else "No"
  )

  if (!is.null(port)) {
    args$Port <- as.integer(port)
  }

  switch(
    cred$method,
    dsn      = { args$dsn <- cred$dsn },
    kerberos = { args$Trusted_Connection <- "yes" },
    {
      args$uid <- cred$uid
      args$pwd <- cred$pwd
    }
  )

  args
}

#' Redact credential-bearing elements for display
#'
#' @param args Named list of connection arguments.
#'
#' @return The list with `uid` and `pwd` replaced by `"<redacted>"`.
#'
#' @keywords internal
#' @noRd
.redact <- function(args) {
  for (k in intersect(names(args), c("uid", "pwd", "UID", "PWD"))) {
    args[[k]] <- "<redacted>"
  }
  args
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "dw_connect")'`
Expected: PASS, 7 tests.

- [ ] **Step 6: Document and check**

First add this task's newly exported topic(s) to the `Pull: Warehouse to R` section of `_pkgdown.yml` (create the section on the first task that needs it, using the YAML in the File Structure block above). pkgdown fails the build on a topic that exists but is not in the index, and the index in this repo is explicit.

```bash
Rscript -e 'devtools::document()'
Rscript -e 'lintr::lint_package()'
export PATH="/Library/TeX/texbin:$PATH" && Rscript -e 'devtools::check(cran = FALSE, manual = TRUE)'
```
Expected: no lint output, then 0/0/0.

- [ ] **Step 7: Commit**

```bash
git add DESCRIPTION NAMESPACE _pkgdown.yml R/dw_connect.R man/ tests/testthat/test-dw_connect.R
git commit -m "feat: dw_connect(), carrying the driver-18 certificate setting forward"
```

---

### Task 4: Module definitions as data

**Files:**
- Create: `inst/extdata/modules/base.yaml`
- Create: `inst/extdata/modules/vitalstatus.yaml`
- Create: `inst/extdata/modules/echo.yaml`
- Create: `inst/extdata/modules/fup.yaml`
- Create: `inst/extdata/modules/events.yaml`
- Create: `R/dw_modules.R`
- Create: `tests/testthat/test-dw_modules.R`

**Interfaces:**
- Consumes: `study_config` from Task 1.
- Produces: `dw_modules()` → data frame with columns `module`, `output`, `join_key`, `optional`; and `.module_sql(module, config)` → a single SQL string with all placeholders interpolated. Task 5 consumes both.

**Why data, not code.** These definitions change independently of the code that runs them, they carry provenance, and holding them outside R source is what keeps site-specific identifiers out of the repository. The files ship with placeholder tokens (`{warehouse}`, `{view_schema}`, `{cohort}`); real values arrive from `study.yaml` at runtime and are never committed.

The five modules mirror the five permanent datasets that `tp.stXXXX_dwpull.sas` writes: `bdbase_*`, `bdstat_*`, `stXXXX_echo`, `stXXXX_fup`, and `bdevents_*`. The sixth block in the SAS file (`stXXXX_addtl`, the cardiac-cath pull) is a worked *example* of pulling arbitrary columns, not a standard module, and is deliberately not ported here.

- [ ] **Step 1: Write the module data files**

Create `inst/extdata/modules/base.yaml`:

```yaml
module: base
output: bdbase
join_key: masterid
optional: false
description: >
  Cohort joined to the CardSurg Base, Valve, and Cabg views. Ports the first
  PROC SQL block of tp.stXXXX_dwpull.sas.
sql: >
  select c.*, s.*, v.*, w.*
  from {cohort} c
  inner join {warehouse}.{view_schema}.vw_CardSurg_Base  s on c.masterid = s.masterid
  inner join {warehouse}.{view_schema}.vw_CardSurg_Valve v on c.masterid = v.masterid
  inner join {warehouse}.{view_schema}.vw_CardSurg_Cabg  w on c.masterid = w.masterid
```

Create `inst/extdata/modules/vitalstatus.yaml`:

```yaml
module: vitalstatus
output: bdstat
join_key: masterid
optional: false
description: >
  Vital-status columns only, from the CardSurg Base view. Ports the second
  PROC SQL block of tp.stXXXX_dwpull.sas. The column list is explicit in SAS
  and stays explicit here.
divergence: >
  The SAS source selects `masterid` twice: once from the cohort (c.masterid)
  and once from the view (s.masterid). The two are equal by construction —
  the join is `on c.masterid = s.masterid` — so no information is lost
  either way. SAS PROC SQL pass-through and R's DBI::dbGetQuery() do not
  resolve a duplicated result-column name the same way: SAS typically
  suffixes the second occurrence, while R may return duplicate names, mangle
  them (e.g. via make.unique/check.names), or behave driver-dependently.
  This port keeps s.masterid in the SQL to stay literally faithful to the
  SAS source, but the actual name the oracle assigns to the second masterid
  column is unknown until the Task 6 equivalence run against a real study
  resolves it. Whoever runs that comparison should look for a second
  masterid-like column (e.g. masterid.1, masterid_1, or a SAS-generated
  suffix) in the oracle output, confirm it is value-identical to c.masterid,
  and record the resolved name in equivalence_signoff.yaml. No rename or
  dedup rule is applied here — that would guess at an answer only the real
  oracle can settle.
sql: >
  select c.masterid, s.patid, s.masterid, s.dtn_inst,
         s.dt_vstat, s.vit_stat, s.vit_src, s.vstatiss, s.mtdate,
         s.hdeath, s.dt_dthep, s.dt_alive, s.dead30d
  from {cohort} c
  inner join {warehouse}.{view_schema}.vw_CardSurg_Base s on c.masterid = s.masterid
```

**Duplicate `masterid` column.** The SAS select list above names `masterid`
twice — `c.masterid` and `s.masterid` — because it is transcribed verbatim
from `tp.stXXXX_dwpull.sas` lines 88–92. An earlier draft of this task
dropped the second occurrence as apparently redundant; that silently
diverges from the SAS-built oracle, which `compare_built()` would report as
`absent_in_r`. The two masterid values are equal by construction (the join
predicate is `c.masterid = s.masterid`), but SAS and R do not name a
duplicated result column the same way, and this repository has no real
oracle to check against. The `divergence:` field in `vitalstatus.yaml`
records the open question for the Task 6 equivalence run rather than
guessing at a rename or dedup rule.

Create `inst/extdata/modules/echo.yaml`:

```yaml
module: echo
output: echo
join_key: patid
optional: true
description: >
  Echocardiography records for the cohort. Ports the third PROC SQL block of
  tp.stXXXX_dwpull.sas.
divergence: >
  The SAS window reads
  `where (datediff(day, e.dtn_echo, c.dtn_inst) <= 180 or
          datediff(day, c.dtn_inst, e.dtn_echo) >= 0)`.
  The second disjunct is a strict subset of the first, so under OR it is dead
  code, and the effective filter is "echo no more than 180 days before
  surgery" with no upper bound after surgery. Whether that was the intent is
  unresolved. This port reproduces the SAS behaviour exactly so that S1
  equivalence is measurable; the question is recorded in
  equivalence_signoff.yaml for a human decision, not silently corrected here.
sql: >
  select c.patid, c.dtn_inst, c.mrn, e.*
  from {cohort} c
  inner join {warehouse}.{view_schema}.vw_Echo_Base e on e.patid = c.patid
  where (datediff(day, e.dtn_echo, c.dtn_inst) <= 180
         or datediff(day, c.dtn_inst, e.dtn_echo) >= 0)
  order by c.mrn, c.dtn_inst
```

Create `inst/extdata/modules/fup.yaml`:

```yaml
module: fup
output: fup
join_key: patid
optional: false
description: >
  Follow-up records for the cohort. Ports the fourth PROC SQL block of
  tp.stXXXX_dwpull.sas. Note that the cohort's dtn_surg is aliased to
  dtn_inst, matching SAS.
sql: >
  select c.patid, c.masterid, c.mrn, c.dtn_surg dtn_inst, s.*
  from {cohort} c
  inner join {warehouse}.{view_schema}.vw_FUP_Base s on c.patid = s.patid
```

Create `inst/extdata/modules/events.yaml`:

```yaml
module: events
output: bdevents
join_key: patid
optional: true
description: >
  Reoperation events — CardSurg Base records occurring strictly after the
  index operation, with sp_ columns renamed to rp_. Ports the fifth PROC SQL
  block of tp.stXXXX_dwpull.sas. The commented-out columns in the SAS source
  (sp_vadio, sp_nocar, sp_ocard) are omitted here, matching SAS.
sql: >
  select c.mrn, c.dtn_inst, c.patid,
         s.dtn_inst dtn_evst,
         s.sp_cabg  rp_cabg,
         s.sp_valve rp_valve,
         s.sp_avrpl rp_avrpl,
         s.sp_avrpr rp_avrpr,
         s.sp_mvrpl rp_mvrpl,
         s.sp_mvrpr rp_mvrpr,
         s.sp_tvrpl rp_tvrpl,
         s.sp_tvrpr rp_tvrpr,
         s.sp_tx    rp_tx,
         s.sp_aorta rp_aorta,
         s.sp_aotic rp_aotic,
         s.sp_dscao rp_dscao
  from {cohort} c
  inner join {warehouse}.{view_schema}.vw_CardSurg_Base s
    on c.patid = s.patid and c.dtn_inst < s.dtn_inst
```

- [ ] **Step 2: Write the failing test**

Create `tests/testthat/test-dw_modules.R`:

```r
.test_config <- function(modules = c("base", "fup")) {
  structure(list(
    study = "st1234", cohort_table = "db.sch.st1234_cohort",
    warehouse = "wh", view_schema = "dbo",
    pull_date = as.Date("2026-08-04"), modules = modules,
    varsets = character(0), derive = stats::setNames(logical(0), character(0))
  ), class = "study_config")
}

test_that("every shipped module file parses and declares the required fields", {
  mods <- dw_modules()

  expect_true(nrow(mods) >= 5L)
  expect_setequal(
    names(mods), c("module", "output", "join_key", "optional")
  )
  expect_true(all(nzchar(mods$module)))
  expect_type(mods$optional, "logical")
  expect_false(anyDuplicated(mods$module) > 0)
})

test_that("the five dwpull modules are present", {
  expect_true(all(c("base", "vitalstatus", "echo", "fup", "events") %in%
                    dw_modules()$module))
})

test_that("SQL interpolation replaces every placeholder", {
  sql <- .module_sql("base", .test_config())

  expect_false(grepl("\\{", sql))
  expect_true(grepl("db.sch.st1234_cohort", sql, fixed = TRUE))
  expect_true(grepl("wh.dbo.vw_CardSurg_Base", sql, fixed = TRUE))
})

test_that("no shipped module file carries a site-specific identifier", {
  # The repository is public. Real host, port, database, and schema names
  # arrive from study.yaml at runtime and must never be committed.
  files <- list.files(
    system.file("extdata", "modules", package = "hvtiRdatasets"),
    full.names = TRUE
  )
  text <- paste(unlist(lapply(files, readLines)), collapse = "\n")

  expect_false(grepl("\\.cchs\\.net|ESQLPROD|ESQLPLDAG|HVI_DM", text))
})

test_that("an unknown module name is an error naming the known ones", {
  expect_error(.module_sql("nonsuch", .test_config()), "base")
})

test_that("the echo module records the SAS window as a known divergence", {
  path <- system.file("extdata", "modules", "echo.yaml",
                      package = "hvtiRdatasets")
  spec <- yaml::read_yaml(path)

  expect_true(nzchar(spec$divergence))
})
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `Rscript -e 'devtools::test(filter = "dw_modules")'`
Expected: FAIL — `could not find function "dw_modules"`.

- [ ] **Step 4: Write the implementation**

Create `R/dw_modules.R`:

```r
#' List the available warehouse modules
#'
#' Module definitions ship as data under `inst/extdata/modules/`, one YAML
#' file per module, rather than as R code. They change independently of the
#' code that executes them, they carry a description of the SAS block each one
#' ports, and holding them outside R source is what keeps site-specific
#' identifiers out of this repository — the SQL ships with placeholders and
#' the real warehouse, schema, and cohort names arrive from `study.yaml` at
#' run time.
#'
#' @return A data frame with one row per module and columns `module`,
#'   `output`, `join_key`, and `optional`.
#'
#' @seealso [dw_pull()]
#'
#' @examples
#' dw_modules()
#'
#' @export
dw_modules <- function() {
  specs <- .read_module_specs()
  data.frame(
    module   = vapply(specs, function(s) s$module,   character(1)),
    output   = vapply(specs, function(s) s$output,   character(1)),
    join_key = vapply(specs, function(s) s$join_key, character(1)),
    optional = vapply(specs, function(s) isTRUE(s$optional), logical(1)),
    stringsAsFactors = FALSE
  )
}

#' Read every shipped module specification
#'
#' @return A named list of module specifications.
#'
#' @keywords internal
#' @noRd
.read_module_specs <- function() {
  dir <- system.file("extdata", "modules", package = "hvtiRdatasets")
  files <- list.files(dir, pattern = "\\.yaml$", full.names = TRUE)
  if (length(files) == 0L) {
    stop("No module definitions found in ", dir,
         ". The package installation is incomplete.", call. = FALSE)
  }
  specs <- lapply(files, yaml::read_yaml)
  required <- c("module", "output", "join_key", "sql")
  for (i in seq_along(specs)) {
    missing_fields <- setdiff(required, names(specs[[i]]))
    if (length(missing_fields)) {
      stop("Module definition ", basename(files[i]),
           " is missing field(s): ",
           paste(missing_fields, collapse = ", "), ".", call. = FALSE)
    }
  }
  stats::setNames(specs, vapply(specs, function(s) s$module, character(1)))
}

#' Build the SQL for one module
#'
#' @param module Module name, one of [dw_modules()]`$module`.
#' @param config A `study_config` from [read_study_config()].
#'
#' @return A single SQL string with every placeholder interpolated.
#'
#' @keywords internal
#' @noRd
.module_sql <- function(module, config) {
  specs <- .read_module_specs()
  if (!module %in% names(specs)) {
    stop("Unknown module '", module, "'. Known modules are: ",
         paste(names(specs), collapse = ", "), ".", call. = FALSE)
  }
  sql <- specs[[module]]$sql

  replacements <- c(
    "{cohort}"      = config$cohort_table,
    "{warehouse}"   = config$warehouse,
    "{view_schema}" = config$view_schema
  )
  for (token in names(replacements)) {
    sql <- gsub(token, replacements[[token]], sql, fixed = TRUE)
  }

  leftover <- regmatches(sql, gregexpr("\\{[^}]*\\}", sql))[[1]]
  if (length(leftover)) {
    stop("Module '", module, "' has uninterpolated placeholder(s): ",
         paste(unique(leftover), collapse = ", "), ".", call. = FALSE)
  }

  trimws(sql)
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "dw_modules")'`
Expected: PASS, 6 tests.

- [ ] **Step 6: Document and check**

First add this task's newly exported topic(s) to the `Pull: Warehouse to R` section of `_pkgdown.yml` (create the section on the first task that needs it, using the YAML in the File Structure block above). pkgdown fails the build on a topic that exists but is not in the index, and the index in this repo is explicit.

```bash
Rscript -e 'devtools::document()'
Rscript -e 'lintr::lint_package()'
export PATH="/Library/TeX/texbin:$PATH" && Rscript -e 'devtools::check(cran = FALSE, manual = TRUE)'
```
Expected: no lint output, then 0/0/0.

- [ ] **Step 7: Commit**

```bash
git add NAMESPACE _pkgdown.yml R/dw_modules.R inst/extdata/modules/ man/ tests/testthat/test-dw_modules.R
git commit -m "feat: warehouse modules as data, with the echo window logged as a divergence"
```

---

### Task 5: `dw_pull()` and the pull manifest

**Files:**
- Create: `R/dw_pull.R`
- Create: `tests/testthat/test-dw_pull.R`

**Interfaces:**
- Consumes: `read_study_config()` (Task 1), `dw_connect()` (Task 3), `dw_modules()` and `.module_sql()` (Task 4).
- Produces: `dw_pull(config, conn)` → object of class `pull_result`: a named list with element `tables` (named list of data frames, one per enabled module, named by the module's `output`) and element `manifest` (a data frame with columns `module`, `output`, `n_rows`, `n_cols`, `pulled_at`). Task 6 consumes `$tables`.

**The pull manifest is provenance, not a checksum registry.** It is returned as a data frame and nothing is written to disk. `hvtiRutilities::update_manifest()` is deliberately **not** called here: it begins with `if (!file.exists(file)) stop(...)` and takes a SHA-256 of that file, so it only makes sense for something that exists on disk. `dw_pull()` returns in-memory tables. `snapshot_oracle()` remains the one place this package uses `update_manifest()`, because a parquet oracle *is* a file. Decision taken by the maintainer 2026-08-06.

**Read-only.** `dw_pull()` executes `SELECT` statements and nothing else. The cohort write-back in the SAS templates is deferred to a later slice by an explicit scope decision.

**Zero rows is an error unless declared optional** (spec § Error handling). An empty module silently producing an empty table is the failure mode that yields a quietly incomplete dataset.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-dw_pull.R`:

```r
.pull_config <- function(modules = c("base", "fup")) {
  structure(list(
    study = "st1234", cohort_table = "db.sch.st1234_cohort",
    warehouse = "wh", view_schema = "dbo",
    pull_date = as.Date("2026-08-04"), modules = modules,
    varsets = character(0), derive = stats::setNames(logical(0), character(0))
  ), class = "study_config")
}

.fake_conn <- function() structure(list(), class = "FakeConnection")

# Synthetic, no PHI: two identifier-shaped columns and one measurement.
.fake_rows <- function(n = 3L) {
  data.frame(
    masterid = seq_len(n),
    patid    = seq_len(n) + 100L,
    value    = seq_len(n) * 1.5
  )
}

test_that("dw_pull() returns one table per enabled module, named by output", {
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) .fake_rows(),
    .package = "DBI"
  )

  res <- dw_pull(.pull_config(), .fake_conn())

  expect_s3_class(res, "pull_result")
  expect_setequal(names(res$tables), c("bdbase", "fup"))
  expect_identical(nrow(res$tables$bdbase), 3L)
})

test_that("the manifest records shape for every module pulled", {
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) .fake_rows(),
    .package = "DBI"
  )

  res <- dw_pull(.pull_config(), .fake_conn())

  expect_setequal(
    names(res$manifest),
    c("module", "output", "n_rows", "n_cols", "pulled_at")
  )
  expect_identical(nrow(res$manifest), 2L)
  expect_true(all(res$manifest$n_rows == 3L))
})

test_that("a required module returning zero rows is an error", {
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) .fake_rows(0L),
    .package = "DBI"
  )

  expect_error(dw_pull(.pull_config("base"), .fake_conn()),
               "zero rows")
})

test_that("an optional module returning zero rows is kept, not an error", {
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) .fake_rows(0L),
    .package = "DBI"
  )

  res <- dw_pull(.pull_config("echo"), .fake_conn())

  expect_identical(nrow(res$tables$echo), 0L)
  expect_identical(res$manifest$n_rows, 0L)
})

test_that("an unknown module in the config is an error before any query runs", {
  queried <- FALSE
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      queried <<- TRUE
      .fake_rows()
    },
    .package = "DBI"
  )

  expect_error(dw_pull(.pull_config("nonsuch"), .fake_conn()), "nonsuch")
  expect_false(queried)
})

test_that("dw_pull() issues only SELECT statements", {
  seen <- character(0)
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      seen <<- c(seen, statement)
      .fake_rows()
    },
    .package = "DBI"
  )

  dw_pull(.pull_config(c("base", "vitalstatus", "fup")), .fake_conn())

  expect_true(all(grepl("^select", trimws(seen), ignore.case = TRUE)))
  expect_false(any(grepl("insert|update|delete|drop|create",
                         seen, ignore.case = TRUE)))
})

test_that("a query failure names the module and not the SQL", {
  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) stop("driver exploded"),
    .package = "DBI"
  )

  msg <- tryCatch(dw_pull(.pull_config("base"), .fake_conn()),
                  error = conditionMessage)

  expect_match(msg, "base")
  expect_false(grepl("vw_CardSurg", msg, fixed = TRUE))
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Rscript -e 'devtools::test(filter = "dw_pull")'`
Expected: FAIL — `could not find function "dw_pull"`.

- [ ] **Step 3: Write the implementation**

Create `R/dw_pull.R`:

```r
#' Pull the enabled warehouse modules for a study
#'
#' Executes one query per module named in the study configuration and returns
#' the raw tables alongside a manifest of what was pulled. This is the R port
#' of `tp.stXXXX_dwpull.sas`.
#'
#' The port is **read-only**. The SAS templates also upload a cohort table to
#' the warehouse; that write is deliberately not carried here and is deferred
#' to a later slice with its own review.
#'
#' A module that returns zero rows is an error unless its definition declares
#' it optional. A silently empty module produces a quietly incomplete dataset,
#' which is the failure this package exists to prevent.
#'
#' @param config A `study_config` from [read_study_config()].
#' @param conn A [DBI::DBIConnection-class], typically from [dw_connect()].
#'
#' @return An object of class `pull_result`: a list with `tables`, a named
#'   list of data frames keyed by each module's `output` name, and `manifest`,
#'   a data frame with columns `module`, `output`, `n_rows`, `n_cols`, and
#'   `pulled_at`.
#'
#' @seealso [dw_connect()], [dw_modules()], [compare_built()]
#'
#' @examples
#' \donttest{
#' # Requires a warehouse connection; see vignette("building-a-study-dataset")
#' # for a runnable version against a mocked connection.
#' }
#'
#' @export
dw_pull <- function(config, conn) {
  if (!inherits(config, "study_config")) {
    stop("'config' must be a study_config from read_study_config().",
         call. = FALSE)
  }

  specs <- .read_module_specs()
  unknown <- setdiff(config$modules, names(specs))
  if (length(unknown)) {
    stop("Study configuration names unknown module(s): ",
         paste(unknown, collapse = ", "), ". Known modules are: ",
         paste(names(specs), collapse = ", "),
         ". Nothing was pulled.", call. = FALSE)
  }

  pulled_at <- Sys.time()
  tables <- list()
  rows   <- list()

  for (m in config$modules) {
    spec <- specs[[m]]
    sql  <- .module_sql(m, config)

    d <- tryCatch(
      DBI::dbGetQuery(conn, sql),
      error = function(e) {
        # The SQL is withheld: it names warehouse objects, and an error
        # message is exactly the artefact that ends up pasted into a ticket.
        stop("Pull failed for module '", m,
             "'. The query was not echoed. Check warehouse access and the ",
             "cohort table named in study.yaml.", call. = FALSE)
      }
    )

    if (nrow(d) == 0L && !isTRUE(spec$optional)) {
      stop("Module '", m, "' returned zero rows and is not declared ",
           "optional. An empty required module yields a quietly incomplete ",
           "dataset. If emptiness is expected, mark the module optional.",
           call. = FALSE)
    }

    tables[[spec$output]] <- d
    rows[[length(rows) + 1L]] <- data.frame(
      module    = m,
      output    = spec$output,
      n_rows    = nrow(d),
      n_cols    = ncol(d),
      pulled_at = pulled_at,
      stringsAsFactors = FALSE
    )
  }

  man <- do.call(rbind, rows)

  structure(list(tables = tables, manifest = man), class = "pull_result")
}

#' Print a pull result
#'
#' @param x A `pull_result` from [dw_pull()].
#' @param ... Ignored.
#'
#' @return `x`, invisibly.
#'
#' @export
print.pull_result <- function(x, ...) {
  cat("Warehouse pull:", nrow(x$manifest), "module(s)\n\n")
  print(x$manifest, row.names = FALSE)
  invisible(x)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript -e 'devtools::test(filter = "dw_pull")'`
Expected: PASS, 7 tests.

- [ ] **Step 5: Document and check**

First add this task's newly exported topic(s) to the `Pull: Warehouse to R` section of `_pkgdown.yml` (create the section on the first task that needs it, using the YAML in the File Structure block above). pkgdown fails the build on a topic that exists but is not in the index, and the index in this repo is explicit.

```bash
Rscript -e 'devtools::document()'
Rscript -e 'lintr::lint_package()'
export PATH="/Library/TeX/texbin:$PATH" && Rscript -e 'devtools::check(cran = FALSE, manual = TRUE)'
```
Expected: no lint output, then 0/0/0.

- [ ] **Step 6: Commit**

```bash
git add NAMESPACE _pkgdown.yml R/dw_pull.R man/ tests/testthat/test-dw_pull.R
git commit -m "feat: dw_pull(), read-only, where an empty required module is an error"
```

---

### Task 6: Equivalence harness for pull-stage datasets

**Files:**
- Modify: `tests/testthat/test-integration-real-study.R`
- Modify: `DESCRIPTION` (version `0.1.0` → `0.1.1`)
- Modify: `README.md`

**Interfaces:**
- Consumes: `dw_pull()` output (Task 5), `snapshot_oracle()` and `compare_built()` (S0, already shipped).
- Produces: nothing consumed by later tasks. This is the slice's acceptance gate.

**What S1's oracle actually is.** `tp.stXXXX_dwpull.sas` writes permanent datasets into the study library — `bdbase_mmddyy`, `bdstat_mmddyy`, `stXXXX_echo`, `stXXXX_fup`, `bdevents_mmddyy`. These are `.sas7bdat` on disk for every completed study, so `snapshot_oracle()` and `compare_built()` apply to pull output directly. S1 does **not** need `library.built`.

**What equivalence means here.** Both the SAS reference and a fresh R pull read live warehouse views, and the reference was pulled on a fixed date. Rows accrued since then are expected. `compare_built()` already reports row-set differences separately from value differences, so the gate is: **row-set drift is expected and reported; a value difference on a shared identifier is a failure.** Do not collapse the two.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-integration-real-study.R`:

```r
# --- S1: pull-stage oracles -------------------------------------------------
# The pull writes permanent datasets alongside `built`. Each is an oracle in
# its own right, so S1 is measurable without waiting for S2.

.pull_oracles <- c("bdbase", "bdstat", "echo", "fup", "bdevents")

.find_pull_oracle <- function(dir, stem) {
  # SAS names carry a pull date (bdbase_mmddyy); match on the stem.
  hits <- list.files(dir, pattern = paste0("^", stem, ".*\\.sas7bdat$"),
                     full.names = TRUE)
  if (length(hits) == 0L) NA_character_ else sort(hits)[1]
}

test_that("each pull-stage oracle snapshots and self-compares as identical", {
  dir <- skip_unless_real_oracle()

  found <- vapply(.pull_oracles, function(s) .find_pull_oracle(dir, s),
                  character(1))
  skip_if(all(is.na(found)), "No pull-stage datasets in HVTI_ORACLE_DIR.")

  for (stem in names(found)[!is.na(found)]) {
    src <- found[[stem]]
    out <- withr::local_tempfile(fileext = ".parquet")
    info <- snapshot_oracle(src, out)

    expect_gt(info$n_rows, 0L)
    expect_match(info$sha256, "^[0-9a-f]{64}$")

    d  <- haven::read_sas(src)
    id <- if ("masterid" %in% names(d)) "masterid" else names(d)[1]
    if (anyDuplicated(d[[id]]) > 0) next

    res <- compare_built(d, d, id = id)
    offending <- sum(res$verdict != "identical")

    # Counts only. A value in a failure message would be PHI.
    expect_equal(
      offending, 0L,
      info = paste0(stem, ": ", offending,
                    " variable(s) not identical to themselves.")
    )
  }
})

test_that("row-set drift is reported apart from value differences", {
  dir <- skip_unless_real_oracle()
  src <- .find_pull_oracle(dir, "bdbase")
  skip_if(is.na(src), "No bdbase dataset in HVTI_ORACLE_DIR.")

  d  <- haven::read_sas(src)
  id <- if ("masterid" %in% names(d)) "masterid" else names(d)[1]
  skip_if(anyDuplicated(d[[id]]) > 0, "Identifier is not unique.")
  skip_if(nrow(d) < 4L, "Too few rows to split.")

  # Simulate the live-warehouse case: the R side has rows the oracle lacks.
  fewer <- d[seq_len(nrow(d) - 2L), , drop = FALSE]
  res   <- compare_built(fewer, d, id = id)

  # Every shared row still matches on value; the difference is row-set only.
  expect_equal(sum(res$verdict != "identical"), 0L)
  expect_gt(length(attr(res, "rows")$only_r), 0L)
})
```

- [ ] **Step 2: Run the test to verify it skips cleanly without real data**

Run: `Rscript -e 'devtools::test(filter = "integration-real-study")'`
Expected: All tests SKIP with "HVTI_ORACLE_DIR not set". No failures, no errors.

- [ ] **Step 3: Run the test against a real study**

This is the slice's acceptance gate and runs **on the server**, never on a laptop.

```bash
HVTI_ORACLE_DIR=/studies/<study>/datasets Rscript -e 'devtools::test(filter = "integration-real-study")'
```
Expected: PASS. If any variable is not identical to itself, that is a defect in the comparison primitives, not in the data.

> **This step needs the target study, which is the one open decision left in the slice.** The criteria: pull-stage datasets intact (`bdbase_*` at minimum), a unique `masterid`, and representative module coverage. Note this is a *weaker* requirement than an intact `library.built` — a study whose `built` was clobbered can still serve here.

- [ ] **Step 4: Bump the version**

In `DESCRIPTION`, set `Version: 0.1.1` and `Date:` to the commit date. Patch digit only — the minor digit is the maintainer's call at release time, not this plan's.

- [ ] **Step 5: Update the README**

Add `dw_connect()`, `dw_pull()`, `dw_modules()`, and `read_study_config()` to the function list, and state that the pull is read-only and that the re-pull variants (`snapshotpull`, `ccfpull`) are a later slice. Use the spec's placeholders for any infrastructure name.

- [ ] **Step 6: Check**

```bash
Rscript -e 'lintr::lint_package()'
export PATH="/Library/TeX/texbin:$PATH" && Rscript -e 'devtools::check(cran = FALSE, manual = TRUE)'
```
Expected: no lint output, then 0/0/0.

- [ ] **Step 7: Commit and open the PR**

```bash
git add DESCRIPTION README.md tests/testthat/test-integration-real-study.R
git commit -m "test: pull-stage oracles, with row-set drift reported apart from values"
git push -u origin feat/s1-pull
gh pr create --fill
```

---

## Carried forward

Recorded here so they are not re-derived. None blocks S1.

- **The cohort write-back** (`libsql` blocks in all three pull templates) is deferred. It is a prerequisite for porting `snapshotpull` and `ccfpull`, which cannot run without it.
- **`snapshotpull` and `ccfpull`** are re-pull paths that take an existing `library.built` as input and remap keys via `etl_key`, because MASTERID stopped being stable in April 2023 (`tp.stXXX_snapshotpull.sas:28`). They need their own slice after the write path exists.
- **`ccfpull` points at a different host and port** than the other two templates. Whoever defines the DSN should reconcile that; it does not affect S1, which takes the server from `study.yaml`.
- **The `stXXXX_addtl` cardiac-cath block** in `tp.stXXXX_dwpull.sas` is a worked example of an ad-hoc pull, not a standard module, and carries the same dead-`OR` window as the echo module. Not ported.
- **`use_study_dataset()` is not in this slice.** The spec lists it as a Unit and a Deliverable, and its testing table has a row for "Scaffold written by `use_study_dataset()` — `.gitignore` covers `.Renviron` and `.odbc.ini`". The slice sequence assigns S1 only the pull, so the scaffold goes with the study-template work. **This matters more than it looks:** the `.gitignore` entries are the mitigation for a project-level `.Renviron` being committed by accident, and until the scaffold ships, that hazard is covered only by the runtime warning built in Task 2. Ship the scaffold before the package reaches analysts.
- **Kerberos availability** against `<AD-DOMAIN>` is still unanswered and still deferred. The ladder has Kerberos as rung 1 with the stored-secret rungs live beneath it, so a later yes deletes rungs rather than forcing a redesign. Re-ask before S1 ships.
- **The echo window divergence** is reproduced exactly, not corrected, and is recorded in `inst/extdata/modules/echo.yaml`. It needs an `equivalence_signoff.yaml` entry with a `resolution` once a human decides whether the SAS behaviour was intended.
