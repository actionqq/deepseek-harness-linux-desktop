#!/usr/bin/env bash
# Rebase the Linux port onto upstream and report what still has to be verified.
# Usage: scripts/sync-upstream.sh [--apply]
#   without --apply  fetch and show the divergence, change nothing
#   with    --apply  fetch, then rebase the current branch onto upstream/master
set -euo pipefail

cd "$(dirname "$0")/.."

if ! git remote get-url upstream >/dev/null 2>&1; then
  git remote add upstream https://github.com/deepseek-ai/deepseek-harness
fi

git fetch upstream --tags

upstream_rev="$(git rev-parse --short upstream/master)"
branch="$(git branch --show-current)"
echo "upstream/master: $(git log -1 --format='%h %ci %s' upstream/master)"
echo "current branch:  ${branch}"

if [[ "${1:-}" != "--apply" ]]; then
  echo
  echo "Divergence (upstream/master..HEAD):"
  git log --oneline "upstream/master..HEAD" || true
  echo
  echo "Re-run with --apply to rebase ${branch} onto upstream/master."
  exit 0
fi

if [[ "${branch}" != "linux" ]]; then
  echo "Refusing to rebase ${branch}: switch to the linux branch first." >&2
  exit 1
fi

git rebase upstream/master

cat <<EOF

Rebased onto ${upstream_rev}. Remaining steps, in order:
  1. pnpm install                          # a lockfile conflict is resolved by regenerating
  2. pnpm --filter @deepseek-ai/dsh-desktop run check:package -- linux-x64
  3. pnpm run package:desktop:linux:x64:unsigned
  4. git tag -a linux-v<upstream-version>-<revision> -m "Linux desktop build for <upstream-version>"
  5. git push origin linux --tags

Kept in sync with apps/desktop/docs/linux-desktop.md (patch ledger).
EOF
