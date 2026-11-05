from mssql_python import connect as mssql_connect
import re

conn = mssql_connect("Server=localhost;Database=texasrangerswillwinitthisyear;Trusted_Connection=yes;Encrypt=no;TrustServerCertificate=yes")
cursor = conn.cursor()
cursor.execute("DBCC TRACEON(3604)")
cursor.execute("DBCC PAGE(N'texasrangerswillwinitthisyear', 1, 352, 3) WITH TABLERESULTS")
rows = cursor.fetchall()

# Collect hex lines for Slot 41
hex_lines = []
record_length = 0
for r in rows:
    parent = str(r[0]) if r[0] else ""
    field = str(r[2]) if r[2] else ""
    value = str(r[3]) if r[3] else ""
    if "Slot 41" in parent:
        len_match = re.search(r'Length (\d+)', parent)
        if len_match:
            record_length = int(len_match.group(1))
        if not field and re.match(r'[0-9a-fA-F]{10,}:', value):
            hex_lines.append(value)

# Parse all bytes
all_bytes = []
for line in hex_lines:
    after_colon = line.split(':', 1)
    if len(after_colon) < 2:
        continue
    parts = re.split(r'  +', after_colon[1].strip(), maxsplit=1)
    hex_str = parts[0].replace(' ', '')
    for i in range(0, len(hex_str), 2):
        try:
            all_bytes.append(int(hex_str[i:i+2], 16))
        except ValueError:
            break
all_bytes = all_bytes[:record_length]

print(f"Record length: {record_length}")
print(f"Status byte: 0x{all_bytes[0]:02X} (bit 6 = {bool(all_bytes[0] & 0x40)})")
print(f"\nLast 14 bytes (version pointer):")
vp = all_bytes[-14:]
print(f"  Raw: {' '.join(f'{b:02X}' for b in vp)}")

# Decode: last 6 bytes = XSN (LE), first 8 = version store pointer
xsn = int.from_bytes(bytes(vp[8:14]), 'little')
print(f"  XSN (bytes 8-13, LE): {xsn}")

# Try different pointer layouts for first 8 bytes
p1 = int.from_bytes(bytes(vp[0:4]), 'little')
p2 = int.from_bytes(bytes(vp[4:8]), 'little')
print(f"  Pointer bytes 0-3 (LE int32): {p1}")
print(f"  Pointer bytes 4-7 (LE int32): {p2}")

# Now check version store
print(f"\n--- Version Store ---")
cursor.execute("""
    SELECT transaction_sequence_num, version_sequence_num, 
           record_length_first_part_in_bytes, status
    FROM sys.dm_tran_version_store
    WHERE database_id = DB_ID(N'texasrangerswillwinitthisyear')
    ORDER BY transaction_sequence_num DESC
""")
for r in cursor.fetchall():
    print(f"  XSN={r[0]}  SeqInChain={r[1]}  RecordBytes={r[2]}  Status={r[3]}")

conn.close()
