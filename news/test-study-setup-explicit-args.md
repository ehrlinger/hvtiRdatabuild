* Tests and examples pass `renv` and `cleanup` to `hvtiRutilities::study_setup()` explicitly, ahead of
  `hvtiRutilities` turning both on by default. A new test fails on any call that leaves them implicit.
* The `hvtiRutilities` floor rises to 1.5.2, the first release whose `study_setup()` takes `renv` and `cleanup`.
