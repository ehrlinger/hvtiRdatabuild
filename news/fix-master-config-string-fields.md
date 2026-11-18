* `read_master_config()` refuses a `name`, `snapshots`, `current` or
  `build_program` that yaml did not read as one non-empty string. An unquoted
  `snapshots: .` became `NA`, and `name: .inf` became `"Inf"`; the error says
  to quote the value.
