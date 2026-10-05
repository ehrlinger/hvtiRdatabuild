# Upstream cohort handoff to build and derive

**Date:** 2026-10-05
**Status:** Draft for review
**Scope:** Define the responsibility boundary for future inclusion, exclusion, and attrition
information supplied by an upstream cohort source to `hvtiRdatabuild`.

## 1. Purpose

The future build process is expected to receive more than a selected set of cohort members.
It should also receive the inclusion and exclusion criteria that produced that cohort and the
attrition information recorded while those criteria were applied. This note proposes how that
information moves through the build and the study-specific variable-derivation step.

This design does not select an upstream system, define a serialized schema, or implement a
cohort builder. Those decisions depend on the upstream source and are listed as open questions.

## 2. The responsibilities are distinct

Three operations are involved, and the word *cohort* can refer to more than one of them:

1. **Upstream cohort selection** applies the source's inclusion and exclusion rules and records
   the resulting membership and attrition.
2. **Build** uses that selected cohort to assemble the dataset from its source modules. It
   preserves the upstream criteria and attrition context; it does not silently apply the same
   rules again.
3. **Study-level derivation** may apply additional study-specific exclusions and derive
   analysis variables. Additional exclusions are appended to the attrition history and their
   difference from upstream criteria is reported, not rejected by default.

This preserves the current distinction between the permanent built dataset and optional
study-level variables, while allowing the later derivation step to reconcile cohort rules from
both sources.

## 3. Proposed handoff

The upstream-to-build handoff carries a cohort packet with these conceptual parts:

- the selected cohort membership used for the build;
- the ordered inclusion and exclusion rules, with their reasons and source provenance; and
- the attrition state produced by applying those rules, including the counts needed to explain
  membership changes.

There is not yet a defined upstream cohort tracker or handoff object. `hvtiRdatabuild` will
define a package-owned, in-memory `cohort_record` with two components:

- **`stages`**: one row per ordered step, with a stable stage key, order, label, source
  (`upstream`, `build`, or `derive`), and provenance for the criterion or operation;
- **`members`**: one row per patient at each stage they enter, with the patient identifier,
  stage key, pass/exclusion outcome, and exclusion reason when excluded.

An excluded patient has no outcome row for later stages. This preserves sequential attrition
and prevents double counting. Stage totals are calculated from `members`; they are not stored
as independent values that can disagree with patient-level outcomes. The exact R column types
and provenance fields are implementation details, but these two tables and their semantics
are part of the contract.

The record is data-package output; `hvtiRdatabuild` must not depend on `hvtiPlotR` to construct
it. The existing `hv_consort_tracker` in `hvtiPlotR` is a downstream consumer that may use the
patient-level build and cohort record to produce CONSORT summaries and figures. Any adapter
belongs on the consumer side. Patient identifiers remain runtime data and must not be printed
or committed.

`build_dataset()` consumes the selected membership when joining cohort records to source
modules. It creates the package's patient-level build and records the upstream criteria and
attrition state in the new cohort record. It must not reapply upstream rules in a way that
changes their recorded meaning. If a source join changes membership unexpectedly, the build
should surface a cohort discrepancy rather than silently treating the result as equivalent.

The optional `derive_vars()` step receives the built data and its cohort record. It can apply
local exclusions and variable derivations. Local exclusion rules are appended to the record
after the upstream rules, in their actual application order. The design continues to allow
study-specific exclusions beyond the upstream criteria and to report that divergence rather
than forbid it.

The existing notes do not settle whether local exclusions always precede or follow every
variable derivation. That order may depend on whether a rule uses a derived variable and must
be specified by the eventual execution contract.

## 4. Data flow

```text
upstream cohort source
  → selected membership + ordered criteria + attrition state
  → build_dataset(): join cohort to source modules; create patient-level data and cohort record
  → optional derive_vars(): append study-level exclusions; derive analysis variables
  → dataset and auditable cohort/attrition record
  → hvtiPlotR may consume the data and record for summaries or figures
```

The existing `study.yaml` fields (`cohort_table`, `modules`, `varsets`, and `derive`) do not
yet describe this packet. This design does not add speculative configuration keys. The config
shape should follow once the upstream source and runtime handoff are known.

## 5. Safety and integrity requirements

- Patient identifiers and row-level membership evidence remain runtime data. They must not be
  written into this repository, committed fixtures, ordinary logs, or error messages.
- User-facing and failure summaries report counts, rule names, and verdicts only; they do not
  print patient values. Tests use invented data and check failure messages as well as results.
- Rule order is part of the recorded meaning. A patient excluded by an earlier rule must not
  be counted as newly excluded by a later rule.
- The build must preserve upstream provenance and distinguish upstream exclusions from
  study-level additions.
- Missing or inconsistent upstream criteria and attrition information must not be silently
  interpreted as an empty history. The runtime contract must define whether a given source
  requires this information and what constitutes a hard error.

## 6. Naming consequence

`transforms` is too narrow for the full optional step if it also receives cohort context,
reconciles study-level exclusions, and appends attrition. `derive` or `derive-vars` remains a
better working name for this step. If exclusions become an independently runnable operation,
that is a separate design decision; this handoff does not require a standalone `cohort` job.

## 7. Open decisions before implementation

1. **Upstream producer:** Which cohort source produces the packet, and does it provide the
   actual selected membership, criteria, attrition, or all three?
2. **Transfer mapping:** How does the upstream producer express its selected membership,
   ordered criteria, decisions, reasons, and provenance in the `cohort_record` contract?
3. **Build interface:** Is the packet passed directly to `build_dataset()`, returned by
   `dw_pull()`, or stored in a source-side object referenced by the study config?
4. **Cohort freeze:** What source version, extraction time, or checksum identifies the exact
   upstream membership and criteria used for a build?
5. **Join validation:** Which row-identity and cardinality checks prove that source-module
   joins preserve the selected cohort, including legitimate one-to-many modules?
6. **Rule execution order:** Which local exclusion rules depend on derived variables, and how
   is that ordering declared and recorded?
7. **Optionality and compatibility:** Which sources require the new metadata, and how are
   existing studies handled while upstream adoption is phased in?
8. **Result shape:** Is the new cohort record returned with the data, as a separate result
   component, or both? Whichever form is chosen must remain available when derivation is
   skipped.

## 8. Related decisions

- The dataset migration design assigns source assembly to `build_dataset()` and the `%vars`
  port to `derive_vars()`.
- The vars port design makes the attrition record a first-class output and allows local
  criteria to diverge from upstream criteria while reporting the difference.
- The build-layer capture distinguishes permanent variables created during build from
  variables created only when the optional vars macro is invoked.

This note resolves the responsibility boundary and the conceptual `cohort_record` shape. It
does not supersede those designs or claim that its open implementation questions are settled.
