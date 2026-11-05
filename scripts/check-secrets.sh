#!/bin/sh
set -eu

if ! command -v gitleaks >/dev/null 2>&1; then
    echo "BLOCKED: gitleaks is required. See SECRET-SCANNING.md for installation." >&2
    exit 1
fi

root=$(git rev-parse --show-toplevel)
cd "$root"

scan() {
    gitleaks git --config "$root/.gitleaks.toml" --redact=100 \
        --no-banner --ignore-gitleaks-allow --max-archive-depth 3 "$@" "$root"
}

case "${1:-}" in
    staged)
        scan --staged
        ;;
    push)
        # Git provides one input line per ref, including explicit refspec pushes.
        while read -r local_ref local_sha remote_ref remote_sha; do
            case "$local_sha" in
                *[!0]*) ;;
                *) continue ;;
            esac
            case "$remote_sha" in
                *[!0]*)
                    if ! git cat-file -e "$remote_sha^{commit}" 2>/dev/null; then
                        echo "BLOCKED: fetch the destination remote before pushing; its commit is unavailable locally." >&2
                        exit 1
                    fi
                    range="$remote_sha..$local_sha"
                    ;;
                *)
                    # A new remote ref has no trusted base; inspect all its history.
                    range="$local_sha"
                    ;;
            esac
            if ! git cat-file -e "$local_sha^{commit}" 2>/dev/null; then
                echo "BLOCKED: cannot scan a pushed ref that does not resolve to a commit." >&2
                exit 1
            fi
            echo "Scanning outgoing history for $local_ref -> $remote_ref" >&2
            scan --log-opts="--full-history $range"
        done
        ;;
    *)
        echo "Usage: sh scripts/check-secrets.sh staged|push" >&2
        exit 2
        ;;
esac
