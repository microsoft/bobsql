# Scheduler-deadlock reproduction

Start with the original [readme.txt](readme.txt) and the
[hang investigation](../readme.md). This folder contains a deliberate
scheduler-hang lab, DMV queries, DAC/debugger helpers, and cleanup scripts.

Use an isolated Windows SQL Server instance with administrative access,
SSMS/sqlcmd, and the debugger tools named in the walkthrough. Check all script
paths and instance names first. Keep a separate diagnostic/DAC session ready
before starting the reproduction; ordinary connections can become unresponsive.

Capture diagnostics before using [cleanuphang.cmd](cleanuphang.cmd) or
[cleanup_setup_hang.sql](cleanup_setup_hang.sql). Read their contents and confirm
their targets before execution. A restart may be necessary in a disposable lab.
