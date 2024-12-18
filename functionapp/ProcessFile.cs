using Azure.Core;
using Azure.Messaging.EventHubs;
using Azure.Storage.Files.Shares;
using Azure.Storage.Files.Shares.Models;
using Azure.Storage.Files.Shares.Specialized;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using System;
using System.Collections.Frozen;
using System.Collections.Generic;
using System.Diagnostics.CodeAnalysis;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;

namespace functionapp;

public class ProcessFile(ILogger<ProcessFile> logger, TokenCredential tokenCredential)
{
    [Function(nameof(ProcessFile))]
    public async Task Run([EventHubTrigger("%EVENT_HUB_NAME%", Connection = "EVENT_HUB_CONNECTION")] EventData[] events, CancellationToken cancellationToken)
    {
        var uris = events.SelectMany(GetUrisFromEvent).ToFrozenSet();

        foreach (var uri in uris)
        {
            await LogFileProperties(uri, tokenCredential, logger, cancellationToken);
        }
    }

    private static IEnumerable<Uri> GetUrisFromEvent(EventData data)
    {
        // Parse the event body as a JSON object
        if (data.EventBody.TryAsJsonObject(out var jsonObject)
            // Ensure the event has a "records" property with an array value
            && jsonObject.TryGetJsonArrayPropertyValue("records", out var records))
        {
            foreach (var record in records)
            {
                if (record is JsonObject recordObject
                    // Ensure the event has a "category" property with the value "StorageWrite"
                    && EventHasStorageWriteCategory(recordObject)
                    // Ensure the event has an "operationName" property with the value "CreateFile"
                    && EventHasCreateFileOperationName(recordObject)
                    // Ensure the event has a "statusCode" property with a success status code
                    && EventHasSuccessStatusCode(recordObject)
                    // Ensure the event has a "uri" property with an absolute URI
                    && recordObject.TryGetAbsoluteUriPropertyValue("uri", out var uri))
                {
                    // Remove any query string or fragment from the URI
                    yield return new UriBuilder(uri) { Query = null, Fragment = null }.Uri;
                }
            }
        }
    }

    private static bool EventHasStorageWriteCategory(JsonObject jsonObject) =>
        jsonObject.TryGetStringPropertyValue("category", out var category)
        && category.Equals("StorageWrite", StringComparison.OrdinalIgnoreCase);

    private static bool EventHasCreateFileOperationName(JsonObject jsonObject) =>
        jsonObject.TryGetStringPropertyValue("operationName", out var operationName)
        && operationName.Equals("CreateFile", StringComparison.OrdinalIgnoreCase);

    private static bool EventHasSuccessStatusCode(JsonObject jsonObject) =>
        jsonObject.TryGetInt32PropertyValue("statusCode", out var statusCode)
        && statusCode >= 200
        && statusCode < 300;

    private static async ValueTask LogFileProperties(Uri uri, TokenCredential tokenCredential, ILogger logger, CancellationToken cancellationToken)
    {
        var client = new ShareFileClient(uri,
                                         tokenCredential,
                                         new ShareClientOptions
                                         {
                                            ShareTokenIntent = ShareTokenIntent.Backup
                                         });

        var fileName = client.Name;
        var properties = await client.GetPropertiesAsync(cancellationToken);
        var fileSize = properties.Value.ContentLength;

        logger.LogInformation("File {FileName} has size {FileSize} bytes.", fileName, fileSize);
    }
}

file static class JsonObjectModule
{
    public static bool TryAsJsonObject(this BinaryData data, [NotNullWhen(true)] out JsonObject? jsonObject)
    {
        try
        {
            if (data.ToObjectFromJson<JsonObject>(JsonSerializerOptions.Web) is JsonObject obj)
            {
                jsonObject = obj;
                return true;
            }
            else
            {
                jsonObject = null;
                return false;
            }
        }
        catch (JsonException)
        {
            jsonObject = null;
            return false;
        }
    }

    public static bool TryGetJsonArrayPropertyValue(this JsonObject jsonObject, string propertyName, [NotNullWhen(true)] out JsonArray? value)
    {
        if (jsonObject.TryGetPropertyValue(propertyName, out var property)
            && property is JsonArray jsonArray)
        {
            value = jsonArray;
            return true;
        }
        else
        {
            value = null;
            return false;
        }
    }

    public static bool TryGetJsonValuePropertyValue(this JsonObject jsonObject, string propertyName, [NotNullWhen(true)] out JsonValue? value)
    {
        if (jsonObject.TryGetPropertyValue(propertyName, out var property)
            && property is JsonValue jsonValue)
        {
            value = jsonValue;
            return true;
        }
        else
        {
            value = null;
            return false;
        }
    }

    public static bool TryGetStringPropertyValue(this JsonObject jsonObject, string propertyName, [NotNullWhen(true)] out string? value)
    {
        if (jsonObject.TryGetJsonValuePropertyValue(propertyName, out var jsonValue)
            && jsonValue.TryGetValue(out value))
        {
            return true;
        }
        else
        {
            value = null;
            return false;
        }
    }

    public static bool TryGetInt32PropertyValue(this JsonObject jsonObject, string propertyName, [NotNullWhen(true)] out int? value)
    {
        if (jsonObject.TryGetJsonValuePropertyValue(propertyName, out var jsonValue)
            && (jsonValue.GetValueKind() == JsonValueKind.Number || jsonValue.GetValueKind() == JsonValueKind.String)
            && int.TryParse(jsonValue.ToString(), out var intValue))
        {
            value = intValue;
            return true;
        }
        else
        {
            value = default;
            return false;
        }
    }

    public static bool TryGetAbsoluteUriPropertyValue(this JsonObject jsonObject, string propertyName, [NotNullWhen(true)] out Uri? value)
    {
        if (jsonObject.TryGetStringPropertyValue(propertyName, out var uriString)
            && Uri.TryCreate(uriString, UriKind.Absolute, out value))
        {
            return true;
        }
        else
        {
            value = null;
            return false;
        }
    }
}