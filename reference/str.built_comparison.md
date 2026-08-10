# Structure of a dataset comparison, without identifiers

[`str()`](https://rdrr.io/r/utils/str.html) dispatches on the object
rather than routing through
[`print.built_comparison()`](https://ehrlinger.github.io/hvtiRdatasets/reference/print.built_comparison.md),
so the default method would print the `rows` attribute verbatim —
including the identifier vectors. In this group's data an identifier is
a medical record number concatenated with a date of surgery.

## Usage

``` r
# S3 method for class 'built_comparison'
str(object, ...)
```

## Arguments

- object:

  An object of class `built_comparison`.

- ...:

  Passed to the underlying
  [`utils::str()`](https://rdrr.io/r/utils/str.html) call.

## Value

`NULL`, invisibly. Called for its side effect.

## Details

The hazard here is *incidental* disclosure, not retrieval.
[`str()`](https://rdrr.io/r/utils/str.html) is what people type
reflexively to inspect an object, and its output is routinely pasted
into issues, chat, and logs, so PHI arrives without anyone having asked
for it. Deliberate retrieval stays available and unchanged:
`attr(x, "rows")$only_oracle` and `$only_r`.

## See also

[`print.built_comparison()`](https://ehrlinger.github.io/hvtiRdatasets/reference/print.built_comparison.md)
