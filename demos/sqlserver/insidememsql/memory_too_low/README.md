# Demo for Memory too low for SQL Server

## WARNING: DO NOT TRY THIS ON A PRODUCTION SERVER. PLEASE USE A VM, your laptop, or a test machine you have exclusive access to

- Deploy SQL Server 2019 on Windows
- Start SQL Server
- Load up Performance Monitor and add these counters
    - Total Server Memory
    - Target Server Memory
- Set 'max server memory' to 128
- Notice in perfmon the Target drops below the Total. This is because the Total memory is "fixed" and cannot be trimmed
- If you try to run sp_configure to fix it you will get a 701 error. SQL can't allocate any fixed memory to even service a query or connection.
- Notice in the ERRORLOG out of memory errors
- You have to kill the SQLSERVR.EXE. You can't even stop the service
- To fix this, start SQL Server from the command line like the following

`sqlsevr -c -f -m"Microsoft SQL Server Management Studio - Query"`

- In SSMS, use File/New Query to get a query window and set 'max server memory' to 0. Restart SQL Server.
