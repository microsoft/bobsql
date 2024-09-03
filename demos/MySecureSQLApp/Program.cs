using Azure.Identity;
using Microsoft.Data.SqlClient;
using System;
using System.Data;

class Program
{
    static void Main(string[] args)
    {
        // Get the server name and database name
        string serverName = "bwsecuresqlserver.database.windows.net";
        string databaseName = "bwsecuresqldb";
        
        // Create a new DefaultAzureCredential object
        DefaultAzureCredential credential = new DefaultAzureCredential();

        // Create a new SqlConnectionStringBuilder object
        SqlConnectionStringBuilder builder = new SqlConnectionStringBuilder
        {
            DataSource = serverName,
            InitialCatalog = databaseName
        };

        // Create a new SqlConnection object with the updated connection string
        using (SqlConnection connection = new SqlConnection(builder.ConnectionString))
        {
            string input = string.Empty;

            // Set the access token for the SQL connection
            connection.AccessToken = credential.GetToken(new Azure.Core.TokenRequestContext(new[] { "https://database.windows.net/.default" })).Token;

            do
            {
                try
                {
                // Open the connection
                connection.Open();
                Console.WriteLine("Connected successfully.");

                    Console.Write("Enter SalesOrderNumber: (type 'quit' to exit): ");
                    input = Console.ReadLine() ?? string.Empty;
                    if (input != "quit")
                    {
                        Console.WriteLine("You entered: " + input);
                        Program.ExecuteQuery(connection, input);
                    }
               
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"Error: {ex.Message}");
                    connection.Close();
           
                }
            } while (input != "quit");
        }
    }

    static public void ExecuteQuery(SqlConnection connection, string SalesOrderNumber)
    {
        using (var command = new SqlCommand())
        {
            command.Connection = connection;
            command.CommandType = CommandType.Text;
            command.CommandText = @"SELECT PurchaseOrderNumber from SalesLT.SalesOrderHeader2 WHERE SalesOrderNumber = '" + SalesOrderNumber + "'";
            Console.WriteLine("Executing query: " + command.CommandText);

            SqlDataReader reader = command.ExecuteReader();

            Console.WriteLine("SalesOrderNumber returned = ");
            while (reader.Read())
            {
                Console.WriteLine("{0}", reader.GetString(0));
            }

            reader.Close();
        }
    }
}
