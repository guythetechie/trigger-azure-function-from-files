using Azure.Monitor.OpenTelemetry.AspNetCore;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Azure.Functions.Worker.OpenTelemetry;

var builder = FunctionsApplication.CreateBuilder(args);

builder.Services
       .AddOpenTelemetry()
       .UseAzureMonitor()
       .UseFunctionsWorkerDefaults();

await builder.Build().RunAsync();
