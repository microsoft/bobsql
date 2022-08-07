# System page latch concurrency enhancements in SQL Server 2022

Follow these steps to demonstrate system page latch concurrency enhancements for SQL Server 2022

## Prerequisites

- SQL Server 2022 Evaluation Edition
- VM or computer with 4 CPUs and at least 8Gb RAM.
- SQL Server Management Studio (SSMS). The latest 18.x build or 19.x build will work.
- Download **ostress.exe** from https://aka.ms/ostress. Install using the RMLSetup.msi file that is downloaded. Use all defaults. Place C:\Program Files\Microsoft Corporation\RMLUtils in the system path.

## Setup the demo

1. Configure perfmon to track **SQLServer:SQL Statistics/Batch requests/sec** and **SQLServer: Wait Statistics/Page latch waits/Waits started per second**.
1. Execute the script **findtempdbfiles.sql** to find the names and configuration of all tempdb files.
1. Execute the script **startsqlminimal.cmd** to start SQL Server in minimal startup mode.
1. Execute the script **removetempdbfiles.sql** to remove all tempdb files except the default and log. If you have more than 4 tempdb files you will need to edit this script to remove all the files you found from findtempdbfiles.sql except the default data and log file.
1. Execute the script **restartsql.cmd** to restart SQL Server.
1. Execute the script **expandtempdblog.sql** to expand the size of the tempdb transaction log to avoid autogrow.

## Observe performance of a tempdb based workload without metadata optimization and without new SQL Server 2022 enhancements

1. Run **disableoptimizetempdb.cmd** and then **disablegamsgam.cmd** from the command prompt.

**Note**: This will ensure tempdb metadata optimization is OFF and turn on two trace flags to disable GAM/SGAM concurrency enhancements. These trace flags are not documented and not supported for production use. They are only use to demonstrate new built-in enhancements.

2. Run **tempsql22stress.cmd 25** from the command prompt.
1. Execute **pageinfo.sql** from SSMS and observe that all the latch waits are for system table page latches
1. Observe perfmon stats
1. Observe final duration elapsed from **tempsql22stress.cmd**

## Observe performance with tempdb metadata optimization enabled but without new SQL Server 2022 enhancements

6. Run **optimizetempdb.cmd**
7. Run **disablegamsgam.cmd**
8. Run **tempsql22stress.cmd 25**
1. 10. Execute **pageinfo.sql** from SSMS and observe that all the latch waits are for GAM pages.
1. Observe perfmon stats. Performance is worse even with tempdb metadata optimization enabled
11. Observe final duration elapsed from **tempsql22stress.cmd**. It is not that much better or even worse than before.

## Observe performance with tempdb metadata optimization enabled and with new SQL Server 2022 enhancements

You could setup SQL Server with only one tempdb data file so one thing you could do is add more files. However, SQL Server 2022 includes enhancements to avoid latch contention for GAM and SGAM pages.

Tempdb metadata optimization is already enabled and by restarting you are no longer using trace flags to disable new SQL Server 2022 enhancements for GAM and SGAM concurrency.

1. Execute the script **restartsql.cmd** to restart SQL Server.
1. Run **tempsql22stress.cmd 25**
1. Execute **pageinfo.sql** from SSMS and observe there are no observable latch waits
1. Observe perfmon stats. Performance is greatly increased with no observable latch waits
1. Observe final duration elapsed from **tempsql22stress.cmd**. It should be the fastest result of all the test with no latch contention.

You have now achieved maximum performance with tempdb workloads and did not have to do any special configuration for tempdb files.

**Note**: This demo showed that you no longer may have to create multiple tempdb files for avoid system page latch contention. However, it is recommend to use the default setting from SQL Server setup for the number of files.