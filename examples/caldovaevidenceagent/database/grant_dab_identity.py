#!/usr/bin/env python3
"""Grant the DAB identity only approved procedures and the embedding model."""

from __future__ import annotations

import argparse

from deploy_database import connect


def quote_identifier(value: str) -> str:
    return "[" + value.replace("]", "]]" ) + "]"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--subscription", required=True)
    parser.add_argument("--server", required=True)
    parser.add_argument("--database", default="research")
    parser.add_argument("--identity-name", required=True)
    parser.add_argument("--identity-object-id", required=True)
    parser.add_argument("--foundry-endpoint", required=True)
    args = parser.parse_args()

    identity = quote_identifier(args.identity_name)
    object_id = args.identity_object_id.replace("'", "''")
    credential = quote_identifier(args.foundry_endpoint.rstrip("/") + "/")
    with connect(args.server, args.database, args.subscription) as connection:
        cursor = connection.cursor()
        cursor.execute(
            f"""
IF DATABASE_PRINCIPAL_ID(N'{args.identity_name.replace("'", "''")}') IS NULL
    CREATE USER {identity} FROM EXTERNAL PROVIDER WITH OBJECT_ID = '{object_id}';
IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_role_members AS role_member
    WHERE role_member.role_principal_id = DATABASE_PRINCIPAL_ID(N'CaldovaEvidenceReader')
      AND role_member.member_principal_id = DATABASE_PRINCIPAL_ID(N'{args.identity_name.replace("'", "''")}')
)
    ALTER ROLE CaldovaEvidenceReader ADD MEMBER {identity};
GRANT EXECUTE ON EXTERNAL MODEL::CaldovaEvidenceEmbedding TO CaldovaEvidenceReader;
GRANT REFERENCES ON DATABASE SCOPED CREDENTIAL::{credential} TO CaldovaEvidenceReader;
"""
        )
        connection.commit()

        permissions = cursor.execute(
            "SELECT permission_name, state_desc FROM sys.database_permissions "
            "WHERE grantee_principal_id = DATABASE_PRINCIPAL_ID(N'CaldovaEvidenceReader') "
            "ORDER BY permission_name;"
        ).fetchall()
        actual_permissions = sorted((row[0], row[1]) for row in permissions)
        expected_permissions = sorted([("EXECUTE", "GRANT")] * 4 + [("REFERENCES", "GRANT")])
        if actual_permissions != expected_permissions:
            raise RuntimeError(f"Unexpected CaldovaEvidenceReader permissions: {permissions}")

    print(f"Granted {args.identity_name} membership in CaldovaEvidenceReader.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
