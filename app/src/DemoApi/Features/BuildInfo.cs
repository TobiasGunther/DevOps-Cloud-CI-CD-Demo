using System.Reflection;

namespace DemoApi.Features;

/// <summary>
/// What the running instance can say about itself.
/// </summary>
/// <param name="Version">Baked into the artifact at build time. Identical in every environment.</param>
/// <param name="Commit">The git commit the artifact was built from.</param>
/// <param name="Environment">Read from configuration. Differs per environment.</param>
/// <param name="Message">Read from configuration, set by the infrastructure code.</param>
/// <param name="Host">The machine actually serving the request.</param>
/// <param name="UtcNow">Server time, so you can see the response is live.</param>
public record AppInfo(
    string Version,
    string Commit,
    string Environment,
    string Message,
    string Host,
    DateTimeOffset UtcNow);

public static class BuildInfo
{
    /// <summary>
    /// Version and commit come from the assembly: they travel with the artifact.
    /// Environment and message come from configuration: they are supplied by the platform.
    /// That split is the whole point of "build once, deploy many".
    /// </summary>
    public static AppInfo Describe(IConfiguration configuration, IHostEnvironment hostEnvironment)
    {
        var informational = Assembly.GetExecutingAssembly()
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion
            ?? "0.0.0-local";

        // The SDK appends "+<sha>" when SourceLink or an explicit InformationalVersion supplies one.
        var parts = informational.Split('+', 2);

        return new AppInfo(
            Version: parts[0],
            Commit: parts.Length > 1 ? parts[1] : "local-build",
            Environment: configuration["Demo:EnvironmentName"] ?? hostEnvironment.EnvironmentName,
            Message: configuration["Demo:Message"] ?? "No message configured.",
            Host: System.Environment.MachineName,
            UtcNow: DateTimeOffset.UtcNow);
    }
}
