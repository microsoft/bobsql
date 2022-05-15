# System page latch concurrency enhancements in SQL Server 2022

Follow these steps to demonstrate system page latch concurrency enhancements for SQL Server 2022

## Prerequisites

- VM with at least 8 CPUs and 24Gb RAM
- SQL Server 2022 CTP 2.0
- During setup configure 1 tempdb data file at 50Gb and 1 tempdb log file at 120Gb
- SQL Server Management Studio (SSMS) Version 19 Preview
- Download ostress.exe from https://www.microsoft.com/en-us/download/details.aspx?id=103126

## Setup the demo

1. Configure perfmon to track batch requests/sec and Page latch waits/Waits started per second

## Observe performance of a tempdb based workload without metadata optimization and without new SQL Server 2022 enhancements

1. Run .\disableoptimizetempdb.cmd and then .\disablegamsgam.cmd

Note: This will ensure tempdb metadata optimization is OFF and turn on two trace flags to disable GAM/SGAM concurrency enhancements. These trace flags are not documented and not supported for productio use. They are only use to demonstrate new built-in enhancements.

2. Run tempsql22stress.cmd 100
3. Observe perfmon stats
4. Execute pageinfo.sql from SSMS and observe that all the latch waits are for system table page latches
5. Observe final duration elapsed from tempsql22stress.cmd

## Observe performance with tempdb metadata optimization enabled but without new SQL Server 2022 enhancements

6. Run .\optimizetempdb.cmd
7. Run .\disablegamsgam.cmd
8. Run tempsql22stress.cmd 100
9. Observe perfmon stats. Performance is worse even with tempdb metadata optimization enabled
10. Execute pageinfo.sql from SSMS and observe that all the latch waits are for GAM pages.
11. Observe final duration elapsed from tempsql22stress.cmd. It is worse than without any optimization

## Observe performance with tempdb metadata optimization enabled and with new SQL Server 2022 enhancements

You could setup SQL Server with only one tempdb data file so one thing you could do is add more files. However, SQL Server 2022 includes enhancements to avoid latch contention for GAM and SGAM pages.

12. Restart SQL Server

Tempdb metadata optimizatio is already enabled and by restarting you are no longer using trace flags to disable new SQL Server 2022 enhancements.

13. Run tempsql22stress.cmd 100
14. Observe perfmon stats. Performance is greatly increased with no observable latch waits
15. Execute pageinfo.sql from SSMS and observe there are not latch waits
16. Observe final duration elapsed from tempsql22stress.cmd. It is significantly faster than all other tests.

You have now achieved maximum performance with tempdb workloads and did not have to do any special configuraiton for tempdb files. 

Note: This demo showed that you no longer may have to create multiple tempdb files for avoid system page latch contention. However, it is recommend to use the default setting from SQL Server setup for the number of files.




9. Run .\optimizetempdb.cmd
10. Run tempsql22stress.cmd 100
11. Observe perfmon stats and final duration. No latch waits and the best performance.