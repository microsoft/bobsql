Prereqs

VS 2022 Community Edition
Nuget packages for Microsoft.Data.SqlClient and System.Configuration.Configuration Manager
Use VS to Add a new item for an Application Configuration file
Start with Azure SQL server not allowing Azure access


1. Show the bwazuresqldbgp database in the Azure portal. Show the server name to connect to.
2. Bring up the SQLSecurity project in Visual Studio in our Azure VM running Windows 11.
3. Show the connection string to connect to the server. Go over pieces of the connection string.
4. Try to run the program and show the error we cannot connect
5. Go to the portal and use the Firewall and virtual networks setting to Allow Azure services. Talk about the various connectivity options including firewalls.
6. Run the program again and see it connect.
7. Show AAD auth in the portal for the server.
8. Show script execconnections and show properties of our connection including encryption is TRUE even though we didn't specify it on the client and our IP address which matches the public IP address of the Azure VM (or whatever IP you are using).
9. Uncomment the code to show how an injection works. Run the program and put in a valid SalesOrderNumber like SO71774
10. Show how the query is constructed in the code
11. Switch to sqli.ipynb and show in the first 2 cells how to construct malicious code
12. Switch back to the app and put a breakpoint on this line

qlDataReader reader = command.ExecuteReader();

13. Now debug and put in this as your input

bob' or 1=1--

14. Show the resulting query in the watch window
15. Hit continue and see the results
16. Disable the breakpoint
17. Run the code again but this time put in this value

bob'; drop table SalesLT.SalesOrderHeader2--

18. Go back into ADS and see the table is gone
19. Run selinto.sql to recreate the table
20. Comment out the code that is bad and uncomment the code to use parameters. Show the code
21. Launch Profiler in ADS
22. Run the program and see no results. Show how sp_executesql is used and that the injected code is now part of the "string" for a SalesOrderNumber and why results are empty.
23. Finally go into the portal and see you have an injection alert detected by Defender1



