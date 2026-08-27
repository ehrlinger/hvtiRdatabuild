# Freeze a SAS-built dataset as a checksummed parquet oracle

Reads a SAS dataset once with haven, writes it as parquet, and returns a
record of what was written including a SHA-256 checksum of the parquet
file.

## Usage

``` r
snapshot_oracle(sas_path, out_path, expect = NULL, manifest = NULL)
```

## Arguments

- sas_path:

  Path to the SAS dataset (`.sas7bdat`).

- out_path:

  Path to write the parquet file. Must not already exist.

- expect:

  Optional named list validating the conversion, with any of `n_rows`,
  `n_cols`, and `variables`. Supply values read from SAS-side
  `PROC CONTENTS`. A mismatch is an error.

- manifest:

  Optional path to a manifest YAML. When supplied, the snapshot is
  recorded with
  [`hvtiRutilities::update_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/update_manifest.html)
  so that
  [`hvtiRutilities::verify_manifest()`](https://ehrlinger.github.io/hvtiRutilities/reference/verify_manifest.html)
  can later detect a drifted oracle.

## Value

Invisibly, a list with elements `path`, `n_rows`, `n_cols`, `variables`,
and `sha256`.

## Details

The snapshot exists so that equivalence testing has a fixed reference. A
SAS-built dataset on a shared volume can be regenerated at any time; if
it changes mid-migration, every previously passing comparison silently
becomes meaningless. A checksummed snapshot is a citable fixed point.

Note that this does not remove haven from the chain of custody — it
confines it to a single audited step. A misread is faithfully preserved
in the parquet file. Supply `expect` to validate the conversion against
SAS-side `PROC CONTENTS` output.

## See also

[`compare_built()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/compare_built.md)

## Examples

``` r
# \donttest{
if (requireNamespace("arrow", quietly = TRUE)) {
  src <- system.file("extdata", "oracle_small.sas7bdat",
                     package = "hvtiRdatabuild")
  snapshot_oracle(src, tempfile(fileext = ".parquet"))
}
# }
```
