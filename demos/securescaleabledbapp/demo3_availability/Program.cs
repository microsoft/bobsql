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
			ConnectionStringSettings settings = ConfigurationManager.ConnectionStrings["ConsoleAppConnectiongp1"];
			connString = settings.ConnectionString;

			// Setup retry logic
			// Define the retry logic parameters
			var options = new SqlRetryLogicOption()
			{
				// Tries 5 times before throwing an exception
				NumberOfTries = 5,
				// Preferred gap time to delay before retry
				DeltaTime = TimeSpan.FromSeconds(5),
				// Maximum gap time for each delay time before retry
				MaxTimeInterval = TimeSpan.FromSeconds(60),
				// Let's add a few errors to the default
				TransientErrors = new int[] { 0, 64, 40615, 40914, 40613}
			};

			// Create a retry logic provider
			SqlRetryLogicBaseProvider provider = SqlConfigurableRetryFactory.CreateExponentialRetryProvider(options);

			// define the retrying event to report the execution attempts
			provider.Retrying += (s, e) =>
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

			for (int i = 0; i < 10000000; i++)
			{
				RunWorkload(connString, provider);
				//if ((i % 100) == 0)
                {
					Console.ForegroundColor = ConsoleColor.White;
					Console.WriteLine("Workload executed... {0}", i);
				}

				// Delay a bit to make this a typical app instead of just making DB calls as fast as I can
				System.Threading.Thread.Sleep(100);
			}
		}

		// Workload routine to connect and run query
		static public void RunWorkload(string connString, SqlRetryLogicBaseProvider provider)
		{
			// Setup a string to hold error messages
			StringBuilder errorMessages = new StringBuilder();

			try
			{
				// Build the connection
				using (var connection = new SqlConnection(connString))
				{
					// Set the retry logic provider on the connection instance
					//connection.RetryLogicProvider = provider;

					// open the connection
					connection.Open();

					var watch = new System.Diagnostics.Stopwatch();
					watch.Start();

					Program.ExecuteQuery(connection, provider);

					watch.Stop();

					// Close the connection
					connection.Close();
				}
			}
 			catch(Exception ex)
            {
				Console.ForegroundColor = ConsoleColor.Red;
				errorMessages.Append(
						"Message: " + ex.Message + "\n" +
						"Source: " + ex.Source + "\n");
				Console.WriteLine(errorMessages.ToString());
			}
		}

		static public void ExecuteQuery(SqlConnection connection, SqlRetryLogicBaseProvider provider)
		{
			using (var command = new SqlCommand())
			{
				command.Connection = connection;
				command.CommandType = CommandType.Text;
				command.CommandText = @"SELECT @@VERSION";
				command.CommandTimeout = 180;
				command.RetryLogicProvider = provider;

				SqlDataReader reader = command.ExecuteReader();

				while (reader.Read()) ;
				reader.Close();
			}
		}
	}
}


