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
