# Cut a release: `just release 1.2.3` (no leading v).
# Refuses dirty trees, unpushed HEADs, and versions missing from CHANGELOG.md;
# the pushed tag triggers .github/workflows/release.yml, which re-verifies the
# module and publishes the GitHub Release from the changelog section.
release version:
    #!/usr/bin/env bash
    set -euo pipefail
    v="{{ version }}"
    [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must be X.Y.Z (no leading v)" >&2; exit 1; }
    [ -z "$(git status --porcelain)" ] || { echo "working tree is dirty" >&2; exit 1; }
    git fetch origin master
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/master)" ] || { echo "HEAD must match pushed origin/master" >&2; exit 1; }
    grep -q "^## \[$v\]" CHANGELOG.md || { echo "CHANGELOG.md has no ## [$v] section" >&2; exit 1; }
    git tag -a "v$v" -m "v$v"
    git push origin "v$v"
    echo "Pushed v$v — the Release workflow will publish the GitHub release."
