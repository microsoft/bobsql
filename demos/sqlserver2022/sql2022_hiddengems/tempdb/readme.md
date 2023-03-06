# Exercise for "hands-free" tempdb in SQL Server 2022

Follow these steps for an exercise to see system page latch concurrency enhancements for SQL Server 2022.

## Prerequisites

- SQL Server 2022 Evaluation or Developer Edition
- VM or computer with 4 CPUs and at least 8Gb RAM.
- SQL Server Management Studio (SSMS). The latest 18.x build or 19.x build will work.
- Download **ostress.exe** from https://aka.ms/ostress. Install using the RMLSetup.msi file that is downloaded. Use all defaults.

## Setup the exercise

1. Configure perfmon to track SQL Server **SQL Statistics:SQL Statistics/Batch requests/sec** (set Scale to 0.1) and **SQL Server:Wait Statistics/Page latch waits/Waits started per second**.
1. Execute the script **findtempdbfiles.sql** and save the output. A script is provided for the end of this exercise to restore back your tempdb file settings.
1. Start SQL Server in minimal mode using the command script **startsqlminimal.cmd**
1. Execute the command script **modifytempdbfiles.cmd**. This will execute the SQL script **modifytempdbfiles.sql** to expand the log to 200Mb (avoid any autogrow) and remove all tempdb files other than 1. If you have more than 4 tempdb files you need to edit this script to remove all of them except for tempdev.

    **IMPORTANT:** If you are using an named instance you will need to edit all the .cmd scripts in this exercise to use a named instance. All the scripts assume a default instance.

## Exercise 1: Observe performance of a tempdb based workload without metadata optimization and without new SQL Server 2022 enhancements

1. Run **disableopttempdb.cmd** and then **disablegamsgam.cmd** from the command prompt.

    **Note**: This will ensure tempdb metadata optimization is OFF and turn on two trace flags to disable GAM/SGAM concurrency enhancements. These trace flags are not documented and not supported for production use. They are only use to demonstrate new built-in enhancements.

1. Load the script **pageinfo.sql** into SSMS
1. Run **tempsql22stress.cmd 25** from the command prompt.
1. Execute **pageinfo.sql** from SSMS and observe that all the latch waits are for system table page latches
1. Observe perfmon stats
1. Observe final duration elapsed from **tempsql22stress.cmd**

## Exercise 2: Observe performance with tempdb metadata optimization enabled but without new SQL Server 2022 enhancements

1. Run **optimizetempdb.cmd**
1. Run **disablegamsgam.cmd**
1. Load the script **pageinfo.sql** into SSMS
1. Run **tempsql22stress.cmd 25** from the command prompt.
1. Execute **pageinfo.sql** from SSMS and observe that all the latch waits are for GAM pages.
1. Observe perfmon stats
1. Observe final duration elapsed from **tempsql22stress.cmd 25**

## Exercise 3: Observe performance with tempdb metadata optimization enabled and with new SQL Server 2022 enhancements

You could setup SQL Server with only one tempdb data file so one thing you could do is add more files. However, SQL Server 2022 includes enhancements to avoid latch contention for GAM and SGAM pages.

1. Execute the command script **restartsql.cmd**

    Tempdb metadata optimization is already enabled and by restarting you are no longer using trace flags to disable new SQL Server 2022 enhancements.

1. Load the script **pageinfo.sql** into SSMS
1. Run **tempsql22stress.cmd 25** from the command prompt.
1. Execute **pageinfo.sql** from SSMS and observe there are no observable latch waits
1. Observe perfmon stats
1. Observe final duration elapsed from **tempsql22stress.cmd 25**

You have now achieved maximum performance with tempdb workloads and did not have to do any special configuration for tempdb files. 

**Tip**: This exercise showed that you no longer may have to create multiple tempdb files for avoid system page latch contention. However, it is recommend to use the default setting from SQL Server setup for the number of files. I have run this same exercise on a 4 CPU machine with 4 files. With tempdb metadata optimization ON and using the new GAM/SGAM enhancements I got similar results from just using 1 file.

If you want to restore your tempdb file settings you can perform the following steps:

1. Edit the **restoretempdbfiles.sql** script to add or remove any extra files.
1. Execute the command script **restoretempdbfiles.cmd**. The script will display **Changed database context to 'master**' and exit back to the command prompt.
1. Execute the command script **restartsql.cmd**
1. Execute the script **findtempdbfiles.sql** to ensure your files are back to the correct configuration.