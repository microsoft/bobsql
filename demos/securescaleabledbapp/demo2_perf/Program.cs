using System;
using System.Text;
using System.Data;
using Microsoft.Data.SqlClient;
using System.Configuration;
namespace SQLPerformance
{
	public class Program
	{
		static public void Main(string[] args)
		{
			// Read the connection string from the app.config file
			string connString;
			ConnectionStringSettings settings = ConfigurationManager.ConnectionStrings["ConsoleAppConnectiongp"];
			connString = settings.ConnectionString;

			// Run 25 concurrent workers
			for (int i = 0; i < 10; i++)
			{
				Thread backgroundthread = new Thread(() => RunWorkload(connString));
				backgroundthread.Start();
			}
		}

		// Workload routine to connect and run query
		static public void RunWorkload(string connString)
		{
			// Setup a string to hold error messages
			StringBuilder errorMessages = new StringBuilder();

			// Connect to the server
			using (var connection = new SqlConnection(connString))
			{
				try
				{
					connection.Open();
					Console.WriteLine("Connected successfully.");

					// Create a stopwatch
					var watch = new System.Diagnostics.Stopwatch();
					watch.Start();

					// Let's run this in a loop 2 times
					for (int i = 0; i < 2; i++)
                    {
						Program.ExecuteQuery(connection);
                    }

					watch.Stop();
					Console.WriteLine("Workload for user has completed in {0}", watch.Elapsed);

				}
				catch (SqlException ex)
				{
					for (int i = 0; i < ex.Errors.Count; i++)
					{
						errorMessages.Append("Index #" + i + "\n" +
							"Message: " + ex.Errors[i].Message + "\n" +
							"LineNumber: " + ex.Errors[i].LineNumber + "\n" +
							"Source: " + ex.Errors[i].Source + "\n" +
							"Procedure: " + ex.Errors[i].Procedure + "\n");
					}
					Console.WriteLine(errorMessages.ToString());
				}
			}
		}

		static public void ExecuteQuery(SqlConnection connection)
		{
			using (var command = new SqlCommand())
			{
				command.Connection = connection;
				command.CommandType = CommandType.Text;
				command.CommandText = @"DECLARE @x int " +
										"DECLARE @y float " +
										"SET @x = 0; " +
										"WHILE (@x < 5000) " +
										"BEGIN " +
										"SELECT @y = sum(cast((soh.SubTotal*soh.TaxAmt*soh.TotalDue) as float)) " +
										"FROM SalesLT.Customer c " +
										"INNER JOIN SalesLT.SalesOrderHeader soh " +
										"ON c.CustomerID = soh.CustomerID " +
										"INNER JOIN SalesLT.SalesOrderDetail sod " +
										"ON soh.SalesOrderID = sod.SalesOrderID " +
										"INNER JOIN SalesLT.Product p " +
										"ON p.ProductID = sod.ProductID " +
										"GROUP BY c.CompanyName " +
										"ORDER BY c.CompanyName; " +
										"SET @x = @x + 1; " +
										"END ";
				command.CommandTimeout = 180;

				SqlDataReader reader = command.ExecuteReader();

				while(reader.Read());
				reader.Close();
			}
		}
	}
}


