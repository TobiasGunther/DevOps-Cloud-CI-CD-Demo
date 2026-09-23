namespace DemoApi.Features;

/// <summary>A greeting returned by the API.</summary>
/// <param name="Message">The greeting itself, in the requested language.</param>
/// <param name="Language">The language the greeting was rendered in.</param>
/// <param name="Name">The name the greeting was addressed to.</param>
public record Greeting(string Message, string Language, string Name);

/// <summary>
/// Builds greetings. Deliberately the most "logic-like" part of the app, so it is
/// the natural place to add a failing test during the pipeline demo.
/// </summary>
public static class GreetingService
{
    public const int MaxNameLength = 40;

    private static readonly Dictionary<string, string> Templates = new(StringComparer.OrdinalIgnoreCase)
    {
        ["nb"] = "Hei, {0}!",
        ["en"] = "Hello, {0}!",
        ["de"] = "Hallo, {0}!",
    };

    public static IReadOnlyCollection<string> SupportedLanguages => Templates.Keys;

    /// <summary>
    /// Returns a greeting, or an error message explaining why the input was rejected.
    /// </summary>
    public static bool TryCreate(string? name, string? language, out Greeting greeting, out string error)
    {
        greeting = default!;
        error = string.Empty;

        if (string.IsNullOrWhiteSpace(name))
        {
            error = "Name must not be empty.";
            return false;
        }

        if (name.Length > MaxNameLength)
        {
            error = $"Name must be {MaxNameLength} characters or fewer.";
            return false;
        }

        var requested = string.IsNullOrWhiteSpace(language) ? "nb" : language.Trim();

        if (!Templates.TryGetValue(requested, out var template))
        {
            error = $"Unsupported language '{requested}'. Supported: {string.Join(", ", Templates.Keys)}.";
            return false;
        }

        var trimmed = name.Trim();
        greeting = new Greeting(string.Format(template, trimmed), requested.ToLowerInvariant(), trimmed);
        return true;
    }
}
