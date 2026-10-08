* **A stale analysis set no longer stops a draft.** `read_analysis_set()`
  reads a set whose parent or declaration has changed, and signals
  `hvtiRutilities_stale_analysis_set` with the `write_analysis_set()` call that
  updates it. A final render (`HVTI_TEMPLATE_STRICT` set, as
  `render_job(final = TRUE)` does) still stops, with the same commands. This
  reverses the earlier rule that every stale read stopped; a damaged set still
  stops in every render. Requires hvtiRutilities 1.5.1.
