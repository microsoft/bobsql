using System.Security.AccessControl;
using System.Security.Principal;

namespace MigrationStudio;

public sealed class StudioPaths
{
    public string Root { get; }
    public string StateRoot { get; }
    public string Skills => Path.Combine(Root, "skills");
    public string Scripts => Path.Combine(Root, "scripts");
    public string AgentWorkspace => Path.Combine(StateRoot, "agent");
    public static readonly System.Text.Json.JsonSerializerOptions Json = new(System.Text.Json.JsonSerializerDefaults.Web);

    public StudioPaths(IWebHostEnvironment environment, IConfiguration configuration)
    {
        Root = Directory.GetParent(environment.ContentRootPath)?.FullName
            ?? throw new InvalidOperationException("Migration Studio root is unavailable.");
        StateRoot = configuration["Studio:StateRoot"]
            ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SqlMigrationStudio");
        ProtectDirectory(StateRoot);
        ProtectDirectory(AgentWorkspace);
    }

    public string RunDirectory(string id)
    {
        if (!Guid.TryParseExact(id, "N", out _))
            throw new StudioException(400, "Invalid run identifier.");
        var path = Path.Combine(StateRoot, "runs", id);
        ProtectDirectory(path);
        return path;
    }

    public static void ProtectDirectory(string path)
    {
        Directory.CreateDirectory(path);
        if (OperatingSystem.IsWindows())
        {
            var user = WindowsIdentity.GetCurrent().User
                ?? throw new InvalidOperationException("Cannot resolve the current Windows identity.");
            var security = new DirectorySecurity();
            security.SetAccessRuleProtection(true, false);
            security.SetOwner(user);
            const InheritanceFlags inheritance = InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit;
            security.AddAccessRule(new FileSystemAccessRule(user, FileSystemRights.FullControl,
                inheritance, PropagationFlags.None, AccessControlType.Allow));
            security.AddAccessRule(new FileSystemAccessRule(
                new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null), FileSystemRights.FullControl,
                inheritance, PropagationFlags.None, AccessControlType.Allow));
            new DirectoryInfo(path).SetAccessControl(security);
        }
    }
}
