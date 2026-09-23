using DemoApi.Features;
using Microsoft.AspNetCore.Http.HttpResults;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new()
    {
        Title = "DevOps demo API",
        Version = "v1",
        Description = "Gjestforelesning USN - fra kode til produksjon. "
                    + "Denne appen ble bygget av en pipeline og rullet ut til Azure App Service uten at noen kopierte en fil.",
    });
});

var app = builder.Build();

// Swagger is normally Development-only. This is a teaching demo whose entire point is
// that you can open the deployed app and look at it, so it is on in every environment.
app.UseSwagger();
app.UseSwaggerUI(options =>
{
    options.SwaggerEndpoint("/swagger/v1/swagger.json", "DevOps demo API v1");
    options.DocumentTitle = "DevOps demo API";
});

// Land visitors straight on the docs instead of a 404.
app.MapGet("/", () => Results.Redirect("/swagger"))
   .ExcludeFromDescription();

app.MapGet("/api/info", (IConfiguration configuration, IHostEnvironment environment) =>
        TypedResults.Ok(BuildInfo.Describe(configuration, environment)))
   .WithName("GetInfo")
   .WithTags("Demo")
   .WithSummary("What is actually running right now")
   .WithDescription(
        "Version and commit are baked into the build artifact, so they are identical in every environment. "
      + "Environment and message come from App Service configuration. "
      + "Refresh this after a deploy to see the commit change.")
   .Produces<AppInfo>();

app.MapGet("/api/greet/{name}", Results<Ok<Greeting>, BadRequest<string>> (string name, string? language) =>
        GreetingService.TryCreate(name, language, out var greeting, out var error)
            ? TypedResults.Ok(greeting)
            : TypedResults.BadRequest(error))
   .WithName("GetGreeting")
   .WithTags("Demo")
   .WithSummary("Greet someone in Norwegian, English or German")
   .WithDescription(
        "Pass ?language=nb, en or de. Names are trimmed, must not be empty, and must be at most "
      + $"{GreetingService.MaxNameLength} characters. The validation rules here are what the unit tests cover.");

app.MapGet("/api/principles", () => TypedResults.Ok(DevOpsPrinciples.All))
   .WithName("GetPrinciples")
   .WithTags("Demo")
   .WithSummary("The six DevOps principles from the lecture")
   .WithDescription("Served by the app you just watched a pipeline deploy.")
   .Produces<IReadOnlyList<Principle>>();

// Used by the deploy workflows as a smoke test and by the keep-warm schedule.
app.MapGet("/health", () => TypedResults.Ok(new { status = "healthy" }))
   .ExcludeFromDescription();

app.Run();

/// <summary>Exposed so the integration tests can boot the real application.</summary>
public partial class Program;
