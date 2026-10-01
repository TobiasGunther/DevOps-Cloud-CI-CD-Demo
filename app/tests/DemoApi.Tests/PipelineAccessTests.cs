using System.Net;
using System.Net.Http.Json;
using DemoApi.Features;
using Microsoft.AspNetCore.Mvc.Testing;

namespace DemoApi.Tests;

public class PipelineAccessTests
{
    [Fact]
    public void Lists_three_ways_a_pipeline_can_be_allowed_to_deploy()
    {
        Assert.Equal(3, PipelineAccess.All.Count);
    }

    [Fact]
    public void Orders_them_from_simplest_to_strongest()
    {
        Assert.Equal(Enumerable.Range(1, 3), PipelineAccess.All.Select(method => method.Number));
    }

    [Fact]
    public void Only_the_simplest_keeps_a_secret_at_the_ci_provider()
    {
        var withSecret = Assert.Single(PipelineAccess.All, method => method.StoresASecret);

        Assert.Equal(1, withSecret.Number);
    }

    [Fact]
    public void Answers_all_three_questions_for_every_method()
    {
        Assert.All(PipelineAccess.All, method =>
        {
            Assert.False(string.IsNullOrWhiteSpace(method.HowLongIsItValid));
            Assert.False(string.IsNullOrWhiteSpace(method.HowMuchDoesItGrant));
            Assert.False(string.IsNullOrWhiteSpace(method.CanYouSeeWhoUsedIt));
        });
    }
}

public class PipelineAccessEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public PipelineAccessEndpointTests(WebApplicationFactory<Program> factory) => _client = factory.CreateClient();

    [Fact]
    public async Task Deployment_access_returns_all_three_methods()
    {
        var response = await _client.GetAsync("/api/deployment/access");
        var methods = await response.Content.ReadFromJsonAsync<List<AccessMethod>>();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(3, methods!.Count);
    }
}
