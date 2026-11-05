# Local DAB RLS configuration

[dab-config.rls.json](dab-config.rls.json) supports the
[Row-Level Security walkthrough](../README.md).

Read the parent instructions for the intended local process, endpoint, identity,
and session-context flow before using this file. It is a demo configuration,
not a blanket authorization model for other applications.

Keep private connection details and credentials outside committed configuration.
Verify access under the intended identities and preserve the parent's cleanup
and rollback procedure when changing RLS behavior.
