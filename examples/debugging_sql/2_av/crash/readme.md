# Access-violation reproduction source

Supporting native source for the [access-violation lab](../readme.md):
[crash.cpp](crash.cpp) and its local [winnt.h](winnt.h) header.

Read the parent walkthrough before building or loading this code. It exists
to support a controlled failure, not as a general utility. Building native
code requires a compatible Windows C++ toolchain; verify the architecture and
the parent's loading instructions instead of assuming a standalone executable.

Never run crash reproductions in production. Preserve the lab's diagnostic
evidence and follow the parent lab's teardown.
