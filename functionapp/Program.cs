using Azure.Core;
using Azure.Identity;
using Azure.Monitor.OpenTelemetry.AspNetCore;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Azure.Functions.Worker.OpenTelemetry;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;

var builder = FunctionsApplication.CreateBuilder(args);

ConfigureBuilder(builder);

await builder.Build().RunAsync();

static void ConfigureBuilder(FunctionsApplicationBuilder builder)
{
    ConfigureTelemetry(builder);
    ConfigureTokenCredential(builder);
}

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

static void ConfigureTokenCredential(IHostApplicationBuilder builder)
{
    builder.Services.TryAddSingleton<TokenCredential>(new DefaultAzureCredential());
}