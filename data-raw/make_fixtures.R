# Generates inst/extdata/oracle_small.sas7bdat.
#
# Run manually, never at test time. haven::write_sas() is deprecated
# (haven 2.5.2); this is the only place in the project that calls it, and
# the resulting binary is committed so no test ever needs a SAS writer.
#
# Usage: Rscript data-raw/make_fixtures.R

source(file.path("tests", "testthat", "helper-fixtures.R"))

d <- .fixture_frame()
dir.create(file.path("inst", "extdata"), showWarnings = FALSE, recursive = TRUE)
target <- file.path("inst", "extdata", "oracle_small.sas7bdat")
suppressWarnings(haven::write_sas(d, target))

# Fail loudly if the writer was not faithful.
back <- haven::read_sas(target)
stopifnot(
  nrow(back) == nrow(d),
  ncol(back) == ncol(d),
  isTRUE(all.equal(as.numeric(back$age), as.numeric(d$age)))
)
cat("wrote", target, "with", nrow(d), "rows\n")
