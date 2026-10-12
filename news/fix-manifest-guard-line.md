- `write_analysis_set()` and `read_analysis_set()` skip the line of text that
  hvtiRutilities 1.5.1 writes at the head of a `manifest.yaml` holding a
  registered dated version. Without this they stopped with "$ operator is
  invalid for atomic vectors" on every study registered from 1.5.1 on.
- `write_analysis_set()` refuses a set named for a registered dated version,
  such as `built_20261008`, before writing anything. Its parquet would have
  replaced that version, the registered data every job reads.
