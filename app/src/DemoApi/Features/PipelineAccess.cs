namespace DemoApi.Features;

/// <summary>One way a pipeline can be allowed to deploy, judged by the three questions from the lecture.</summary>
/// <param name="Number">Position on the ladder, 1-3, from simplest to strongest.</param>
/// <param name="Name">Short name of the approach.</param>
/// <param name="HowItWorks">One sentence on the mechanism.</param>
/// <param name="StoresASecret">Whether a long-lived credential is kept at the CI provider.</param>
/// <param name="HowLongIsItValid">The first question: how long is the access valid?</param>
/// <param name="HowMuchDoesItGrant">The second question: how much does it give access to?</param>
/// <param name="CanYouSeeWhoUsedIt">The third question: can the log tell you who used it?</param>
public record AccessMethod(
    int Number,
    string Name,
    string HowItWorks,
    bool StoresASecret,
    string HowLongIsItValid,
    string HowMuchDoesItGrant,
    string CanYouSeeWhoUsedIt);

/// <summary>
/// The three ways from the lecture, simplest first. Worth knowing when you read this on
/// the deployed app: the first row is exactly how the publish-profile workflow deploys.
/// </summary>
public static class PipelineAccess
{
    public static readonly IReadOnlyList<AccessMethod> All =
    [
        new(1, "Lagret hemmelighet",
            "En nøkkel eller et passord limes inn i CI-systemet og brukes ved hver kjøring.",
            StoresASecret: true,
            HowLongIsItValid: "Til noen husker å bytte den",
            HowMuchDoesItGrant: "Alt på den aktuelle tjenesten",
            CanYouSeeWhoUsedIt: "Nei, deploy ser lik ut uansett hvem"),
        new(2, "Kortlevd føderert identitet",
            "CI-systemet beviser hvem det er, og skyen utsteder et token som varer i minutter.",
            StoresASecret: false,
            HowLongIsItValid: "Minutter, per kjøring",
            HowMuchDoesItGrant: "Kun valgt rolle på valgt ressursgruppe",
            CanYouSeeWhoUsedIt: "Ja, egen identitet i loggen"),
        new(3, "Identitet i kjøremiljøet",
            "Tjenesten som kaller kjører allerede i skyen og får identiteten sin derfra.",
            StoresASecret: false,
            HowLongIsItValid: "Ingen nøkkel å bytte, plattformen fornyer tokenet selv",
            HowMuchDoesItGrant: "Rollen som er tildelt tjenesten",
            CanYouSeeWhoUsedIt: "Ja, tjenestens egen identitet i loggen"),
    ];
}
