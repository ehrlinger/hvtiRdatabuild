# hvtiRdatabuild: Build and Verify Analytic Datasets for the HVTI CORR Group

Builds analysis-ready clinical datasets for the clinical investigations
statistics group within The Heart and Vascular Institute at the
Cleveland Clinic, and verifies them against the legacy 'SAS' datasets
they replace.

## Quiet mode

Informational messages, such as the progress lines of
[`snapshot_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/snapshot_master.md)
and
[`lift_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/lift_master.md),
follow the hvtiR family option `hvti.quiet`:
`options(hvti.quiet = TRUE)` silences them. Warnings and errors are
never silenced by it. A call that finishes with work left undone warns,
so quiet mode cannot hide it:
[`snapshot_master()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/snapshot_master.md)
when a historical snapshot fails, and
[`backfill_corrections()`](https://ehrlinger.github.io/hvtiRdatabuild/reference/backfill_corrections.md)
when a legacy fact is unresolved or a statement unparsed.

## See also

Useful links:

- <https://github.com/ehrlinger/hvtiRdatabuild>

- <https://ehrlinger.github.io/hvtiRdatabuild/>

- Report bugs at <https://github.com/ehrlinger/hvtiRdatabuild/issues>

## Author

**Maintainer**: John Ehrlinger <john.ehrlinger@gmail.com>

Authors:

- John Ehrlinger <john.ehrlinger@gmail.com>
