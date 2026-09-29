namespace DemoApi.Features;

/// <summary>One need, and what each of the three large providers calls the service that meets it.</summary>
/// <param name="Need">What you are trying to do, in provider-neutral terms.</param>
/// <param name="Aws">The Amazon Web Services name.</param>
/// <param name="Azure">The Microsoft Azure name.</param>
/// <param name="GoogleCloud">The Google Cloud name.</param>
public record CloudService(string Need, string Aws, string Azure, string GoogleCloud);

/// <summary>
/// Same concepts, different names: the table from the lecture, served by an app that is
/// itself running on the second row of it.
/// </summary>
public static class CloudServices
{
    public static readonly IReadOnlyList<CloudService> All =
    [
        new("Virtuell maskin", "EC2", "Virtual Machines", "Compute Engine"),
        new("Kjøre en webapp uten å drifte server", "App Runner", "App Service", "Cloud Run"),
        new("Kode som kjøres på hendelser", "Lambda", "Functions", "Cloud Functions"),
        new("Lagring av filer og objekter", "S3", "Blob Storage", "Cloud Storage"),
        new("Database som tjeneste", "RDS", "Azure SQL", "Cloud SQL"),
        new("Containere i drift", "EKS", "AKS", "GKE"),
        new("Identitet og tilgang", "IAM", "Entra ID", "Cloud IAM"),
    ];
}
