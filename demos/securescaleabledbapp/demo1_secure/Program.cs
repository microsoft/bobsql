using System;
using System.Text;
using System.Data;
using Microsoft.Data.SqlClient;
using System.Configuration;
namespace SQLSecurity
{
	public class Program
	{
		static public void Main(string[] args)
		{
			// Setup a string to hold error messages
			StringBuilder errorMessages = new StringBuilder();

			// Read the connection string from the app.config file
			string connString;
			ConnectionStringSettings settings = ConfigurationManager.ConnectionStrings["ConsoleAppConnection"];
			connString = settings.ConnectionString;

			// Connect to the server
			using (var connection = new SqlConnection(connString))
			{
				try
				{
					connection.Open();
					Console.WriteLine("Connected successfully.");

					Program.ExecuteQuery(connection);

					Console.WriteLine("Press any key to finish...");
					Console.ReadKey(true);
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
				command.CommandText = @"SELECT @@SPID";

				SqlDataReader reader = command.ExecuteReader();

				Console.WriteLine("SessionID = ");
				while (reader.Read())
				{
					Console.WriteLine("{0}", reader.GetInt16(0));
				}

				reader.Close();
			}

			// Here is an example of how not to construct a query based on user input
			// This is very suspectible to SQL Injections
			/* using (var command = new SqlCommand())
			{
				Console.WriteLine("Input SalesOrderNumber: ");
				string SalesOrderNumber = Console.ReadLine();

				command.Connection = connection;
				command.CommandType = CommandType.Text;
				command.CommandText = @"SELECT PurchaseOrderNumber from SalesLT.SalesOrderHeader2 WHERE SalesOrderNumber = '" + SalesOrderNumber + "'";

				SqlDataReader reader = command.ExecuteReader();

				while (reader.Read())
				{
					Console.WriteLine("{0}", reader.GetString(0));
				}

				reader.Close();
			} */

			// Let's use parameters to avoid the injection
			//
			/* using (var command = new SqlCommand())
			{
				Console.WriteLine("Input SalesOrderNumber: ");
				string SalesOrderNumber = Console.ReadLine();

				command.Connection = connection;
				command.CommandType = CommandType.Text;
				command.CommandText = @"SELECT PurchaseOrderNumber from SalesLT.SalesOrderHeader2 WHERE SalesOrderNumber = @SalesOrderNumber";

				command.Parameters.Add("@SalesOrderNumber", System.Data.SqlDbType.NVarChar, 25);
				command.Parameters["@SalesOrderNumber"].Value = SalesOrderNumber;

				SqlDataReader reader = command.ExecuteReader();

				while (reader.Read())
				{
					Console.WriteLine("{0}", reader.GetString(0));
				}

				reader.Close();
			} */
		}
	}
}


