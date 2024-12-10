using Azure.Monitor.OpenTelemetry.AspNetCore;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Azure.Functions.Worker.OpenTelemetry;

var builder = FunctionsApplication.CreateBuilder(args);

ConfigureTelemetry(builder);

await builder.Build().RunAsync();

static void ConfigureTelemetry(FunctionsApplicationBuilder builder)
{
    var telemetryBuilder = builder.Services.AddOpenTelemetry();

    if (GetKeyValue(builder.Configuration, "APPLICATIONINSIGHTS_CONNECTION_STRING") is string applicationInsightsConnectionString)
    {
        telemetryBuilder.UseAzureMonitor();
    }

    telemetryBuilder.UseFunctionsWorkerDefaults();
}

static string? GetKeyValue(IConfiguration configuration, string key)
{
    var section = configuration.GetSection(key);

    return section.Exists() ? section.Value : null;
}