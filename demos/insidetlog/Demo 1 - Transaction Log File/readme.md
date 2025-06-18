# Example 1 - Transaction Log File

SQL Server 2022 will be used for examples.

## Example 1.1 - Physical Log File

1. Create a database in SSMS using the query editor with no options so all defaults are used

```sql
CREATE DATABASE defaultdb;
GO
```
2. Examine the default size and autogrow using the following query using the script **lookatlogfilesize.sql** in SSMS:


## Example 1.2 - Virtual Log File

1. Let's see how VLFs are created for a physical log file. Using the example in Example 1.1, let's see what VLFs look like by executing the following query:

```sql
SELECT * FROM sys.dm_db_log_info(DB_ID('defaultdb'));
```

Let's break down the output of this query:

- There are 4 VLFs in the log file
- The first VLF is "active" and the rest are "inactive" as you can see from vlf_active = 1 and vlf_status = 2. The active VLF is the one that is currently being written to.
- Notice the first VLF starts at physical offset 8192 bytes into the file because of the log file header page.
- Because the log header page takes up 8192 bytes the VLFs cannot be divided evenly so the first 3 VLFs are 1.92MB and the last one if 2.17MB. vlf_size_mb is "rounded" but if you calculate the differences for each vlf_begin_offset you can see the actual byte difference and it adds up to 8388608 which is 8MB.
- The vlf_sequence number is 43 for the active VLF because the last vlf_sequence_number for model was 42.
- The vlf_parity is 64 which is 0x40 or 01000000.
- The vlf_first_lsn is the first log record in the VLF which we will examine later

2. Let's see what VLFs look like for other sized databases. Bring up the script **lookatvlfs.sql** in SSMS and execute it. This script will create a database with a specific size and autogrow settings, then it will show the VLFs for that database.

-- A database log file of 64MB has 4 VLFs roughly 16Mb each
-- A database log file of 1GB has 8 VLFs roughly 128Mb each
-- A database log file of 2GB has 16 VLFs roughly 128Mb each
-- A database log file of 20GB has 16 VLFs roughly 1.28GB each

3. Let's see the VLF log header information in each VLF and what the "empty" VLFs look like

Here are the offsets for each VLF (your dbid may not be 5):

database_id	file_id	vlf_begin_offset

5	        2	    8192
5	        2	    2039808
5	        2	    4071424
15	        2	    6103040

a. Shutdown SQL Server
b. Use the list.exe program in hex mode to look at the log file

The first 2000 (hex) bytes are the log file header. So let's go at 2000 (hex) to see the VLF header.

The VLF header is actually 8192 bytes even though it does not take up a page but it is written as a page. Let's take a look at the first few bytes of the VLF header:

AB 40 05 00 2B 00 00 00

AB = This is the log file header signature used to see if there is disk sectore remapping. 1 byte
40 = This is the parity byte which is 0x40 used for this file.
00 05 (swapped) = This is a log format "version number". 2 bytes

00 00 00 2B (swapped) - This is the seqno of the VLF. 0x2B = 43 decimal which lines up in our DMV.

Notice at 0x3000 a bunch of 0xC0 values. This is how we "zero" the log to put in a known signature instead of just "00". TODO: Check with log grow looks like when we use IFI and how are we ok if we don't write 0xC0?. This blog post exlains why we use 0xC0 now https://learn.microsoft.com/en-ca/archive/blogs/psssql/sql-2016-it-just-runs-faster-ldf-stamped but how can we rely on IFI now if we don't write 0xC0? I've asked Peter and Purvi.

So the first log block is at 4000 (hex). 
At 4000 hex, notice the first byte is 0x50. This is the parity bytes of 0x40 OR'd with 0x10 which indicates this the first 512 sector of the log block.

Go to 4200 which is the next 512 bytes and now you see 0x40. Go to 4E00 (hex) and you will see 0x48. The last sector of the log block is OR'd with 0x08.

This means the 1st log block is 4KB in size. You can see at 5000 at new log block.

iF you start scrolling down on the right side you can see strings which are part of log records.

## Usding DBTABLE to look inside

1. Use the script **dbtable.sql** to look at the log file and VLFs in a database. This script will show you the log file and VLFs in a database based on memory structure. WARNING: A completely undocumented and unsupported command.

```sql