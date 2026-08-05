# Canonical synthetic fixture. No PHI: ids and values are invented.
.fixture_frame <- function() {
  d <- data.frame(
    ccfidu   = c("A001", "A002", "A003", "A004"),
    age      = c(65.5, 70.25, 58.0, NA),
    bmi      = c(31.2, NA, 22.8, 27.4),
    dt_surg  = as.Date(c("2020-01-15", "2021-06-30", NA, "2019-11-02")),
    surgeon  = c("Smith", "Jones ", "Smith", NA),
    stringsAsFactors = FALSE
  )
  attr(d$age, "label") <- "Age at surgery"
  attr(d$bmi, "label") <- "Body mass index"
  d
}

# Resolves whether the package is loaded via pkgload (devtools::test) or
# installed (R CMD check).
.fixture_path <- function() {
  system.file("extdata", "oracle_small.sas7bdat", package = "hvtiRdatasets")
}
