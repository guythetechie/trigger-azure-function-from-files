using System;
using Azure.Messaging.EventHubs;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace functionapp;

public class ProcessFile(ILogger<ProcessFile> logger)
{

    [Function(nameof(ProcessFile))]
    public void Run([EventHubTrigger("%EVENT_HUB_NAME%", Connection = "EVENT_HUB_CONNECTION")] EventData[] events)
    {
        foreach (EventData @event in events)
        {
            logger.LogInformation("Event Body: {body}", @event.EventBody.ToString());
            logger.LogInformation("Event Content-Type: {contentType}", @event.ContentType);
        }
    }
}
