#' Open a connection to the data warehouse
#'
#' Resolves credentials through the ladder documented in the design spec and
#' opens an ODBC connection. Credentials never appear in a function argument,
#' a configuration file, a log line, or an error message, and the connection
#' string is never echoed.
#'
#' `trust_certificate` defaults to `FALSE`: the warehouse server's TLS
#' certificate is checked against the machine's CA chain, because the
#' connection carries credentials. Microsoft changed the `Encrypt` default
#' from `no` in *ODBC Driver 17 for SQL Server* to `yes` in driver 18, and the
#' legacy SAS connection carried `TrustServerCertificate=Yes`. If a connection
#' fails because the certificate does not verify, install the institutional CA
#' chain on the machine (ask whoever administers the server or the DSN). Pass
#' `trust_certificate = TRUE` only as a stop-gap: it accepts any certificate,
#' so it does not protect the credentials from an impostor server.
#'
#' Set the `HVI_DW_KERBEROS` environment variable to enable the top rung of
#' the credential ladder, Kerberos integrated authentication: no stored
#' secret is used, and the connection relies on the caller's existing ticket
#' instead. It is read with [as.logical()], which recognises `"true"`,
#' `"True"`, `"T"`, and `"TRUE"` (and their `FALSE` counterparts). Set it to
#' one of those, not `"yes"` or `"1"`, which `as.logical()` does not
#' recognise and silently reads as `NA`.
#'
#' File-based credentials (a DSN or `~/.Renviron`) are unavailable on
#' Windows: Windows has no POSIX file mode, so a credential file's
#' protection can never be confirmed there, and `dw_connect()` refuses
#' rather than trust it unverified. This package targets the Linux server
#' described in the design spec.
#'
#' @param server Warehouse host name.
#' @param database Database name.
#' @param dsn Optional named ODBC DSN. When supplied, the driver holds the
#'   credentials and none enters R's memory.
#' @param port Optional port number.
#' @param encrypt Whether to request an encrypted connection.
#' @param trust_certificate Whether to trust the server certificate without
#'   validating it against a CA chain. `FALSE`, the default, validates it.
#' @param ... Further arguments passed to [DBI::dbConnect()].
#'
#' @return A [DBI::DBIConnection-class] object.
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
                       encrypt = TRUE, trust_certificate = FALSE, ...) {
  if (!requireNamespace("odbc", quietly = TRUE)) {
    stop("Package 'odbc' is required to connect to the warehouse. ",
         "Install it with install.packages('odbc').", call. = FALSE)
  }

  .warn_renviron_shadow()

  args <- .build_connection_args(
    server = server, database = database, dsn = dsn, port = port,
    encrypt = encrypt, trust_certificate = trust_certificate
  )

  # tryCatch/withCallingHandlers, not a bare call: do.call() builds a call
  # object holding the *evaluated* argument values, so both an error and a
  # warning raised inside dbConnect() can carry uid/pwd in their
  # conditionCall() regardless of what the driver puts in the message. Every
  # condition is replaced with call. = FALSE before it leaves this function.
  withCallingHandlers(
    tryCatch(
      do.call(DBI::dbConnect, c(list(odbc::odbc()), args, list(...))),
      error = function(e) {
        stop("dw_connect(): Could not connect to the warehouse. The driver reported a ",
             "failure; the connection string is not shown because it may ",
             "carry a credential. Check the DSN, server, and database.",
             if (isTRUE(encrypt) && !isTRUE(trust_certificate)) paste0(
               " The server's TLS certificate was checked against this machine's CA ",
               "chain. If the certificate does not verify, install the institutional CA ",
               "chain (ask the server's administrator). `trust_certificate = TRUE` connects ",
               "without checking it, as a stop-gap only: it accepts any server's certificate."
             ),
             call. = FALSE)
      }
    ),
    warning = function(w) {
      warning("The driver reported a warning while connecting. The ",
              "message is not shown because it may carry a credential.",
              call. = FALSE)
      invokeRestart("muffleWarning")
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
                                   trust_certificate = FALSE) {
  cred <- .resolve_credentials(dsn = dsn)

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
    dsn = {
      args$dsn <- cred$dsn
    },
    kerberos = {
      args$Trusted_Connection <- "yes"
    },
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
