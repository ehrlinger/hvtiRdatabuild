# Print a dataset comparison

Reports row-set differences and a count per verdict, then lists every
variable that is not \`"identical"\`. No overall pass/fail is printed,
by design: see \[compare_built()\].

## Usage

``` r
# S3 method for class 'built_comparison'
print(x, ..., show_ids = getOption("hvtiRdatasets.show_ids", FALSE))
```

## Arguments

- x:

  An object of class \`built_comparison\`.

- ...:

  Ignored.

- show_ids:

  Logical. Print the identifiers that appear on only one side. Defaults
  to the \`hvtiRdatasets.show_ids\` option, itself \`FALSE\`.
  \*\*Enabling this may emit PHI.\*\* Only do so in a session whose
  output is not being logged or shared.

## Value

\`x\`, invisibly.

## Details

Identifiers are \*\*not\*\* printed by default. In this group's datasets
\`ccfidu\` is a medical record number concatenated with a date of
surgery, which is PHI; printing it would place PHI in terminals, logs,
and captured test failures. The identifiers remain available in the
\`rows\` attribute for a caller who needs them to chase a discrepancy.
