# Development Reports

Evidence-based milestone reports documenting what changed in this repository, why, and with what verification.

## Purpose

Each report records a bounded period of work: goals, completed/partial/deferred work tied to audit findings or plans, build and test evidence, unexpected discoveries, decisions, lessons, and handover context — enough for a future engineer or AI coding agent to continue safely without access to the conversations that produced the work.

## Conventions

- **Location:** `docs/development-reports/`
- **Filename:** `YYYY-MM-DD-<short-milestone-slug>.md` (repository date at report creation). Never overwrite an existing file; choose a unique descriptive name.
- **Index:** every report gets one row in [INDEX.md](INDEX.md), reverse-chronological.
- **Metadata:** YAML front matter with `report_id`, `title`, `date`, `stage`, `status`, `branch`, `from_commit`, `to_commit`, `working_tree_clean`, `previous_report`, `related_audit`, `related_findings`, `generated_by`. Use `null` (and an explanation in the body) when a value cannot be determined — never fabricate.
- **Baseline selection:** a report's starting commit is the previous report's `to_commit`. For the first report, the baseline is inferred from tags/audit history and labeled as an initial retrospective baseline.

## Immutability

Reports are **immutable historical records**: earlier reports are not edited or deleted. Corrections are made in a later report that references the error. Superseded reports are noted in the index, not removed.

## Distinctions

- **Reports vs. changelogs:** reports are evidence-backed retrospectives with verification status and lessons; release notes/changelogs are user-facing summaries (see `RELEASE_NOTES.md`).
- **Reports vs. audit findings:** audits catalog defects with IDs (F-*, O-*, AN-*); reports record which findings were addressed in a period and how they were verified. In this repository, audit documents are internal (untracked by policy); reports are tracked and cite them as internal evidence.
- **Reports vs. ADRs:** decisions with architectural significance are summarized in reports; an ADR is recommended (and created separately) only when a decision is long-lived, cross-cutting, or expensive to reverse.
- **Reports vs. issue tracking:** this repository does not use an issue tracker; finding IDs in audit documents serve that role.
