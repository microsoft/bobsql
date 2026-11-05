"""Quick diagnostic: dump DBCC PAGE output for AccountId 42 in Accounts."""
from mssql_python import connect as mssql_connect
import re

conn = mssql_connect('Server=localhost;Database=texasrangerswillwinitthisyear;Trusted_Connection=yes;Encrypt=no')
cur = conn.cursor()

# Find the page for AccountId 42
cur.execute("""SELECT allocated_page_file_id, allocated_page_page_id
FROM sys.dm_db_database_page_allocations(DB_ID(), OBJECT_ID('dbo.Accounts'), NULL, NULL, 'DETAILED')
WHERE page_type_desc = 'DATA_PAGE' ORDER BY allocated_page_page_id""")
pages = [(r[0], r[1]) for r in cur.fetchall()]

cur.execute('DBCC TRACEON(3604)')
for fid, pid in pages:
    cur.execute(f"DBCC PAGE(N'texasrangerswillwinitthisyear', {fid}, {pid}, 3) WITH TABLERESULTS")
    rows = cur.fetchall()
    found = False
    target_slot = None
    for r in rows:
        parent = str(r[0]) if r[0] else ''
        field = str(r[2]) if r[2] else ''
        value = str(r[3]) if r[3] else ''
        if field == 'AccountId' and value == '42':
            slot_match = re.search(r'Slot (\d+)', parent)
            target_slot = f'Slot {slot_match.group(1)}' if slot_match else None
            print(f'=== AccountId 42: file={fid} page={pid} slot={slot_match.group(1) if slot_match else "??"} ===')
            found = True
            break
    if found and target_slot:
        for r in rows:
            p = str(r[0]) if r[0] else ''
            f = str(r[2]) if r[2] else ''
            v = str(r[3]) if r[3] else ''
            if target_slot in p:
                if f:
                    print(f'  {f} = {v}')
                elif re.match(r'[0-9a-fA-F]{10,}:', v):
                    print(f'  HEX: {v}')
                else:
                    print(f'  [{p}] {v}')
        break

# Also check PVS stats
cur.execute("""SELECT persistent_version_store_size_kb
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID(N'texasrangerswillwinitthisyear')""")
row = cur.fetchone()
print(f'\nPVS Size: {row[0]} KB' if row else '\nNo PVS stats')

conn.close()
