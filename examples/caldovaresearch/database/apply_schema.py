#!/usr/bin/env python3
"""Apply an approval-gated Potion 512 template to the target database."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

from deploy_common_schema import connect, database_token

GATE_PATTERN = re.compile(r"(DECLARE\s+@DeploymentApproved\s+BIT\s*=\s*)0(\s*;)", re.IGNORECASE)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("template", type=Path)
    parser.add_argument("--server", required=True, help="Logical server FQDN.")
    parser.add_argument("--database", required=True)
    args = parser.parse_args()

    script = args.template.read_text(encoding="utf-8")
    approved, replacements = GATE_PATTERN.subn(r"\g<1>1\g<2>", script)
    if replacements != 1:
        parser.error(f"Expected exactly one approval gate; found {replacements}.")

    with connect(args.server, args.database, database_token()) as connection:
        connection.timeout = 600
        connection.cursor().execute(approved)

    print(f"applied {args.template.name} to {args.server}/{args.database}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
