I have a SQL Server 2017 instance running on my Windows 10 laptop. I made no changes to the default install. My laptop has 32Gb RAM with a single socket 4 core HT CPU (8 logical CPUs). I have 2 1TB PCI-NVMe drives with the laptop.

One aspect to this demo that is amazing is that everthing is running on the same computer (client driver, SQL Server, ...)

If you don't get to 1M tpm it is likely caused by not a fast enough disk to handle the load (especially tlog). My PCI NVMe SSD has avg write latencies of 1ms or less.

1. Use the scripts provided to create and load a database called tpcc_workload which will be used by HammerDB. The scripts assume a directory within tpcc_workload called inputfiles. I don't supply these here because of their size. But you can use HammerDB to do that. I built this database using HammerDB options for datagen to 50 warehouses

2. Install HammerDB (the latest build was v2.23). You can find it at www.hammerdb.com.

3. Launch HammerDB (hammerdb.bat)

You can use the supplied config.xml file in place of the default to make SQL Server the default

4. Select Driver Script\Options to pick

correct instance name
Change database name to tpcc_workload
Click on Load subtree option

5. For Virtual Users\Options

Type in 8 Virtual Users
100 Iterations
Click on Create subtree option

6. Select Transactions\Options

Instance name should already be the one in Step 4 but confirm
Type in Refresh Rate of 2 secs
Check Autorange Data Points
Click on Counter SubTree option

7. Click on Green Arrow Button to Run

8. Observe TPM hits 1M fairly quick and sustains itself there

9. Let's bump this to 25 users and see if we can maintain speed. What about 100?

10. Let's see how we are affected when we add other "stuff"

--> Use the new XEProfiler
--> Enable Query Store

Observe performance

Only if time

10. Let's see the affects an online index build while we are running at full speed. Stop the workload onHammerDB and reconfigure for 8 virtual users.

11. Load up these two scripts in SSMS

rebuild_indexes_online.sql
pause_my_index.sql

12. Start up the HammerDB virtual users again (that you have configured for 8)

13. Run the commands in rebuild_indexes_online.sql to ALTER the INDEX. With the workload running this takes about 12 seconds.

Observe the impact on performance of the HammerDB workload. Run the command to pause the index in pause_my_index.sql after about 6 seconds.

Note the output of the catalog view showing it was paused.

Observe performance went back up to what it was before.

Now run the ALTER INDEX command again to restart the index. Note the output of the DMV showing it is back running again and its progress









