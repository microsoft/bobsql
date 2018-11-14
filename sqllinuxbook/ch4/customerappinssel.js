var Connection = require('tedious').Connection;
var Request = require('tedious').Request;
var TYPES = require('tedious').TYPES;
var async = require('async');

// Create connection to database
var config = {
  userName: 'sqllinux',
  password: 'Sql2017isfast',
  server: 'bwsql2017rhel',
  options: {
      database: 'WideWorldImporters'
  }
}

console.log("Connecting to SQL Server");
var connection = new Connection(config);

function Start(callback) {
  console.log('Starting...');
  callback(null, 'Travis Wright', 'radtravis', 'twright');
}

function Insert(FullName, PreferredName, Logon, callback) {
  console.log("Inserting '" + FullName + "' into Table...");

  request = new Request(
    'INSERT INTO [Application].[People] ([FullName], [PreferredName], [IsPermittedToLogon], [LogonName], [IsExternalLogonProvider], [IsSystemUser], [IsEmployee], [IsSalesPerson], [LastEditedBy]) VALUES (@FullName, @PreferredName, 1, @Logon, 0, 1, 1, 0, 0);',
      function(err, rowCount, rows) {
      if (err) {
          console.log(err);
          callback(err);
      } else {
          console.log(rowCount + ' row(s) inserted');
          callback(null);
      }
      });
  request.addParameter('FullName', TYPES.NVarChar, FullName);
  request.addParameter('PreferredName', TYPES.NVarChar, PreferredName);
  request.addParameter('Logon', TYPES.NVarChar, Logon);

  // Execute SQL statement
  connection.execSql(request);
}

function Read(callback) {
  console.log('Reading Customer Contacts...');

  // Read all rows from table
  request = new Request(
  'SELECT c.[CustomerName], c.[WebsiteURL], p.[FullName] AS PrimaryContact FROM [Sales].[Customers] AS c JOIN [Application].[People] AS p  ON p.[PersonID] = c.[PrimaryContactPersonID];',
  function(err, rowCount, rows) {
  if (err) {
      console.log(err);
      callback(err);
  } else {
      console.log(rowCount + ' row(s) returned');
      callback(null);
  }
  });

  // Print the rows read
  var result = "";
  request.on('row', function(columns) {
      columns.forEach(function(column) {
          if (column.value === null) {
              console.log('NULL');
          } else {
              result += column.value + " ";
          }
      });
      console.log(result);
      result = "";
  });

  // Execute SQL statement
  connection.execSql(request);
}

function Complete(err, result) {
  if (err) {
      console.log(err);
  } else {
      console.log("Done!");
      connection.close();
  }
}

// Attempt to connect to the SQL Server on Linux
connection.on('connect', function(err) {
  if (err) {
    console.log(err);
    process.exit(1);
  } else {
    console.log('Connected to SQL Server successfully');

    // Execute all functions in the array serially
    async.waterfall([
      Start,
      Insert,
      Read
  ], Complete)
  }
});