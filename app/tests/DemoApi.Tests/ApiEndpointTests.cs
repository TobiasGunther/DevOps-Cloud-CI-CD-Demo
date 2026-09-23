using System.Net;
using System.Net.Http.Json;
using DemoApi.Features;
using Microsoft.AspNetCore.Mvc.Testing;

namespace DemoApi.Tests;

/// <summary>
/// Integration tests. These boot the real application in memory and make real HTTP
/// requests against it, so they catch routing and serialisation mistakes that the
/// unit tests above cannot see. No Azure, no network, still fast.
/// </summary>
public class ApiEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public ApiEndpointTests(WebApplicationFactory<Program> factory) => _client = factory.CreateClient();

    [Fact]
    public async Task Health_reports_healthy()
    {
        var response = await _client.GetAsync("/health");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task Root_lands_on_the_swagger_ui()
    {
        // The test client follows the redirect from "/", so a 200 means the UI is reachable.
        var response = await _client.GetAsync("/");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("swagger", response.RequestMessage!.RequestUri!.ToString(), StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Info_reports_a_version_and_an_environment()
    {
        var info = await _client.GetFromJsonAsync<AppInfo>("/api/info");

        Assert.NotNull(info);
        Assert.False(string.IsNullOrWhiteSpace(info!.Version));
        Assert.False(string.IsNullOrWhiteSpace(info.Environment));
    }

    [Fact]
    public async Task Greet_returns_a_greeting()
    {
        var greeting = await _client.GetFromJsonAsync<Greeting>("/api/greet/Martin?language=en");

        Assert.NotNull(greeting);
        Assert.Equal("Hello, Martin!", greeting!.Message);
    }

    [Fact]
    public async Task Greet_rejects_an_unsupported_language_with_400()
    {
        var response = await _client.GetAsync("/api/greet/Martin?language=fr");

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Principles_returns_the_six_principles()
    {
        var principles = await _client.GetFromJsonAsync<List<Principle>>("/api/principles");

        Assert.NotNull(principles);
        Assert.Equal(6, principles!.Count);
    }

    [Fact]
    public async Task Swagger_document_is_served()
    {
        var response = await _client.GetAsync("/swagger/v1/swagger.json");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("/api/greet/{name}", await response.Content.ReadAsStringAsync());
    }
}
