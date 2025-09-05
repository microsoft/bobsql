using System;
using System.Text;
using System.Threading.Tasks;
using Azure;
using Azure.AI.OpenAI;
using System.Collections.Generic;
using Azure.Identity;
using Azure.Messaging.EventHubs;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;

namespace Contoso.SQLEvents
{
    public class SQLEventHubTrigger
    {
        private readonly ILogger<SQLEventHubTrigger> _logger;

        public SQLEventHubTrigger(ILogger<SQLEventHubTrigger> logger)
        {
            _logger = logger;
        }

        [Function(nameof(SQLEventHubTrigger))]
        public async Task Run([EventHubTrigger("<AEH>", Connection = "<AEHspace>_<policy>_EVENTHUB")] EventData[] events)
        {
            foreach (EventData @event in events)
            {
                string eventBody = Encoding.UTF8.GetString(@event.Body.ToArray());
                _logger.LogInformation("Event Body: {body}", eventBody);

                // Parse the JSON data
                var jsonData = JObject.Parse(eventBody);
                var dataToken = jsonData["data"];
                if (dataToken == null)
                {
                    _logger.LogWarning("The 'data' section is missing in the event JSON.");
                    continue;
                }
                var dataSection = JObject.Parse(dataToken.ToString());

                // Display operation
                string operation = jsonData["operation"]?.ToString() ?? string.Empty;
                _logger.LogInformation("Operation: {operation}", operation);

                // Display eventsource details
                var eventSource = dataSection["eventsource"];
                if (eventSource != null)
                {
                    _logger.LogInformation("Database: {db}", eventSource["db"]?.ToString());
                    _logger.LogInformation("Schema: {schema}", eventSource["schema"]?.ToString());
                    _logger.LogInformation("Table: {tbl}", eventSource["tbl"]?.ToString());
                }
                else
                {
                    _logger.LogWarning("The 'eventsource' section is missing in the data.");
                }

                // Display columns
                var columns = eventSource?["cols"];
                if (columns != null)
                {
                    foreach (var column in columns)
                    {
                        _logger.LogInformation("Column Name: {name}, Type: {type}, Index: {index}", column["name"]?.ToString(), column["type"]?.ToString(), column["index"]?.ToString());
                    }
                }
                else
                {
                    _logger.LogWarning("The 'cols' section is missing in the event data.");
                }

                // Display primary key
                var pkKey = eventSource?["pkkey"];
                if (pkKey != null)
                {
                    foreach (var key in pkKey)
                    {
                        _logger.LogInformation("Primary Key Column: {columnname}, Value: {value}", key["columnname"]?.ToString(), key["value"]?.ToString());
                    }
                }
                else
                {
                    _logger.LogWarning("The 'pkkey' section is missing in the event data.");
                }

                // Display transaction details
                var transaction = eventSource?["transaction"];
                if (transaction != null)
                {
                    _logger.LogInformation("Commit LSN: {commitlsn}", transaction["commitlsn"]?.ToString());
                    _logger.LogInformation("Begin LSN: {beginlsn}", transaction["beginlsn"]?.ToString());
                    _logger.LogInformation("Sequence Number: {sequencenumber}", transaction["sequencenumber"]?.ToString());
                    _logger.LogInformation("Commit Time: {committime}", transaction["committime"]?.ToString());
                }
                else
                {
                    _logger.LogWarning("The 'transaction' section is missing in the event data.");
                }

                // Display event row details
                var eventRow = dataSection["eventrow"];
                if (eventRow != null)
                {
                    if (operation == "INS" && eventRow["current"] != null)
                    {
                        var currentRow = JObject.Parse(eventRow["current"]?.ToString() ?? "{}");

                        _logger.LogInformation("OrderID: {OrderID}", currentRow["OrderID"]?.ToString());
                        _logger.LogInformation("CustomerFirstName: {CustomerFirstName}", currentRow["CustomerFirstName"]?.ToString());
                        _logger.LogInformation("CustomerLastName: {CustomerLastName}", currentRow["CustomerLastName"]?.ToString());
                        _logger.LogInformation("Company: {Company}", currentRow["Company"]?.ToString());
                        _logger.LogInformation("SalesDate: {SalesDate}", currentRow["SalesDate"]?.ToString());
                        _logger.LogInformation("EstimatedShipDate: {EstimatedShipDate}", currentRow["EstimatedShipDate"]?.ToString());
                        _logger.LogInformation("ShippingID: {ShippingID}", currentRow["ShippingID"]?.ToString());
                        _logger.LogInformation("ShippingLocation: {ShippingLocation}", currentRow["ShippingLocation"]?.ToString());
                        _logger.LogInformation("Product: {Product}", currentRow["Product"]?.ToString());
                        _logger.LogInformation("Quantity: {Quantity}", currentRow["Quantity"]?.ToString());
                        _logger.LogInformation("Price: {Price}", currentRow["Price"]?.ToString());

                        // Check if EstimatedShipDate is more than 30 days from SalesDate
                        if (DateTime.TryParse(currentRow["SalesDate"]?.ToString(), out DateTime salesDate) &&
                            DateTime.TryParse(currentRow["EstimatedShipDate"]?.ToString(), out DateTime estimatedShipDate))
                        {
                            if ((estimatedShipDate - salesDate).TotalDays > 30)
                            {
                                _logger.LogInformation("Checking shipment due to excessive shipping delay. SalesDate: {SalesDate}, EstimatedShipDate: {EstimatedShipDate}", salesDate, estimatedShipDate);
                                await CheckShipment(currentRow);
                            }
                        }
                        else
                        {
                            _logger.LogWarning("Invalid date format in SalesDate or EstimatedShipDate.");
                        }
                    }
                    else if (operation == "UPD" && eventRow["current"] != null)
                    {
                        var currentRow = JObject.Parse(eventRow["current"]?.ToString() ?? "{}");
                        _logger.LogInformation("Dumping all fields for the current row (UPD Operation): {currentRow}", currentRow.ToString());
                    }
                    else if (operation != "INS")
                    {
                        _logger.LogWarning("Skipping 'current' row processing as operation is not 'INS' or 'UPD'.");
                    }

                    if (eventRow["old"] != null)
                    {
                        _logger.LogInformation("Old Row: {old}", eventRow["old"]?.ToString());
                    }
                }
                else
                {
                    _logger.LogWarning("The 'eventrow' section is missing in the data.");
                }
            }
        }

        private async Task CheckShipment(JObject currentRow)
        {
            _logger.LogInformation("CheckShipment called with currentRow: {currentRow}", currentRow.ToString());

            // Break out fields from currentRow
            string orderId = currentRow["OrderID"]?.ToString();
            string customerFirstName = currentRow["CustomerFirstName"]?.ToString();
            string customerLastName = currentRow["CustomerLastName"]?.ToString();
            string company = currentRow["Company"]?.ToString();
            string salesDate = currentRow["SalesDate"]?.ToString();
            string estimatedShipDate = currentRow["EstimatedShipDate"]?.ToString();
            string shippingId = currentRow["ShippingID"]?.ToString();
            string shippingLocation = currentRow["ShippingLocation"]?.ToString();
            string product = currentRow["Product"]?.ToString();
            string quantity = currentRow["Quantity"]?.ToString();
            string price = currentRow["Price"]?.ToString();

            // Construct the prompt for the Azure AI Agent
            string prompt = $@"
                Please analyze the following shipment details and provide recommendations:
                OrderID: {orderId}
                CustomerFirstName: {customerFirstName}
                CustomerLastName: {customerLastName}
                Company: {company}
                SalesDate: {salesDate}
                EstimatedShipDate: {estimatedShipDate}
                ShippingID: {shippingId}
                ShippingLocation: {shippingLocation}
                Product: {product}
                Quantity: {quantity}
                Price: {price}";

            // Call Azure AI Agent to handle the shipment
            try
            {
                var aiAgentResponse = await CallAzureAIAgentAsync(prompt);
                _logger.LogInformation("Azure AI Agent Response: {response}", aiAgentResponse);
            }
            catch (Exception ex)
            {
                _logger.LogError("Error while calling Azure AI Agent: {message}", ex.Message);
            }
        }

        private async Task<string> CallAzureAIAgentAsync(string prompt)
        {
            try
            {
                // Azure OpenAI Service configuration
                string endpoint = "<azure ai endpoint>";
                string apiKey = Environment.GetEnvironmentVariable("AZURE_OPENAI_API_KEY");
                var client = new OpenAIClient(new Uri(endpoint), new AzureKeyCredential(apiKey));

                var chatCompletionOptions = new ChatCompletionsOptions()
                {
                    Messages =
                    {
                        new ChatMessage(ChatRole.System, "You are an AI agent to help analyze shipment for orders for Contoso. If you are asked to analyze a shipment, you will look at the SalesDate, the EstimatedShipDate, ShipLocation, and ShippingID. You will respond back to these requests to say you have looked at the current shipment information, found the tracking details, and have made adjustments with another shipping provider to expedite the shipping to a more reasonable date. Based on the customer information provided you have also notified the customer of the new estimated shipping date"),
                        new ChatMessage(ChatRole.User, prompt)
                    },
                    MaxTokens = 500
                };
                var response = await client.GetChatCompletionsAsync("gpt-4.5-preview", chatCompletionOptions);

                // Return the AI Agent's response
                return response.Value.Choices[0].Message.Content;
            }
            catch (Exception ex)
            {
                _logger.LogError("Error while calling Azure AI Agent: {message}", ex.Message);
                throw;
            }
        }
    }
}
