# Open a connection to the data warehouse

Resolves credentials through the ladder documented in the design spec
and opens an ODBC connection. Credentials never appear in a function
argument, a configuration file, a log line, or an error message, and the
connection string is never echoed.

## Usage

``` r
dw_connect(
  server,
  database,
  dsn = NULL,
  port = NULL,
  encrypt = TRUE,
  trust_certificate = FALSE,
  ...
)
```

## Arguments

- server:

  Warehouse host name.

- database:

  Database name.

- dsn:

  Optional named ODBC DSN. When supplied, the driver holds the
  credentials and none enters R's memory.

- port:

  Optional port number.

- encrypt:

  Whether to request an encrypted connection.

- trust_certificate:

  Whether to trust the server certificate without validating it against
  a CA chain. `FALSE`, the default, validates it.

- ...:

  Further arguments passed to
  [`DBI::dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html).

## Value

A
[DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
object.

## Details

`trust_certificate` defaults to `FALSE`: the warehouse server's TLS
certificate is checked against the machine's CA chain, because the
connection carries credentials. Microsoft changed the `Encrypt` default
from `no` in *ODBC Driver 17 for SQL Server* to `yes` in driver 18, and
the legacy SAS connection carried `TrustServerCertificate=Yes`. If a
connection fails because the certificate does not verify, install the
institutional CA chain on the machine (ask whoever administers the
server or the DSN). Pass `trust_certificate = TRUE` only as a stop-gap:
it accepts any certificate, so it does not protect the credentials from
an impostor server.

Set the `HVI_DW_KERBEROS` environment variable to enable the top rung of
the credential ladder, Kerberos integrated authentication: no stored
secret is used, and the connection relies on the caller's existing
ticket instead. It is read with
[`as.logical()`](https://rdrr.io/r/base/logical.html), which recognises
`"true"`, `"True"`, `"T"`, and `"TRUE"` (and their `FALSE`
counterparts). Set it to one of those, not `"yes"` or `"1"`, which
[`as.logical()`](https://rdrr.io/r/base/logical.html) does not recognise
and silently reads as `NA`.

File-based credentials (a DSN or `~/.Renviron`) are unavailable on
Windows: Windows has no POSIX file mode, so a credential file's
protection can never be confirmed there, and `dw_connect()` refuses
rather than trust it unverified. This package targets the Linux server
described in the design spec.

## Examples

``` r
# \donttest{
if (requireNamespace("odbc", quietly = TRUE)) {
  # Requires a configured DSN and warehouse access; not run in checks.
  # conn <- dw_connect(server = "<DW-SERVER>", database = "<DW-DB>",
  #                    dsn = "HVI_DW")
}
#> NULL
# }
```
