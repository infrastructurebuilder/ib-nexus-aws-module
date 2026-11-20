# ib-nexus-aws-module Constitution

## Core Principles

### I. Secure by Default, Secrets Out of State

- The module MUST NOT read a secret's value. It may read a secret's metadata, and the
  instance fetches the value itself at boot. No secret may appear in state, in user-data
  or in an output.
- Every default MUST be the safe choice: TLS at the load balancer, the instance in a
  private subnet with no SSH, encrypted volumes, and IAM policies scoped to the named
  resource.
- The security scan MUST pass at HIGH and CRITICAL. A finding may be ignored only inline,
  with a written justification next to the ignore.

Rationale: consumers apply this module with their own state backends and logs. Whatever
reaches state or user-data is readable by everyone who can read those.

### II. Data Outlives the Instance

- Nexus data lives on a dedicated data volume and in the blobstore bucket, never on the
  root volume. Replacing the instance MUST NOT lose either.
- A change that would replace or destroy the data volume or the blobstore bucket is a
  breaking change under Principle IV. The changelog MUST give the steps to apply it safely.
- The blobstore bucket MUST keep `prevent_destroy`.

Rationale: the instance is disposable by design, because upgrades and recovery both
replace it. That is safe only while the database and the blobs sit outside it.

### III. Infrastructure Only, With a Clear Boundary

- The module builds the infrastructure Nexus runs on. Configuring Nexus itself (blob
  stores, repositories, roles, users) is out of scope and MUST NOT be added here.
- Whatever a downstream module needs in order to configure Nexus MUST be exported as an
  output, so that nothing has to be copied by hand.
- The module deploys into infrastructure it does not own. Each prerequisite MUST be
  documented in the README, and a missing one MUST fail with a precondition that names it.

Rationale: keeping Nexus configuration out lets the infrastructure be replaced without
touching repositories, and lets the repositories module work against any Nexus.

### IV. A Stable, Versioned, Documented Interface

- Releases are tagged `vMAJOR.MINOR.PATCH`. Consumers pin a tag, never a branch. Release
  tags MUST NOT be moved or deleted.
- Every user-visible change MUST add an entry under `[Unreleased]` in `CHANGELOG.md`. A
  breaking change goes under a `BREAKING` heading, with migration steps.
- New capability MUST be opt-in and backward compatible within a major version. An input
  that is being retired stays accepted until the next major version and is documented as
  deprecated.
- Every variable and output MUST have a description, and a constrained variable MUST have
  a validation block. The README tables are generated from those descriptions and MUST NOT
  drift from the code.

Rationale: this module is applied to live deployments. A consumer has to be able to read
what an upgrade will do before running it.

### V. Checked Before Merge and Before Release

- The Justfile MUST provide `init`, `build`, `test`, `full-test` and `release`, and
  `release` MUST depend on `full-test`.
- `just test` MUST run what CI runs: formatting, validation of the module and of every
  example, the test suite, the linter, the security scan and the documentation drift
  check. It MUST pass before a change is merged.
- A new validation block or precondition MUST come with a test that triggers it. Tests run
  against mocked providers and MUST NOT need cloud credentials.
- A release MUST re-verify the module at the tagged commit and MUST NOT rely on an earlier
  run.

Rationale: one definition of "checked", used at the desk and in CI, means a green local
run predicts a green pipeline. Tags can be pushed without a pull request, so a release has
to prove itself.

## Compatibility and Layout

- The module supports Terraform 1.5 or later, `hashicorp/aws` 5.0 or later and
  `hashicorp/cloudinit` 2.3 or later. The test suite needs Terraform 1.7 or later for
  provider mocking. Raising a floor is a breaking change under Principle IV.
- The module sits at the repository root, with its resources in numbered files
  (`NN_topic.tf`), a working example in `examples/basic` and the tests in `tests/`.
- Provider lock files are not committed, because consumers manage their own. State files
  are never committed, and `*.tfvars` files are committed only under `examples/`.

## Development Workflow

- Features follow the Spec Kit sequence: `/speckit-specify`, `/speckit-plan`,
  `/speckit-tasks`, `/speckit-implement`. Their artifacts live in `specs/<NNN-name>/`.
- Every plan's Constitution Check MUST list Principles I to V and record a pass or a
  justified violation for each.
- Changes are kept small enough to review. Documentation and the changelog entry land with
  the change they describe.
- Features are developed on a `feature/<name>` branch and squash-merged into the
  integration branch, `develop`.
- Releases follow git-flow. A release is staged on a `release/<version>` branch and
  finished into `main`, where it is tagged. `main` is the production branch.
- The `master` branch is retired and replaced by `main`. Nothing may be based on `master`
  or pin it as a ref.
- Plans are not tracked in this repo. A root `PLAN.md` is a maintainer's local file and
  stays gitignored. The tracked record of a feature is its `specs/<NNN-name>/` directory.

## Governance

- This constitution takes precedence over other practice in this repository. Where a plan
  conflicts with it, either the plan changes or the constitution is amended first.
- An amendment is a change to this file with a stated rationale. It takes effect when a
  maintainer merges it.
- Versions follow semantic versioning. MAJOR removes or redefines a principle. MINOR adds a
  principle or a section, or materially expands one. PATCH clarifies wording.
- Compliance is checked in every plan's Constitution Check and again at review. A violation
  that is accepted MUST be justified in the plan's Complexity Tracking table.
- Day-to-day usage and operating guidance belongs in `README.md`.

**Version**: 1.0.1 | **Ratified**: 2026-11-20 | **Last Amended**: 2026-11-20
