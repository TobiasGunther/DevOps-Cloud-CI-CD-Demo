namespace DemoApi.Features;

/// <summary>One of the DevOps principles from the lecture.</summary>
/// <param name="Number">Position in the list, 1-6.</param>
/// <param name="Title">Short name of the principle.</param>
/// <param name="Description">One sentence explaining it.</param>
public record Principle(int Number, string Title, string Description);

/// <summary>
/// The six principles from the lecture, served by the app the students watched deploy.
/// </summary>
public static class DevOpsPrinciples
{
    public static readonly IReadOnlyList<Principle> All =
    [
        new(1, "Felles ansvar",
            "Teamet eier koden hele veien, også når den kjører for brukerne klokken to om natten."),
        new(2, "Automatiser det repeterende",
            "Alt som gjøres likt hver gang bør gjøres av en maskin: bygg, test og utrulling."),
        new(3, "Rask tilbakemelding",
            "Du skal vite innen minutter om endringen din virker, ikke innen uker."),
        new(4, "Små og hyppige endringer",
            "Liten endring gir liten risiko og er lett å rulle tilbake når noe går galt."),
        new(5, "Kortere vei til produksjon, trygt",
            "Målet er å korte ned tiden fra kode til bruk uten å øke risikoen."),
        new(6, "Robust når noe brekker",
            "Breaking changes skal være påtenkt og planlagt, håndtert av prosessen selv."),
    ];
}
