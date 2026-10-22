# Optional metrics tooling

Last updated: 2026-10-22

The original metrics tooling is preserved for future reuse. It is disconnected
from the profile README, and no metrics workflow is installed in
`.github/workflows/`.

- [compute_loc.sh](compute_loc.sh) generates `metrics/loc.md` from repository
  histories and `metrics/system.yml`.
- [system.yml](../metrics/system.yml) preserves the original configuration.
- [loc.md](../metrics/loc.md) is the original historical output, not a current
  measurement.
- [loc-metrics.workflow.yml](archive/loc-metrics.workflow.yml) preserves the
  complete original workflow, including its schedule and README injection step.
  GitHub Actions does not load workflows from this archive directory.

The script counts repository history across all authors, includes generated and
vendored text, and reads container counts from configuration. Its output must not
be presented as individual engineering impact or measured running infrastructure.
It also clones full repository histories, so check the local storage budget before
running it.

To revisit the automation, review these limitations and the intended output first.
Restoring the archived file to `.github/workflows/loc-metrics.yml` would restore
its Monday schedule. Its injection step also requires the old README markers;
keep that step removed if metrics should stay separate from the profile.

Only a Bash syntax check has been run on the preserved script during this change.
No repositories were cloned, metrics regenerated, or workflow run.
