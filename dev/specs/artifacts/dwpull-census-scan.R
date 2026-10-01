#!/usr/bin/env Rscript
# dwpull-census-scan.R
#
# What the study instances of the warehouse pull change from the template.
#
# WHY. `dw_pull()` ports the canonical `tp.stXXXX_dwpull.sas`: its first five
# PROC SQL pass-through blocks are the five module YAMLs. What a port of the
# TEMPLATE cannot say is what studies CHANGE when they use it, and those edits
# are the requirements list for the master -> subset build
# (ehrlinger/hvtiRtemplates#223). Issue #72 asks for this census.
#
#   Rscript dwpull-census-scan.R --root /studies --count-only
#   Rscript dwpull-census-scan.R --root /studies --out dwpull-census.json
#
# WHAT IT MEASURES, for every study instance compared with the canonical
# template (the most common byte-identical `tp.*` copy under the root):
#
#   1. warehouse views and HVI_DM tables referenced, and which are beyond the
#      template's own
#   2. columns selected: `alias.*` versus explicit lists, explicit column names,
#      and renames (`s.sp_cabg rp_cabg`), as pairs and as prefix patterns
#   3. join keys (masterid / patid / other) and join TYPE per join, and how many
#      studies turned the template's inner join to Valve or Cabg into a left join
#   4. date windows: every `datediff(unit, X, Y) <op> N`, normalised to days
#      BEFORE or AFTER the cohort's index column, and the template's lopsided
#      `before <= N OR after >= 0` shape flagged wherever it occurs
#   5. ad hoc pulls (the template's sixth block): pulls whose view set is not one
#      of the template's, and which event views they read
#   6. cohort upload (the seventh block): writes through an ODBC libref, and
#      `execute (...) by` statements that write
#   7. the template copies themselves: byte variants, structural variants, a
#      structural diff of each against the canonical one, and which variant each
#      study instance sits nearest
#
# ⚠️ IT IS A PATTERN READER, NOT A SQL PARSER. The pass-through T-SQL is matched
# with regular expressions against the shapes the template uses. A subquery in a
# FROM clause, a comma join with its key in WHERE, a datediff whose argument is
# an expression rather than `alias.column`, and implicit pass-through (a
# `libname ... odbc` libref read in a DATA step) are counted or skipped, not
# understood. The output counts what it could not parse (`unparsed_datediff`,
# `implicit_joins`) rather than letting it vanish.
#
# 🔴 PRIVACY CONTRACT. Study programs can carry literal patient identifiers in a
# WHERE clause, and the template `%include`s a file holding warehouse
# credentials. So:
#
#   - It opens only files whose NAME matches the dwpull pattern. It never opens a
#     `%include` target, and nothing it emits names one.
#   - Every file goes through a lexer FIRST, before any other processing, which
#     drops comments and replaces every quoted string with a placeholder. A
#     connection string (`noprompt="..."` and kin) is reduced to its database
#     name if that is `hvi_dm` or `warehouse`, and to `other` or `unspecified`
#     otherwise. String contents are then dropped from memory.
#   - The one numeric literal it keeps is a parsed `datediff` bound, which is a
#     day offset. Every other number is replaced before any further parsing, and
#     every `in (...)` list is collapsed.
#   - It emits no path, file name, study identifier, directory name or source
#     line. View, table, column and rename NAMES are schema metadata and are
#     emitted, but only when seen in at least `--min-studies` studies (default
#     3) or present in the canonical template, and never when they carry a study
#     identifier's shape. Everything below the floor is counted, not named.
#   - Template variants are labelled by rank (1 = canonical), never by path.
#
# THE CONSOLE echoes the --root you passed, and counts.

here <- (function() {
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  if (length(f)) dirname(f[[1]]) else "."
})()
source(file.path(here, "scan-common.R"))

args <- commandArgs(trailingOnly = TRUE)
getarg <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i == length(args)) default else args[[i + 1L]]
}
root <- normalise_root(getarg("--root", "/studies"))
outfile <- getarg("--out", "dwpull-census.json")
min_studies <- as.integer(getarg("--min-studies", "3"))
top_n <- as.integer(getarg("--top", "30"))
count_only <- "--count-only" %in% args

.folders <- taxonomy_folders()
study_of <- study_of_factory(root, .folders)
message("taxonomy folders: ", paste(.folders, collapse = ", "))

# `stNNNN_dwpull.sas`, `tp.stXXXX_dwpull.sas`, and the `dw_pull` spelling. The
# pattern is applied to the BASENAME, so a directory named after the template
# does not pull in everything below it.
dwpull_re <- "dw_?pull[^/]*\\.sas$"
files <- list.files(root,
  pattern = dwpull_re, recursive = TRUE,
  full.names = TRUE, ignore.case = TRUE, no.. = TRUE
)
is_tp <- grepl("^tp\\.", basename(files), ignore.case = TRUE)
message(
  "candidate files: ", length(files), "  (template copies: ", sum(is_tp),
  ", study instances: ", sum(!is_tp), ")"
)
if (count_only) {
  message("\n--count-only: nothing was read.")
  quit(save = "no", status = 0)
}

# ---- fingerprint --------------------------------------------------------------
# As `build-structure-scan.R`: md5 where `digest` exists, and the output records
# which ran. Byte identity uses digest's `file=` mode, so CRLF and LF copies are
# different bytes, as they are on disk.
.fp_digest <- requireNamespace("digest", quietly = TRUE)
fingerprint_method <- if (.fp_digest) "md5" else "weighted-sums (COLLISION-PRONE)"
fingerprint <- function(x) {
  if (!nzchar(x)) {
    return("empty")
  }
  if (.fp_digest) {
    return(digest::digest(x, algo = "md5"))
  }
  v <- as.numeric(utf8ToInt(x))
  i <- seq_along(v)
  paste(length(v), sum(v) %% 2147483647, sum(v * i) %% 2147483647,
    sum(v * i * i) %% 2147483647,
    sep = "-"
  )
}
byte_fingerprint <- function(path, txt) {
  if (.fp_digest) {
    fp <- tryCatch(digest::digest(file = path, algo = "md5"), error = function(e) NA)
    if (!is.na(fp)) {
      return(fp)
    }
  }
  fingerprint(paste(txt, collapse = "\n"))
}

# ---- the lexer ----------------------------------------------------------------
# 🔴 THIS RUNS BEFORE ANYTHING ELSE TOUCHES THE TEXT. A character-level pass,
# because a regex cannot tell a quote inside a comment from a quote opening a
# string, and the template itself has an apostrophe in a `*` comment.
#
# Drops `/* */` block comments, `* ... ;` and `%* ... ;` statement comments, and
# `--` T-SQL line comments. Replaces each quoted string (with SAS's doubled-quote
# escape) by a numbered placeholder; the contents are returned separately only
# so the caller can classify connection strings, and are then discarded.
#
# ⚠️ Limits: macro quoting such as `%str(%')` is not understood, and an
# unbalanced quote masks the rest of the file. Both err toward masking more.
sas_lex <- function(txt) {
  s <- paste(enc2utf8(txt), collapse = "\n")
  ch <- strsplit(s, "", fixed = TRUE)[[1]]
  n <- length(ch)
  if (!n) {
    return(list(text = "", strings = character(0)))
  }
  nxt <- c(ch[-1], "")
  ws <- grepl("^[[:space:]]$", ch)
  close_block <- which(ch == "*" & nxt == "/")
  semis <- which(ch == ";")
  nls <- which(ch == "\n")
  quotes <- list("'" = which(ch == "'"), "\"" = which(ch == "\""))
  first_after <- function(v, i) {
    v <- v[v > i]
    if (length(v)) v[[1]] else NA_integer_
  }

  out <- character(n)
  k <- 0L
  strs <- character(0)
  i <- 1L
  at_start <- TRUE
  while (i <= n) {
    c1 <- ch[[i]]
    c2 <- nxt[[i]]
    if (c1 == "/" && c2 == "*") {
      j <- first_after(close_block, i + 1L)
      i <- if (is.na(j)) n + 1L else j + 2L
      k <- k + 1L
      out[k] <- " "
      next
    }
    if (c1 == "'" || c1 == "\"") {
      qp <- quotes[[c1]]
      j <- i
      repeat {
        j <- first_after(qp, j)
        if (is.na(j)) {
          j <- n + 1L
          break
        }
        if (j < n && ch[[j + 1L]] == c1) {
          j <- j + 1L
          next
        } # doubled quote
        break
      }
      body <- if (j - 1L >= i + 1L) paste(ch[(i + 1L):(j - 1L)], collapse = "") else ""
      strs <- c(strs, body)
      k <- k + 1L
      out[k] <- paste0(" __s", length(strs), "__ ")
      at_start <- FALSE
      i <- j + 1L
      next
    }
    if (at_start && (c1 == "*" || (c1 == "%" && c2 == "*"))) {
      j <- first_after(semis, i)
      i <- if (is.na(j)) n + 1L else j + 1L
      k <- k + 1L
      out[k] <- " "
      next
    }
    if (c1 == "-" && c2 == "-") {
      j <- first_after(nls, i)
      i <- if (is.na(j)) n + 1L else j
      next
    }
    if (c1 == ";") at_start <- TRUE else if (!ws[[i]]) at_start <- FALSE
    k <- k + 1L
    out[k] <- c1
    i <- i + 1L
  }
  list(text = paste(out[seq_len(k)], collapse = ""), strings = strs)
}

# A connection string, reduced to the one thing that may be emitted.
conn_db_of <- function(s) {
  m <- regmatches(s, regexec("(?i)(database|initial catalog) *= *([A-Za-z0-9_]+)",
    s,
    perl = TRUE
  ))[[1]]
  if (!length(m)) {
    return("unspecified")
  }
  db <- tolower(m[[3]])
  if (db %in% c("hvi_dm", "warehouse")) db else "other"
}
known_db <- function(x) {
  x <- tolower(x)
  if (x %in% c("hvi_dm", "warehouse")) x else "other"
}

# ---- sanitise: strings, connections, datediff bounds, every other number -------
dd_cmp_re <- paste0(
  "(abs *\\( *)?datediff *\\( *([a-z]+) *, *([a-z0-9_.&]+) *, *([a-z0-9_.&]+) *\\)",
  "( *\\))? *(<=|>=|<>|!=|<|>|=) *(-?[0-9]+|&[a-z0-9_]+\\.?)"
)
dd_btw_re <- paste0(
  "(abs *\\( *)?datediff *\\( *([a-z]+) *, *([a-z0-9_.&]+) *, *([a-z0-9_.&]+) *\\)",
  "( *\\))? *(between) *(-?[0-9]+|&[a-z0-9_]+\\.?) *and *(-?[0-9]+|&[a-z0-9_]+\\.?)"
)

sanitise <- function(txt) {
  lx <- sas_lex(txt)
  text <- lx$text
  for (k in seq_along(lx$strings)) {
    tok <- paste0("__s", k, "__")
    is_conn <- grepl(paste0(
      "(?i)\\b(noprompt|complete|required|prompt|init_string|",
      "datasrc|dsn|database) *= *", tok
    ), text, perl = TRUE)
    rep <- if (is_conn) paste0("__conn_", conn_db_of(lx$strings[[k]]), "__") else "__s__"
    text <- sub(tok, rep, text, fixed = TRUE)
  }
  lx <- NULL # string contents end here
  text <- tolower(gsub("[[:space:]]+", " ", text))

  # The datediff bounds, parsed into a table BEFORE numbers are stripped, and
  # replaced in the text by tokens a later parse can attribute to a pull.
  dd <- list()
  for (re in c(dd_btw_re, dd_cmp_re)) {
    m <- gregexpr(re, text, perl = TRUE)
    hits <- regmatches(text, m)[[1]]
    if (!length(hits)) next
    toks <- character(length(hits))
    for (h in seq_along(hits)) {
      g <- regmatches(hits[[h]], regexec(re, hits[[h]], perl = TRUE))[[1]]
      dd[[length(dd) + 1L]] <- list(
        abs = nzchar(g[[2]]), unit = g[[3]], a = g[[4]], b = g[[5]], op = g[[7]],
        lo = g[[8]], hi = if (length(g) >= 9L) g[[9]] else NA_character_
      )
      toks[[h]] <- paste0(" __dd", length(dd), "__ ")
    }
    regmatches(text, m) <- list(toks)
  }
  unparsed <- lengths(regmatches(text, gregexpr("datediff *\\(", text)))

  # 🔴 Every remaining number goes, and every `in (...)` list collapses.
  text <- gsub("\\bin *\\([^()]*\\)", "in (#)", text, perl = TRUE)
  text <- gsub("\\b[0-9]+(\\.[0-9]*)?(e[-+]?[0-9]+)?\\b", "#", text, perl = TRUE)
  list(text = text, dd = dd, unparsed_dd = unparsed)
}

# ---- names --------------------------------------------------------------------
# A study identifier in a cohort table name (`hvi_dm.st.st1234_cohort`) is
# normalised away before the name is ever tallied.
norm_table <- function(x) {
  x <- gsub("&[a-z0-9_]+\\.?", "&macro", x)
  x <- gsub("\\bst([0-9]{3,}|x{3,})", "stnnnn", x, perl = TRUE)
  gsub("[0-9]{3,}", "n", x)
}
# A second line behind the floor, as in `build-structure-scan.R`.
looks_identifying <- function(x) grepl("st[0-9]{3,}|[0-9]{5,}|^/", x)

table_re <- "\\b(warehouse|hvi_dm)\\.[a-z0-9_]*\\.(&[a-z0-9_]+\\.?)?[a-z0-9_]+"

# Top-level comma split, so `convert(date, x)` stays one select item.
split_top <- function(s) {
  ch <- strsplit(s, "", fixed = TRUE)[[1]]
  if (!length(ch)) {
    return(character(0))
  }
  depth <- cumsum((ch == "(") - (ch == ")"))
  cut <- which(ch == "," & depth == 0L)
  starts <- c(1L, cut + 1L)
  ends <- c(cut - 1L, length(ch))
  trimws(substring(s, starts, ends))
}

inner_of <- function(s) {
  m <- regexpr("connection +to +[a-z0-9_]+ *\\(", s)
  rest <- substring(s, m + attr(m, "match.length"))
  ch <- strsplit(rest, "", fixed = TRUE)[[1]]
  depth <- cumsum((ch == "(") - (ch == ")"))
  end <- which(depth < 0L)[1]
  if (is.na(end)) rest else substr(rest, 1L, end - 1L)
}

# ---- one pass-through query ---------------------------------------------------
join_kw_re <- "\\b((inner|left|right|full|cross)( +outer)? +)?join\\b"
tbl_re <- "^ *([a-z0-9_.&#]+)(?: +as)?(?: +(?!on\\b)([a-z0-9_]+))?(?: +on +(.*))? *$"

parse_query <- function(q, dd) {
  q <- trimws(q)
  sel <- regmatches(q, regexec("^select +(distinct +)?(.*?) +from +(.*)$", q,
    perl = TRUE
  ))[[1]]
  if (!length(sel)) {
    return(NULL)
  }
  sel_list <- sel[[3]]
  rest <- sel[[4]]
  cut <- regexpr("\\b(where|group +by|order +by|having|union)\\b", rest, perl = TRUE)
  fr <- if (cut > 0) substr(rest, 1L, cut - 1L) else rest

  # FROM and JOIN segments.
  jp <- gregexpr(join_kw_re, fr, perl = TRUE)[[1]]
  if (jp[[1]] < 0) {
    base <- fr
    segs <- character(0)
    kws <- character(0)
  } else {
    base <- substr(fr, 1L, jp[[1]] - 1L)
    ml <- attr(jp, "match.length")
    kws <- substring(fr, jp, jp + ml - 1L)
    segs <- substring(fr, jp + ml, c(jp[-1] - 1L, nchar(fr)))
  }
  alias <- list()
  tables <- character(0)
  add_tbl <- function(seg) {
    g <- regmatches(seg, regexec(tbl_re, seg, perl = TRUE))[[1]]
    if (!length(g)) {
      return(NULL)
    }
    t <- norm_table(g[[2]])
    a <- if (nzchar(g[[3]])) g[[3]] else sub("^.*\\.", "", t)
    list(table = t, alias = a, on = if (length(g) >= 4L) g[[4]] else "")
  }
  base_items <- split_top(base)
  base_tbls <- Filter(Negate(is.null), lapply(base_items, add_tbl))
  for (b in base_tbls) {
    alias[[b$alias]] <- b$table
    tables <- c(tables, b$table)
  }
  joins <- list()
  for (j in seq_along(segs)) {
    b <- add_tbl(segs[[j]])
    if (is.null(b)) next
    alias[[b$alias]] <- b$table
    tables <- c(tables, b$table)
    type <- sub("^ *(inner|left|right|full|cross).*$", "\\1", kws[[j]])
    if (!type %in% c("inner", "left", "right", "full", "cross")) type <- "inner"
    eq <- regmatches(b$on, gregexpr(
      "[a-z0-9_]+\\.([a-z0-9_]+) *= *[a-z0-9_]+\\.([a-z0-9_]+)", b$on
    ))[[1]]
    key <- if (!length(eq)) {
      "none"
    } else {
      g <- regmatches(eq[[1]], regexec(
        "[a-z0-9_]+\\.([a-z0-9_]+) *= *[a-z0-9_]+\\.([a-z0-9_]+)", eq[[1]]
      ))[[1]]
      if (g[[2]] == g[[3]]) g[[2]] else paste0(g[[2]], "=", g[[3]])
    }
    extra <- grepl("\\band\\b", b$on)
    joins[[length(joins) + 1L]] <- list(
      type = type, table = b$table, key = key,
      extra = extra
    )
  }
  coh <- names(alias)[startsWith(unlist(alias), "hvi_dm.")]
  cohort_alias <- if (length(coh)) {
    coh[[1]]
  } else if (length(base_tbls)) {
    base_tbls[[1]]$alias
  } else {
    ""
  }

  # SELECT items.
  items <- split_top(sel_list)
  stars <- 0L
  bare <- 0L
  expr <- 0L
  cols <- character(0)
  renames <- character(0)
  for (it in items) {
    if (it == "*") {
      bare <- bare + 1L
      next
    }
    if (grepl("^[a-z0-9_]+\\.\\*$", it)) {
      stars <- stars + 1L
      next
    }
    g <- regmatches(it, regexec(
      "^(?:[a-z0-9_]+\\.)?([a-z0-9_]+)(?:(?: +as)? +([a-z0-9_]+))?$", it,
      perl = TRUE
    ))[[1]]
    if (!length(g)) {
      expr <- expr + 1L
      next
    }
    cols <- c(cols, g[[2]])
    if (nzchar(g[[3]]) && g[[3]] != g[[2]]) {
      renames <- c(renames, paste(g[[2]], g[[3]],
        sep = " -> "
      ))
    }
  }

  # Date windows inside this query.
  ids <- as.integer(sub(
    "__dd([0-9]+)__", "\\1",
    regmatches(q, gregexpr("__dd[0-9]+__", q))[[1]]
  ))
  side_of <- function(arg) {
    p <- strsplit(arg, ".", fixed = TRUE)[[1]]
    if (length(p) == 2L && p[[1]] == cohort_alias) p[[2]] else NA_character_
  }
  wins <- list()
  for (id in ids) {
    w <- dd[[id]]
    ia <- side_of(w$a)
    ib <- side_of(w$b)
    # datediff(unit, a, b) is b - a. Index second: positive when the event is
    # BEFORE the index. Index first: positive when it is AFTER.
    dir <- if (w$abs) {
      "abs"
    } else if (!is.na(ib)) {
      "before"
    } else if (!is.na(ia)) {
      "after"
    } else {
      "unknown-index"
    }
    idx <- if (!is.na(ib)) ib else if (!is.na(ia)) ia else NA_character_
    bound <- if (w$op == "between") paste0(w$lo, "..", w$hi) else w$lo
    bound <- sub("^&.*$", "&macro", bound)
    sig <- paste(dir, w$op, bound)
    if (w$unit != "day") sig <- paste(sig, w$unit)
    wins[[as.character(id)]] <- list(
      dir = dir, op = w$op, bound = bound, sig = sig,
      idx = idx
    )
  }
  # ⚠️ THE TEMPLATE'S LOPSIDED SHAPE: `before <= N OR after >= 0`. The second
  # disjunct admits every event after the index, so the window has no upper
  # bound. Detected only when the two tokens are joined by OR.
  lop <- FALSE
  pr <- regmatches(q, gregexpr("__dd[0-9]+__ *\\)? *or *\\(? *__dd[0-9]+__", q))[[1]]
  for (p in pr) {
    two <- as.integer(sub(
      "__dd([0-9]+)__", "\\1",
      regmatches(p, gregexpr("__dd[0-9]+__", p))[[1]]
    ))
    w <- lapply(as.character(two), function(z) wins[[z]])
    if (any(vapply(w, is.null, logical(1)))) next
    is_before <- function(x) x$dir == "before" && x$op %in% c("<=", "<")
    is_open_after <- function(x) {
      x$dir == "after" && x$op %in% c(">=", ">") &&
        x$bound == "0"
    }
    if ((is_before(w[[1]]) && is_open_after(w[[2]])) ||
          (is_before(w[[2]]) && is_open_after(w[[1]]))) {
      lop <- TRUE
    }
  }

  views <- unique(tables[grepl("^(warehouse|hvi_dm)\\.", tables)])
  list(
    views = views,
    sig = paste(sort(views[startsWith(views, "warehouse.")]), collapse = "+"),
    joins = joins, implicit_joins = max(0L, length(base_tbls) - 1L),
    stars = stars, bare = bare, expr = expr, cols = unique(cols),
    renames = unique(renames), wins = unname(wins), lopsided = lop
  )
}

# ---- one file -----------------------------------------------------------------
parse_file <- function(path) {
  txt <- suppressWarnings(
    tryCatch(readLines(path, warn = FALSE, encoding = "latin1"),
      error = function(e) NULL
    )
  )
  if (is.null(txt)) {
    return(NULL)
  }
  sz <- sanitise(txt)
  st <- trimws(strsplit(sz$text, ";", fixed = TRUE)[[1]])

  pulls <- lapply(st[grepl("connection +to +[a-z0-9_]+ *\\(", st)], function(s) {
    parse_query(inner_of(s), sz$dd)
  })
  pulls <- Filter(Negate(is.null), pulls)
  connect_dbs <- unlist(lapply(st[grepl("^connect +to +odbc\\b", st)], function(s) {
    m <- regmatches(s, regexpr("__conn_[a-z_]+__", s))
    if (length(m)) {
      sub("^__conn_(.*)__$", "\\1", m)
    } else {
      u <- regmatches(s, regexec("\\b(database|dsn|datasrc) *= *([a-z0-9_]+)", s))[[1]]
      if (length(u)) known_db(u[[3]]) else "unspecified"
    }
  }))

  # Block 7: the ODBC libref and what is written through it.
  lib_st <- st[grepl("^libname +[a-z0-9_]+ +odbc\\b", st)]
  odbc_refs <- sub("^libname +([a-z0-9_]+) .*$", "\\1", lib_st)
  lib_dbs <- vapply(lib_st, function(s) {
    m <- regmatches(s, regexpr("__conn_[a-z_]+__", s))
    if (length(m)) {
      return(sub("^__conn_(.*)__$", "\\1", m))
    }
    u <- regmatches(s, regexec("\\b(database|dsn|datasrc) *= *([a-z0-9_]+)", s))[[1]]
    if (length(u)) known_db(u[[3]]) else "unspecified"
  }, character(1), USE.NAMES = FALSE)
  writes <- 0L
  reads <- 0L
  for (r in odbc_refs) {
    w <- paste0(
      "^data +[^=]*\\b", r, "\\.|^create +table +", r, "\\.|\\b(base|out) *= *",
      r, "\\b"
    )
    writes <- writes + sum(grepl(w, st))
    reads <- reads + sum(grepl(paste0("\\b(set|merge|from|join) +", r, "\\."), st))
  }
  exec_write <- sum(grepl("^execute *\\(", st) &
                      grepl("\\b(insert|create|drop|truncate|update|delete|into)\\b", st))

  # Structural fingerprint: literals are already gone; the study identifier in
  # the cohort table is normalised, and the window bounds are appended because
  # the text no longer carries them.
  norm <- gsub("\\bst([0-9]{3,}|x{3,})", "stnnnn", sz$text, perl = TRUE)
  norm <- gsub("__dd[0-9]+__", "__dd__", norm)
  sigs <- unlist(lapply(pulls, function(p) vapply(p$wins, `[[`, "", "sig")))
  list(
    byte_fp = byte_fingerprint(path, txt),
    struct_fp = fingerprint(paste(c(gsub(" +", " ", norm), sigs), collapse = "|")),
    views = unique(norm_table(regmatches(sz$text, gregexpr(table_re, sz$text))[[1]])),
    pulls = pulls, connect_dbs = connect_dbs, lib_dbs = lib_dbs,
    odbc_writes = writes, odbc_reads = reads, exec_writes = exec_write,
    has_include = any(grepl("^%include\\b", st)),
    unparsed_dd = sz$unparsed_dd,
    mtime = format(file.info(path)$mtime, "%Y-%m")
  )
}

# The features two files are compared on, for variant diffs and nearest-variant.
features_of <- function(p) {
  j <- unlist(lapply(p$pulls, function(q) {
    vapply(q$joins, function(x) {
      paste("join", x$type, x$table, x$key, sep = ":")
    }, "")
  }))
  unique(c(
    paste0("view:", p$views), j,
    paste0("pull:", vapply(p$pulls, `[[`, "", "sig")),
    paste0("win:", unlist(lapply(p$pulls, function(q) {
      vapply(q$wins, `[[`, "", "sig")
    }))),
    paste0("col:", unlist(lapply(p$pulls, `[[`, "cols"))),
    if (any(vapply(p$pulls, `[[`, logical(1), "lopsided"))) "lopsided",
    if (p$odbc_writes + p$exec_writes > 0L) "upload"
  ))
}

# ---- walk ---------------------------------------------------------------------
parsed <- vector("list", length(files))
for (i in seq_along(files)) {
  parsed[i] <- list(parse_file(files[[i]]))
  if (is.null(parsed[[i]])) .scan_unreadable$n <- .scan_unreadable$n + 1L
  if (i %% 50 == 0) message("  ", i, " / ", length(files))
}
ok <- !vapply(parsed, is.null, logical(1))
studies <- study_of(files)
unplaced <- is.na(studies)
# ⚠️ A file with no taxonomy ancestor is keyed by its directory, IN MEMORY ONLY,
# so it still counts as a study. The key is never emitted; the count of such
# files is.
studies[unplaced] <- paste0("unplaced:", dirname(files[unplaced]))

inst <- which(ok & !is_tp)
tpl <- which(ok & is_tp)

# ---- the canonical template ---------------------------------------------------
canon <- NULL
variants <- list()
if (length(tpl)) {
  bfp <- vapply(parsed[tpl], `[[`, "", "byte_fp")
  tab <- sort(table(bfp), decreasing = TRUE)
  for (r in seq_along(tab)) {
    members <- tpl[bfp == names(tab)[[r]]]
    variants[[r]] <- list(
      rank = r, files = length(members), first = members[[1]],
      months = vapply(parsed[members], `[[`, "", "mtime")
    )
  }
  canon <- parsed[[variants[[1]]$first]]
}
template_source <- if (is.null(canon)) {
  "none (no tp.* copy under root)"
} else {
  "most common byte-identical tp.* copy"
}
# ⚠️ Fallback when no template copy is under the root, so `beyond_template` still
# means something. These are the six views of the template as ported in
# `inst/extdata/modules/*.yaml`, plus its coronary ad hoc block.
builtin_views <- paste0("warehouse.dbo.", c(
  "vw_cardsurg_base", "vw_cardsurg_valve", "vw_cardsurg_cabg", "vw_echo_base",
  "vw_fup_base", "event_cardsurg_coronary"
))
tmpl_views <- if (is.null(canon)) builtin_views else canon$views
tmpl_cols <- if (is.null(canon)) {
  character(0)
} else {
  unique(unlist(lapply(canon$pulls, `[[`, "cols")))
}
tmpl_sigs <- if (is.null(canon)) {
  character(0)
} else {
  vapply(canon$pulls, `[[`, "", "sig")
}
tmpl_joins <- if (is.null(canon)) {
  list()
} else {
  unlist(lapply(canon$pulls, `[[`, "joins"),
    recursive = FALSE
  )
}
canon_feat <- if (is.null(canon)) character(0) else features_of(canon)

# ---- tallies over study instances ---------------------------------------------
tally <- new.env(parent = emptyenv())
bump <- function(cat, keys, stu) {
  for (k in unique(keys)) {
    id <- paste(cat, k, sep = "\r")
    tally[[id]] <- unique(c(tally[[id]], stu))
  }
}
studies_in <- function(cat) {
  ks <- ls(tally, pattern = paste0("^", cat, "\r"))
  stats::setNames(
    vapply(ks, function(k) length(tally[[k]]), integer(1)),
    sub("^[^\r]*\r", "", ks)
  )
}
flag <- new.env(parent = emptyenv())
mark <- function(what, stu) flag[[what]] <- unique(c(flag[[what]], stu))
nflag <- function(what) length(flag[[what]])

n_join <- list()
n_items <- c(
  alias_star = 0L, bare_star = 0L, explicit = 0L,
  expression = 0L
)
n_dd <- 0L
n_unparsed <- 0L
n_implicit <- 0L
pulls_per <- integer(0)
for (i in inst) {
  p <- parsed[[i]]
  s <- studies[[i]]
  bump("view", p$views, s)
  bump("conn", p$connect_dbs, s)
  bump("libdb", p$lib_dbs, s)
  if (p$has_include) mark("include", s)
  if (length(p$connect_dbs)) mark("connects", s)
  if (length(p$lib_dbs)) mark("odbc_libname", s)
  if (p$odbc_writes > 0L) mark("odbc_write", s)
  if (p$odbc_reads > 0L) mark("odbc_read", s)
  if (p$exec_writes > 0L) mark("exec_write", s)
  if (p$odbc_writes + p$exec_writes > 0L) mark("any_write", s)
  if (!is.null(canon) && identical(p$byte_fp, canon$byte_fp)) mark("byte_same", s)
  if (!is.null(canon) && identical(p$struct_fp, canon$struct_fp)) mark("struct_same", s)
  n_unparsed <- n_unparsed + p$unparsed_dd
  pulls_per <- c(pulls_per, length(p$pulls))

  sigs <- vapply(p$pulls, `[[`, "", "sig")
  if (!is.null(canon) && any(!tmpl_sigs %in% sigs)) mark("drops_template_pull", s)
  for (q in p$pulls) {
    n_items <- n_items + c(q$stars, q$bare, length(q$cols), q$expr)
    n_implicit <- n_implicit + q$implicit_joins
    if (q$stars + q$bare > 0L) mark("selects_star", s)
    if (length(q$cols)) mark("selects_explicit", s)
    bump("col", q$cols, s)
    bump("rename", q$renames, s)
    pat <- vapply(strsplit(q$renames, " -> ", fixed = TRUE), function(ab) {
      m1 <- regmatches(ab[[1]], regexec("^([a-z]+_)(.+)$", ab[[1]]))[[1]]
      m2 <- regmatches(ab[[2]], regexec("^([a-z]+_)(.+)$", ab[[2]]))[[1]]
      if (length(m1) && length(m2) && m1[[3]] == m2[[3]]) {
        paste0(m1[[2]], "* -> ", m2[[2]], "*")
      } else {
        NA_character_
      }
    }, character(1))
    bump("rename_pattern", pat[!is.na(pat)], s)
    if (!is.null(canon) && !q$sig %in% tmpl_sigs) {
      mark("adhoc", s)
      bump("adhoc_event_view", q$views[grepl("\\.event_", q$views)], s)
      bump("adhoc_view", q$views[startsWith(q$views, "warehouse.")], s)
    }
    for (j in q$joins) {
      n_join[[j$type]] <- (if (is.null(n_join[[j$type]])) 0L else n_join[[j$type]]) + 1L
      bump("join_type", j$type, s)
      cls <- if (j$key %in% c("masterid", "patid")) j$key else "other"
      bump("join_key_class", cls, s)
      if (cls == "other") bump("join_key_other", j$key, s)
      if (j$extra) mark("join_extra_condition", s)
      if (grepl("vw_cardsurg_(valve|cabg)$", j$table) && j$type != "inner") {
        mark("valve_cabg_outer", s)
        if (j$type == "left") mark("valve_cabg_left", s)
      }
      for (t in tmpl_joins) {
        if (identical(t$table, j$table) && identical(t$key, j$key) &&
              !identical(t$type, j$type)) {
          mark("template_join_retyped", s)
        }
      }
    }
    for (w in q$wins) {
      n_dd <- n_dd + 1L
      mark("has_window", s)
      bump("window", w$sig, s)
      if (!is.na(w$idx)) bump("window_index", w$idx, s)
    }
    if (q$lopsided) mark("lopsided", s)
  }
}

# ---- naming, behind the floor -------------------------------------------------
view_n <- studies_in("view")
col_n <- studies_in("col")
nameable <- function(x, counts, always = character(0)) {
  n <- counts[x]
  n[is.na(n)] <- 0L
  (x %in% always | n >= min_studies) & !looks_identifying(x)
}
top_names <- function(cat, always = character(0), extra = NULL) {
  n <- studies_in(cat)
  if (!length(n)) {
    return(list(
      distinct = 0L, below_floor = 0L,
      withheld_as_identifying = 0L, top = list()
    ))
  }
  keep <- nameable(names(n), n, always)
  ident <- looks_identifying(names(n))
  o <- order(-n[keep], names(n)[keep])
  kn <- n[keep][o]
  list(
    distinct = length(n),
    below_floor = sum(!keep & !ident),
    withheld_as_identifying = sum(ident),
    top = lapply(utils::head(seq_along(kn), top_n), function(k) {
      r <- list(name = names(kn)[[k]], studies = kn[[k]])
      if (!is.null(extra)) r[[extra]] <- names(kn)[[k]] %in% always
      r
    })
  )
}
counts_of <- function(cat) {
  n <- studies_in(cat)
  if (!length(n)) {
    return(list())
  }
  as.list(n[order(-n, names(n))])
}

# Floored rendering of a feature, for template diffs.
feature_nameable <- function(f) {
  kind <- sub(":.*$", "", f)
  body <- sub("^[^:]*:", "", f)
  switch(kind,
    view = nameable(body, view_n, tmpl_views),
    col  = nameable(body, col_n, tmpl_cols),
    pull = all(nameable(strsplit(body, "+", fixed = TRUE)[[1]], view_n, tmpl_views)),
    join = nameable(strsplit(body, ":", fixed = TRUE)[[1]][[2]], view_n, tmpl_views),
    TRUE
  )
}
render_diff <- function(feats) {
  if (!length(feats)) {
    return(list(named = list(), below_floor = 0L))
  }
  ok <- vapply(feats, feature_nameable, logical(1))
  list(named = as.list(sort(feats[ok])), below_floor = sum(!ok))
}

# ---- template variants --------------------------------------------------------
variant_out <- list()
nearest <- integer(0)
if (length(variants)) {
  vfeat <- lapply(variants, function(v) features_of(parsed[[v$first]]))
  for (v in variants) {
    pv <- parsed[[v$first]]
    fv <- vfeat[[v$rank]]
    variant_out[[v$rank]] <- list(
      rank = v$rank, files = v$files,
      first_seen = min(v$months), last_seen = max(v$months),
      structurally_canonical = identical(pv$struct_fp, canon$struct_fp),
      pulls = length(pv$pulls),
      added = render_diff(setdiff(fv, canon_feat)),
      removed = render_diff(setdiff(canon_feat, fv))
    )
  }
  # Which variant each instance sits nearest, by Jaccard similarity of features.
  # Ties go to the lower rank, so an instance is called drifted only when it is
  # strictly closer to a drifted variant than to the canonical one.
  jac <- function(a, b) {
    if (!length(union(a, b))) {
      1
    } else {
      length(intersect(a, b)) / length(union(a, b))
    }
  }
  for (i in inst) {
    fi <- features_of(parsed[[i]])
    nearest <- c(nearest, which.max(vapply(vfeat, function(v) jac(fi, v), numeric(1))))
  }
}

n_stu <- length(unique(studies[inst]))
out <- list(
  `_provenance` = list(
    script = "dwpull-census-scan.R",
    question = "what do study instances of tp.stXXXX_dwpull.sas change from the template?",
    issue = "ehrlinger/hvtiRdatabuild#72",
    run_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    root = if (identical(root, "/studies")) "/studies" else "(non-default root)",
    file_pattern = dwpull_re,
    fingerprint = fingerprint_method,
    template_source = template_source,
    hvtiRutilities_version = as.character(utils::packageVersion("hvtiRutilities")),
    taxonomy_folders = paste(sort(.folders), collapse = ","),
    min_studies = min_studies,
    top = top_n,
    files_considered = length(files),
    files_read = sum(ok),
    files_unreadable = unreadable_count()
  ),
  corpus = list(
    study_instance_files = length(inst),
    template_files = length(tpl),
    studies = n_stu,
    unplaced_instance_files = sum(unplaced[inst]),
    studies_with_include = nflag("include"),
    studies_connecting = nflag("connects")
  ),
  unedited = list(
    studies_byte_identical_to_canonical = nflag("byte_same"),
    studies_structurally_identical_to_canonical = nflag("struct_same")
  ),
  views = c(
    top_names("view", tmpl_views, "in_template"),
    list(
      template_views = as.list(sort(tmpl_views)),
      beyond_template_distinct = sum(!names(view_n) %in% tmpl_views)
    )
  ),
  connections = list(connect_to_odbc_db = counts_of("conn")),
  columns = list(
    items = as.list(n_items),
    studies_selecting_star = nflag("selects_star"),
    studies_selecting_explicit = nflag("selects_explicit"),
    names = top_names("col", tmpl_cols, "in_template"),
    renames = top_names("rename"),
    rename_patterns = top_names("rename_pattern")
  ),
  joins = list(
    joins_by_type = n_join,
    studies_by_type = counts_of("join_type"),
    studies_by_key_class = counts_of("join_key_class"),
    other_keys = top_names("join_key_other"),
    implicit_joins = n_implicit,
    studies_with_extra_join_condition = nflag("join_extra_condition"),
    studies_left_join_valve_or_cabg = nflag("valve_cabg_left"),
    studies_outer_join_valve_or_cabg = nflag("valve_cabg_outer"),
    studies_retyping_a_template_join = nflag("template_join_retyped")
  ),
  windows = list(
    datediff_clauses = n_dd,
    unparsed_datediff = n_unparsed,
    studies_with_any = nflag("has_window"),
    studies_lopsided = nflag("lopsided"),
    canonical_is_lopsided = if (is.null(canon)) {
      NA
    } else {
      any(vapply(canon$pulls, `[[`, logical(1), "lopsided"))
    },
    signatures = counts_of("window"),
    index_columns = top_names("window_index", tmpl_cols)
  ),
  pulls = list(
    canonical_pulls = length(tmpl_sigs),
    per_instance_min = if (length(pulls_per)) min(pulls_per) else 0L,
    per_instance_median = if (length(pulls_per)) {
      as.numeric(stats::median(pulls_per))
    } else {
      NA_real_
    },
    per_instance_max = if (length(pulls_per)) max(pulls_per) else 0L,
    studies_dropping_a_template_pull = nflag("drops_template_pull"),
    studies_with_pull_beyond_template = nflag("adhoc"),
    adhoc_views = top_names("adhoc_view", tmpl_views),
    adhoc_event_views = top_names("adhoc_event_view", tmpl_views)
  ),
  upload = list(
    studies_with_odbc_libname = nflag("odbc_libname"),
    odbc_libname_db = counts_of("libdb"),
    studies_writing_via_odbc_libref = nflag("odbc_write"),
    studies_reading_via_odbc_libref = nflag("odbc_read"),
    studies_execute_write = nflag("exec_write"),
    studies_any_write = nflag("any_write")
  ),
  templates = list(
    files = length(tpl),
    byte_variants = length(variants),
    structural_variants = length(unique(vapply(parsed[tpl], `[[`, "", "struct_fp"))),
    canonical_files = if (length(variants)) variants[[1]]$files else 0L,
    variants = variant_out,
    instances_nearest_canonical = sum(nearest == 1L),
    instances_nearest_drifted = sum(nearest > 1L),
    instances_nearest_by_rank = lapply(seq_along(variants), function(r) {
      list(rank = r, instances = sum(nearest == r))
    })
  )
)

writeLines(to_json(out), outfile)

c0 <- out$corpus
u <- out$unedited
message("\n--- DWPULL CENSUS ---")
message(
  "instance files / studies:   ", c0$study_instance_files, " / ", c0$studies,
  "   (unplaced files: ", c0$unplaced_instance_files, ")"
)
message(
  "template copies:            ", c0$template_files, "  in ",
  out$templates$byte_variants, " byte variants (canonical: ",
  out$templates$canonical_files, ")"
)
message(
  "unedited (byte / structure): ", u$studies_byte_identical_to_canonical, " / ",
  u$studies_structurally_identical_to_canonical
)
message(
  "views beyond template:      ", out$views$beyond_template_distinct,
  "   below floor: ", out$views$below_floor
)
message("left join to Valve/Cabg:    ", out$joins$studies_left_join_valve_or_cabg)
message(
  "datediff clauses:           ", out$windows$datediff_clauses,
  "   lopsided studies: ", out$windows$studies_lopsided,
  "   unparsed: ", out$windows$unparsed_datediff
)
message("pull beyond template:       ", out$pulls$studies_with_pull_beyond_template)
message("cohort upload (any write):  ", out$upload$studies_any_write)
message("nearest drifted variant:    ", out$templates$instances_nearest_drifted)
message("files unreadable:           ", unreadable_count())
message("\nwrote ", outfile)
