/* ============================================================================
   Ward General — Architecture (Exploring the Architecture)
   06-replicas.sql : HA and named replicas as architectural objects.  (Architecture §6, §7)

   Architectural illustration only — no benchmarks (Performance) and no tuning. HA
   operational use and failover mechanics are High Availability and Resiliency; named replicas as a scale-out
   pattern are Performance.

   WHERE TO RUN QUERY 1 — anywhere, but WHAT YOU SEE DEPENDS ON WHERE YOU STAND.
   The DMF is scoped to the database you pass it, and it only ever looks DOWN the
   tree, never up:
     - From the PRIMARY: the primary, its HA replicas, and the named replicas
       along with their own HA replicas. This is the run that shows the whole
       picture, and it is the one the area uses.
     - From a NAMED REPLICA: only that named replica and its own HA replicas.
       THE PRIMARY DOES NOT APPEAR (observed live, 2026-08-10). A named replica is
       a separate database with its own database_id, so DB_ID() resolves to the
       named replica and the DMF returns that database's subtree. Nothing is
       broken — you are simply standing lower in the tree.
     - From a GEO-SECONDARY: Learn documents the same shape from the other side.
       HA replicas added under a geo-secondary "are not returned ... when queried
       on the primary. You should query ... when connected to a geo-secondary."
   `is_local` = 1 marks the row you are connected to, so you can always tell where
   you are standing. The corollary is worth stating plainly: NO SINGLE RUN IS
   GUARANTEED TO BE THE WHOLE TOPOLOGY once named replicas or geo-replication are
   in play (High Availability and Resiliency, Performance). Run it from the primary for the full inventory.

   PERMISSIONS — admin, or VIEW DATABASE STATE. A pooled database needs
   VIEW SERVER STATE. See README.md.

   Sources (accessed 2026-08-05; `sys.dm_hs_database_replicas` columns, run
   location and permissions re-verified 2026-08-10):
     [Microsoft Learn — sys.dm_hs_database_replicas]
       https://learn.microsoft.com/sql/relational-databases/system-functions/sys-dm-hs-database-replicas
     [Microsoft Learn — Hyperscale secondary replicas]
       https://learn.microsoft.com/azure/azure-sql/database/service-tier-hyperscale-replicas
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
GO

PRINT N'== 1. The replica inventory (primary + HA + named, all on shared storage) ==';
/* Every replica is compute attached to the SAME page servers as the primary
   (§4) — creating one copies no data, which is why it comes online in seconds
   and bills for compute only. HA replicas are hot standbys; named replicas carry
   a different database name and use the same log service. Hyperscale-only DMF.

   THE POINT OF THIS QUERY IS THE PARENTAGE. HA replicas are not all children of
   the primary. A named replica can have its own HA replicas, and those attach to
   the NAMED REPLICA, not to the primary (§7). Learn makes this explicit in the
   column definition for
   parent_replica_id: "the Primary, geo-forwarder, or named replica that has an
   HA replica."

   The DMF is joined to itself on `parent_replica_id` = `replica_id` so the parent
   is resolved to a NAME. The GUIDs do the work but are not projected — matching
   uniqueidentifiers by eye across rows teaches nothing, and the names are the
   answer. The ORDER BY then groups every replica UNDER ITS OWN PARENT rather than
   lumping all HA replicas together by role — otherwise the primary's HA replicas
   and a named replica's HA replicas interleave and the hierarchy disappears,
   which is the one thing this query exists to show.

   Reading the output: `parent_replica_database_name` is NULL for the primary, for
   named replicas, and for a geo-replication forwarder — those are the tops of
   their own trees. Any row where it is populated is an HA replica, and the value
   tells you whose. Run this from a named replica and the tree you get back is
   rooted at THAT named replica, not at the primary — see WHERE TO RUN above.

   EXPECT A FLAT RESULT HERE. A named replica is created with NO HA replicas of
   its own, so on the topology this area builds you will see the primary, its
   HA replica, and the named replica — and the nested `+--` row under the named
   replica will NOT appear. That is correct. The nesting has to be created
   deliberately by adding an HA replica TO the named replica, and the script that
   does it belongs to High Availability and Resiliency, which owns HA operations. The self-join stays here
   because the parentage is the architectural point either way: the column exists,
   and it tells you an HA replica attaches to a specific parent rather than to
   "the database". */
SELECT
    CASE
        WHEN r.parent_replica_id IS NULL THEN r.replica_role_desc
        ELSE N'   +-- ' + r.replica_role_desc          -- an HA replica of the row above
    END                                            AS replica_tree,
    r.replica_server_name,
    r.replica_database_name,
    r.is_local,                   -- 1 = the replica you are connected to
    p.replica_database_name AS parent_replica_database_name,
    p.replica_role_desc     AS parent_replica_role_desc    -- 'Primary' or 'Named replica'
FROM sys.dm_hs_database_replicas(DB_ID()) AS r
LEFT JOIN sys.dm_hs_database_replicas(DB_ID()) AS p
       ON p.replica_id = r.parent_replica_id
ORDER BY
    COALESCE(p.replica_role, r.replica_role),               -- which tree: primary's first, then each named replica's
    COALESCE(p.replica_database_name, r.replica_database_name),
    CASE WHEN r.parent_replica_id IS NULL THEN 0 ELSE 1 END,  -- parent row first, then its HA replicas
    r.replica_database_name;
GO

PRINT N'== 2. This connection''s role and updateability ==';
/* Primary is READ_WRITE; every HA and named replica is READ_ONLY. Run this from
   a named replica connection to see replica_role = 3 and a different DB name. */
SELECT
    rg.replica_role,              -- 0 = primary, 1 = HA secondary, 2 = geo forwarder, 3 = named replica
    CASE rg.replica_role
        WHEN 0 THEN N'primary (read-write)'
        WHEN 1 THEN N'HA secondary (read-only)'
        WHEN 2 THEN N'geo forwarder'
        WHEN 3 THEN N'named replica (read-only)'
    END                                                              AS ReplicaRoleDesc,
    CAST(DATABASEPROPERTYEX(DB_NAME(), 'Updateability') AS NVARCHAR(20)) AS Updateability
FROM sys.dm_user_db_resource_governance AS rg
WHERE rg.database_id = DB_ID();
GO
