* `propose_corrections()` refuses a row that repeats a correction still
  pending or accepted: same source, key, variable, prior and new value, compared
  in canonical text. The verdict is `duplicate_pending` or `duplicate_accepted`,
  and as with any other refused row the whole file is refused. A proposed
  correction leaves the source unchanged until it is accepted, so the same file
  submitted twice used to be appended twice. An assertion whose correction was
  rejected or superseded may be proposed again.
