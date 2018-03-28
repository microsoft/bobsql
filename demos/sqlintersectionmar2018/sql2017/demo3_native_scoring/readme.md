This demo shows the Native Scoring feature of SQL Server 2017

This demo pulls SQL commands from the main site for a rental prediction tutorial using Python which you can find at https://microsoft.github.io/sql-ml-tutorials/python/rentalprediction/. Use this site for the entire tutorial in case any changes or additions are made there. If you want to use Native Scoring as a feature you do not have to install the Machine Learning Services feature but this demo will require it because we train the model using Python with SQL Server.

As with that site, in order to run this demo you will need:

- SQL Server 2017 for Windows installed (Developer Edition will work just fine). You must choose the Machine Learning Services feature during installation (or add this feature if you have already installed)
- You need to download the TutorialDB database from https://sqlchoice.blob.core.windows.net/sqlchoice/TutorialDB.bak
- Enable this configuration option and restart SQL Server

EXEC sp_configure 'external scripts enabled', 1;
RECONFIGURE WITH OVERRIDE

 


