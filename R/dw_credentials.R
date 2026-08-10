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
#'
#' A DSN outranks `.Renviron` because `.Renviron` places the password in the R
#' process environment, where `Sys.getenv()` prints it and any handler that
#' dumps the environment on error captures it. A DSN password is read by the
#' driver and never enters R's memory. `Sys.getenv()` cannot leak what it never
#' held.
#'
#' @param dsn Optional name of an ODBC DSN in `~/.odbc.ini`.
#'
#' @return A list with element `method`, and for the `renviron` and `keyring`
#'   methods, `uid` and `pwd`; for the `dsn` method, `dsn`. The `kerberos` and
#'   `dsn` methods carry no secret.
#'
#' @keywords internal
#' @noRd
.resolve_credentials <- function(dsn = NULL) {
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

  stop("No credential source resolved. Configure one of: set ",
       "HVI_DW_KERBEROS=true if Kerberos integrated auth is available; ",
       "pass a named ODBC DSN configured in ~/.odbc.ini (mode 600); set ",
       "HVI_DW_UID and HVI_DW_PWD in ~/.Renviron (mode 600); or configure ",
       "a 'hvti_dw' entry in keyring for the current HVI_DW_UID. Note that ",
       ".Renviron is read only at session start, so restart R after ",
       "editing it.", call. = FALSE)
}

#' Refuse a credential file more permissive than 600
#'
#' Windows has no POSIX file mode: `Sys.chmod()` there only toggles the
#' read-only attribute, so a file "chmod'd" to 600 still reports as
#' world-readable. Rather than pass a credential file that cannot actually be
#' confirmed protected, this refuses outright on a platform without POSIX
#' modes.
#'
#' @param path Path to a credential-bearing file.
#' @param os_type Platform indicator, as returned by `.Platform$OS.type`.
#'   Exposed as a parameter so the Windows branch can be exercised from a
#'   test on any platform; callers should not need to pass it.
#'
#' @return `NULL`, invisibly. Called for the error it raises.
#'
#' @keywords internal
#' @noRd
.check_file_mode <- function(path, os_type = .Platform$OS.type) {
  if (identical(os_type, "windows")) {
    stop("Cannot verify credential file permissions on Windows: this ",
         "platform has no POSIX file mode, so a credential file's ",
         "protection can never be confirmed here. hvtiRdatasets targets ",
         "the Linux server described in the design spec; file-based ",
         "credentials (a DSN or ~/.Renviron) are not supported on Windows.",
         call. = FALSE)
  }
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
