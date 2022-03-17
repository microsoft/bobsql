using System;
using System.Text;
using System.Data;
using Microsoft.Data.SqlClient;
using System.Configuration;
namespace SQLAvailability
{
	public class Program
	{
		static public void Main(string[] args)
		{
			// Read the connection string from the app.config file
			string connString;
			ConnectionStringSettings settings = ConfigurationManager.ConnectionStrings["ConsoleAppConnectionbc"];
			connString = settings.ConnectionString;

			for (int i = 0; i < 25; i++)
			{
				RunWorkload(connString);
			}
		}

		// Workload routine to connect and run query
		static public void RunWorkload(string connString)
		{
			// Setup a string to hold error messages
			StringBuilder errorMessages = new StringBuilder();

			// Define the retry logic parameters
			var options = new SqlRetryLogicOption()
			{
				// Tries 3 times before throwing an exception
				NumberOfTries = 5,
				// Preferred gap time to delay before retry
				DeltaTime = TimeSpan.FromSeconds(5),
				// Maximum gap time for each delay time before retry
				MaxTimeInterval = TimeSpan.FromSeconds(10)
			};
			
			// Create a retry logic provider
			SqlRetryLogicBaseProvider provider = SqlConfigurableRetryFactory.CreateExponentialRetryProvider(options);

			// define the retrying event to report the execution attempts
			provider.Retrying += (object s, SqlRetryingEventArgs e) =>
			{
				int attempts = e.RetryCount;
				Console.ForegroundColor = ConsoleColor.Yellow;
				Console.WriteLine($"attempt {attempts} - current delay time:{e.Delay} \n");
				Console.ForegroundColor = ConsoleColor.DarkGray;
				if (e.Exceptions[e.Exceptions.Count - 1] is SqlException ex)
				{
					Console.WriteLine($"{ex.Number}-{ex.Message}\n");
				}
				else
				{
					Console.WriteLine($"{e.Exceptions[e.Exceptions.Count - 1].Message}\n");
				}
			};

			try
			{
				// Build the connection
				using var connection = new SqlConnection(connString);
				
				// Set the retry logic provider on the connection instance
				connection.RetryLogicProvider = provider;

				// open the connection
				connection.Open();
				Console.WriteLine("Connected successfully.");

				// Create a stopwatch
				var watch = new System.Diagnostics.Stopwatch();
				watch.Start();

				Program.ExecuteQuery(connection);

				watch.Stop();
				Console.WriteLine("Workload for user has completed in {0}", watch.Elapsed);
			}
			catch(Exception ex)
            {
				errorMessages.Append(
						"Message: " + ex.Message + "\n" +
						"Source: " + ex.Source + "\n");
				Console.WriteLine(errorMessages.ToString());
			}
		}

		static public void ExecuteQuery(SqlConnection connection)
		{
			using (var command = new SqlCommand())
			{
				command.Connection = connection;
				command.CommandType = CommandType.Text;
				command.CommandText = @"SELECT @@VERSION";
				command.CommandTimeout = 180;

				SqlDataReader reader = command.ExecuteReader();

				while (reader.Read()) ;
				reader.Close();
			}
		}
	}
}


