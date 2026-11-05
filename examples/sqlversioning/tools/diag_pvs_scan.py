"""Scan ALL slots on the PVS page to find where V0 (938.30) lives."""
import pyodbc, re, struct

conn = pyodbc.connect(
    'DRIVER={ODBC Driver 18 for SQL Server};SERVER=localhost;'
    'DATABASE=texasrangerswillwinitthisyear;Trusted_Connection=yes;'
    'TrustServerCertificate=yes'
)
cursor = conn.cursor()

# Step 1: Find the data page for AccountId=1
cursor.execute("DBCC TRACEON(3604)")
cursor.execute("""
    SELECT TOP 1 
        sys.fn_PhysLocFormatter(%%physloc%%) AS PhysLoc
    FROM dbo.Accounts WITH (NOLOCK)
    WHERE AccountId = 1
""")
physloc = cursor.fetchone()[0]
m = re.match(r'\((\d+):(\d+):(\d+)\)', physloc)
file_id, page_id, slot_id = int(m.group(1)), int(m.group(2)), int(m.group(3))
print(f"Data page: file={file_id}, page={page_id}, slot={slot_id}")

# Step 2: DBCC PAGE the data page, find version pointer
cursor.execute(f"DBCC PAGE('texasrangerswillwinitthisyear', {file_id}, {page_id}, 3) WITH TABLERESULTS")
rows = cursor.fetchall()

target_slot = f"Slot {slot_id}"
hex_lines = []
fields = {}
for r in rows:
    parent = str(r[0]) if r[0] else ""
    field = str(r[2]) if r[2] else ""
    value = str(r[3]) if r[3] else ""
    if target_slot in parent:
        if not field and re.match(r'[0-9a-fA-F]{10,}:', value):
            hex_lines.append(value)
        elif field:
            fields[field] = value

print(f"\nData page fields for slot {slot_id}:")
for k, v in fields.items():
    if 'version' in k.lower() or 'pvs' in k.lower() or 'pointer' in k.lower() or k in ('Balance', 'LastUpdated'):
        print(f"  {k} = {v}")

# Find version pointer info
vp_page = fields.get('Version Pointer Page', fields.get('VersionPointerPage', ''))
vp_file = fields.get('Version Pointer File', fields.get('VersionPointerFile', ''))
vp_slot = fields.get('Version Pointer Slot', fields.get('VersionPointerSlot', ''))
print(f"\nVersion pointer -> file={vp_file}, page={vp_page}, slot={vp_slot}")

if not vp_page or vp_page == '0':
    # Try parsing from hex
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
    print(f"  (hex dump has {len(all_bytes)} bytes, no named VP fields found)")
    print("  Cannot proceed without version pointer")
    conn.close()
    exit()

pvs_page = int(vp_page)
pvs_file = int(vp_file)

# Step 3: DBCC PAGE on the PVS page - scan ALL slots
print(f"\n{'='*60}")
print(f"Scanning PVS page: file={pvs_file}, page={pvs_page}")
print(f"{'='*60}")

cursor.execute(f"DBCC PAGE('texasrangerswillwinitthisyear', {pvs_file}, {pvs_page}, 3) WITH TABLERESULTS")
pvs_rows = cursor.fetchall()

# Group by slot
slots = {}
for r in pvs_rows:
    parent = str(r[0]) if r[0] else ""
    field = str(r[2]) if r[2] else ""
    value = str(r[3]) if r[3] else ""
    slot_match = re.search(r'Slot (\d+)', parent)
    if slot_match:
        sn = int(slot_match.group(1))
        if sn not in slots:
            slots[sn] = {'fields': {}, 'hex_lines': []}
        if not field and re.match(r'[0-9a-fA-F]{10,}:', value):
            slots[sn]['hex_lines'].append(value)
        elif field:
            slots[sn]['fields'][field] = value

print(f"Found {len(slots)} slots on PVS page")

for sn in sorted(slots.keys()):
    sd = slots[sn]
    print(f"\n--- Slot {sn} ---")
    
    # Show key named fields
    for k, v in sd['fields'].items():
        if any(x in k.lower() for x in ['prev', 'chain', 'xdes', 'min_len', 'seq', 'version']):
            print(f"  {k} = {v}")
    
    # Parse hex to decode embedded row
    all_bytes = []
    for line in sd['hex_lines']:
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
    
    if len(all_bytes) < 4:
        print(f"  (only {len(all_bytes)} bytes)")
        continue
    
    pminlen = int.from_bytes(bytes(all_bytes[2:4]), 'little')
    print(f"  pminlen={pminlen}, record_bytes={len(all_bytes)}")
    
    # Dump offsets 4-62 to see fixed columns
    if pminlen >= 54:
        xdes_ts_push = int.from_bytes(bytes(all_bytes[4:12]), 'little')
        prev_chain_46 = bytes(all_bytes[46:54]).hex() if len(all_bytes) >= 54 else "N/A"
        prev_chain_54 = bytes(all_bytes[54:62]).hex() if len(all_bytes) >= 62 else "N/A"
        print(f"  xdes_ts_push={xdes_ts_push}")
        print(f"  bytes[46:54]={prev_chain_46}  (offset 46)")
        print(f"  bytes[54:62]={prev_chain_54}  (offset 54)")
    
    # Try to decode embedded row (variable-length column)
    status_byte = all_bytes[0]
    pos = pminlen
    if pos + 2 <= len(all_bytes):
        col_count = int.from_bytes(bytes(all_bytes[pos:pos+2]), 'little')
        null_bitmap_len = (col_count + 7) // 8
        pos += 2 + null_bitmap_len
        
        if status_byte & 0x20 and pos + 2 <= len(all_bytes):
            var_col_count = int.from_bytes(bytes(all_bytes[pos:pos+2]), 'little')
            pos += 2
            var_offsets = []
            for vc in range(var_col_count):
                if pos + 2 <= len(all_bytes):
                    var_offsets.append(int.from_bytes(bytes(all_bytes[pos:pos+2]), 'little'))
                    pos += 2
            
            if var_offsets:
                var_data_start = pos
                if len(var_offsets) >= 2:
                    row_start = var_offsets[-2]
                else:
                    row_start = var_data_start
                row_end = var_offsets[-1]
                embedded = all_bytes[row_start:row_end]
                
                print(f"  Embedded row: {len(embedded)} bytes (offsets {row_start}..{row_end})")
                
                if len(embedded) > 17:
                    # Balance DECIMAL(18,2) at offset 8
                    dec_bytes = embedded[8:17]
                    if len(dec_bytes) == 9:
                        sign = dec_bytes[0]
                        int_val = int.from_bytes(bytes(dec_bytes[1:9]), 'little')
                        decimal_val = int_val / 100.0
                        if sign == 0:
                            decimal_val = -decimal_val
                        print(f"  >>> BALANCE = {decimal_val:,.2f} <<<")

conn.close()
print("\nDone.")
