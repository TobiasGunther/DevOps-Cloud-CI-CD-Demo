using System.Net;
using System.Net.Http.Json;
using DemoApi.Features;
using Microsoft.AspNetCore.Mvc.Testing;

namespace DemoApi.Tests;

public class CloudServicesTests
{
    [Fact]
    public void Lists_the_seven_needs_from_the_lecture()
    {
        Assert.Equal(7, CloudServices.All.Count);
    }

    [Fact]
    public void Names_the_service_at_every_provider_for_every_need()
    {
        Assert.All(CloudServices.All, service =>
        {
            Assert.False(string.IsNullOrWhiteSpace(service.Need));
            Assert.False(string.IsNullOrWhiteSpace(service.Aws));
            Assert.False(string.IsNullOrWhiteSpace(service.Azure));
            Assert.False(string.IsNullOrWhiteSpace(service.GoogleCloud));
        });
    }

    [Fact]
    public void Maps_app_service_to_its_equivalents_at_the_other_providers()
    {
        var webApps = Assert.Single(CloudServices.All, service => service.Azure == "App Service");

        Assert.Equal("App Runner", webApps.Aws);
        Assert.Equal("Cloud Run", webApps.GoogleCloud);
    }
}

public class CloudServicesEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public CloudServicesEndpointTests(WebApplicationFactory<Program> factory) => _client = factory.CreateClient();

    [Fact]
    public async Task Cloud_services_returns_the_whole_table()
    {
        var response = await _client.GetAsync("/api/cloud/services");
        var services = await response.Content.ReadFromJsonAsync<List<CloudService>>();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(7, services!.Count);
    }
}
