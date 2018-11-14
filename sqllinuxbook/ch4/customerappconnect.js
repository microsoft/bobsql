var Connection = require('tedious').Connection;
var Request = require('tedious').Request;
var TYPES = require('tedious').TYPES;

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

// Attempt to connect to the SQL Server on Linux
connection.on('connect', function(err) {
  if (err) {
    console.log(err);
  } else {
    console.log('Connected to SQL Server successfully');
    connection.close();
  }
});