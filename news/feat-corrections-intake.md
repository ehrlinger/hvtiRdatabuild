* New interim tools for correcting warehouse source views, superseded by the HVTR
  registry: `generate_corrections_sql()` writes each declared source's corrections tables
  and its corrected, applied, stale and conflicts views, covering every column;
  `write_corrections_template()`, `propose_corrections()` and `decide_corrections()` take
  a whole submission and refuse it whole if any row fails, with a verdict per row and no
  values in any message; `retire_filled_corrections()` retires fill-ins upstream has
  caught up with; and `study_correction_candidates()` turns a study's own fixes into
  candidate corrections against its frozen pull. In these views, accepted corrections to one cell
  that disagree do not resolve to the latest: neither applies until one is superseded.
* `read_master_config()` reads `sources` (correctable source views and their keys) and
  `deciders` from `master.yml`.
* On SQL Server, `table_types()` now carries a decimal column's precision and scale, so the
  master corrections view built by `lift_master()` no longer casts to a bare `decimal`,
  which SQL Server reads as `decimal(18,0)` and rounds.
* `parse_value()` now parses logical columns.
