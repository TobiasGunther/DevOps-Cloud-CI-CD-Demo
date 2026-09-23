using DemoApi.Features;

namespace DemoApi.Tests;

/// <summary>
/// Plain unit tests, no web server. These run in milliseconds, which is the point:
/// fast feedback is what makes people actually run them.
/// </summary>
public class GreetingServiceTests
{
    [Theory]
    [InlineData("Martin", "nb", "Hei, Martin!")]
    [InlineData("Martin", "en", "Hello, Martin!")]
    [InlineData("Martin", "de", "Hallo, Martin!")]
    public void Creates_greeting_in_the_requested_language(string name, string language, string expected)
    {
        var ok = GreetingService.TryCreate(name, language, out var greeting, out _);

        Assert.True(ok);
        Assert.Equal(expected, greeting.Message);
    }

    [Fact]
    public void Defaults_to_norwegian_when_no_language_is_given()
    {
        var ok = GreetingService.TryCreate("Tobias", language: null, out var greeting, out _);

        Assert.True(ok);
        Assert.Equal("nb", greeting.Language);
        Assert.Equal("Hei, Tobias!", greeting.Message);
    }

    [Fact]
    public void Trims_surrounding_whitespace_from_the_name()
    {
        var ok = GreetingService.TryCreate("  Tobias  ", "nb", out var greeting, out _);

        Assert.True(ok);
        Assert.Equal("Tobias", greeting.Name);
        Assert.Equal("Hei, Tobias!", greeting.Message);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void Rejects_an_empty_name(string? name)
    {
        var ok = GreetingService.TryCreate(name, "nb", out _, out var error);

        Assert.False(ok);
        Assert.Equal("Name must not be empty.", error);
    }

    [Fact]
    public void Rejects_a_name_longer_than_the_limit()
    {
        var tooLong = new string('a', GreetingService.MaxNameLength + 1);

        var ok = GreetingService.TryCreate(tooLong, "nb", out _, out var error);

        Assert.False(ok);
        Assert.Contains($"{GreetingService.MaxNameLength} characters", error);
    }

    [Fact]
    public void Accepts_a_name_exactly_at_the_limit()
    {
        var atLimit = new string('a', GreetingService.MaxNameLength);

        Assert.True(GreetingService.TryCreate(atLimit, "nb", out _, out _));
    }

    [Fact]
    public void Rejects_an_unsupported_language()
    {
        var ok = GreetingService.TryCreate("Martin", "fr", out _, out var error);

        Assert.False(ok);
        Assert.Contains("Unsupported language 'fr'", error);
    }

    [Fact]
    public void Language_matching_is_case_insensitive()
    {
        Assert.True(GreetingService.TryCreate("Martin", "EN", out var greeting, out _));
        Assert.Equal("en", greeting.Language);
    }
}

public class DevOpsPrinciplesTests
{
    [Fact]
    public void Serves_all_six_principles_from_the_lecture()
    {
        Assert.Equal(6, DevOpsPrinciples.All.Count);
    }

    [Fact]
    public void Numbers_the_principles_one_through_six_in_order()
    {
        Assert.Equal(Enumerable.Range(1, 6), DevOpsPrinciples.All.Select(p => p.Number));
    }

    [Fact]
    public void Gives_every_principle_a_title_and_a_description()
    {
        Assert.All(DevOpsPrinciples.All, principle =>
        {
            Assert.False(string.IsNullOrWhiteSpace(principle.Title));
            Assert.False(string.IsNullOrWhiteSpace(principle.Description));
        });
    }
}
