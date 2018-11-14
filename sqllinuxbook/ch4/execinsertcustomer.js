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

connection.on('connect', function(err) {  
    // If no error, then good to proceed.  
   console.log("Connected to SQL Server Successfully");  
   InsertCustomer();
});  

function InsertCustomer() {  
    request = new Request("[Sales].[InsertCustomer]", function(err) {  
    if (err) {  
        console.log(err);}
    else
        console.log('Inserted new Customer');
     }
    );

    request.addParameter('PrimaryContactID', TYPES.Int, 1);
    request.addParameter('AlternateContactID', TYPES.Int, 1);
    request.on('requestCompleted', ()=>{connection.close();});
    connection.callProcedure(request);
}