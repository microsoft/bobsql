#!/bin/sh
set -eu

if ! command -v gitleaks >/dev/null 2>&1; then
    echo "Install gitleaks first. See SECRET-SCANNING.md." >&2
    exit 1
fi
root=$(git rev-parse --show-toplevel)
cd "$root"
existing=$(git config --get core.hooksPath || :)
if [ -n "$existing" ] && [ "$existing" != ".githooks" ]; then
    echo "Refusing to replace existing hooksPath: $existing" >&2
    exit 1
fi
chmod +x .githooks/pre-commit .githooks/pre-push
git config --local core.hooksPath .githooks
echo "Enabled pre-commit and pre-push secret checks for this checkout."
gitleaks version
