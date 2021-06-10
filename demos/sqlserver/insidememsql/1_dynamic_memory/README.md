# Demo for Dynamic Memory Management for SQL Server

- Deploy SQL Server 2019 on Windows
- Create a database and populate a table that will take up around 5Gb
- Restart SQL Server
- Load up Performance Monitor and add these counters (chart scale is 0 to 1000)
    - Private Bytes for SQLSERVR.EXE (Scale 0.00000001)
    - Total Server Memory (Scale 0.00001)
    - Target Server Memory (Scale 0.00001)
- Set 'max server memory' to around 5Gb
- Notice in perfmon the Target is around 5Gb but the total is very low (fixed memory required by the server at startup)
- Run a query that scans the entire table you built
- Notice the Total memory will go up to the Target but never go past it
- Private bytes is just a bit larger than Total Memory
- Let the query finish. Now set 'max server memory' to 1Gb
- Notice the Target and Total go down along with Private bytes as we deallocate memory
- Change 'max server memory' back to 5Gb. See the Target go back up but not the total. If you run the query again the total will go back up but not exceed the Target (ceiling)
- Reset 'max server memory' to 0 and shutdown SQL Server