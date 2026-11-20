namespace MigrationStudio.Services;

public interface ISkillCatalog
{
    SkillInfo[] All { get; }
    string[] Directories { get; }
    string Read(string name);
}

public sealed class SkillCatalog(StudioPaths paths) : ISkillCatalog
{
    private const string Revision = "eeb1c6867c2d128763516a1aad41671c593cc189";
    public SkillInfo[] All { get; } =
    [
        new("provision-azure-sql-db", "Provision a protected free database",
            $"https://github.com/microsoft/microsoft-sql/blob/{Revision}/plugins/microsoft-sql-vscode/skills/provision-azure-sql-db/SKILL.md",
            Revision, "Explicit resource approval; confirmed Entra administrator; free-limit AutoPause guards."),
        new("sql-bacpac-to-azure-sql-db-migration", "Move actual schema and data",
            $"https://github.com/microsoft/microsoft-sql/blob/{Revision}/plugins/microsoft-sql-migration/skills/sql-bacpac-to-azure-sql-db-migration/SKILL.md",
            Revision, "Protected local SQL source authentication; precreated empty target; fixed execution tools only."),
        new("azuresql-db-local-to-cloud", "Verify local-to-cloud behavior",
            $"https://github.com/microsoft/microsoft-sql/blob/{Revision}/plugins/microsoft-azuresqldb-container/skills/azuresql-db-local-to-cloud/SKILL.md",
            Revision, "Preserve the existing app and restricted role; verify cloud behavior rather than assume parity.")
    ];

    public string[] Directories => All.Select(skill => Path.Combine(paths.Skills, skill.Name)).ToArray();

    public string Read(string name)
    {
        var skill = All.SingleOrDefault(item => item.Name == name)
            ?? throw new StudioException(400, "Unknown skill.");
        return File.ReadAllText(Path.Combine(paths.Skills, skill.Name, "SKILL.md"));
    }
}
