# Buffer-latch lab

Start with [readme.txt](readme.txt). The scripts inspect buffers, pages, request
states, and latch classes while a lab insert workload runs.

Use an isolated SQL Server instance, SSMS/sqlcmd, and any inspection tools
specified in the text walkthrough. Review [bufsandpages.sql](bufsandpages.sql),
[dbccpage.sql](dbccpage.sql), and [insertbears.cmd](insertbears.cmd) for
database names and workload settings first.

DBCC PAGE and internal latch/debugger details are version-sensitive educational
tools, not supported production repair instructions. Stop the workload and
close lab transactions after collecting evidence. Captured images illustrate
one run and are not current measurements.
