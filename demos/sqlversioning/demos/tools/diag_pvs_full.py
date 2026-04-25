"""Dump EVERYTHING from the PVS record(s) for AccountId=42 — all metadata, all fields, all hex."""
import pyodbc, re, struct

conn = pyodbc.connect(
    'DRIVER={ODBC Driver 18 for SQL Server};SERVER=localhost;'
    'DATABASE=texasrangerswillwinitthisyear;Trusted_Connection=yes;'
    'TrustServerCertificate=yes'
)
cursor = conn.cursor()
cursor.execute("DBCC TRACEON(3604)")

# Step 1: Find data page for AccountId=42
cursor.execute("SELECT TOP 1 sys.fn_PhysLocFormatter(%%physloc%%) FROM dbo.Accounts WITH (NOLOCK) WHERE AccountId = 42")
physloc = cursor.fetchone()[0]
m = re.match(r'\((\d+):(\d+):(\d+)\)', physloc)
fid, pid, sid = int(m.group(1)), int(m.group(2)), int(m.group(3))
print(f"=== DATA PAGE: file={fid}, page={pid}, slot={sid} ===")

# Step 2: DBCC PAGE on data page to get version pointer
cursor.execute(f"DBCC PAGE('texasrangerswillwinitthisyear', {fid}, {pid}, 3) WITH TABLERESULTS")
rows = cursor.fetchall()
target = f"Slot {sid}"
fields = {}
hex_lines = []
for r in rows:
    parent = str(r[0]) if r[0] else ""
    field = str(r[2]) if r[2] else ""
    value = str(r[3]) if r[3] else ""
    if target in parent:
        if field:
            fields[field] = value
        elif re.match(r'[0-9a-fA-F]{10,}:', value):
            hex_lines.append(value)

print(f"\nData page fields for AccountId=42 (slot {sid}):")
for k in sorted(fields.keys()):
    print(f"  {k} = {fields[k]}")

# Get version pointer
vp_page = fields.get('Version Pointer Page', '0')
vp_file = fields.get('Version Pointer File', '0')
vp_slot = fields.get('Version Pointer Slot', '0')
vp_type = fields.get('Version Pointer Type', 'unknown')
print(f"\nVersion Pointer -> file={vp_file}, page={vp_page}, slot={vp_slot}, type={vp_type}")

if not vp_page or vp_page == '0':
    # Try parsing VP from hex dump
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
    print(f"  No named VP fields. Hex dump = {len(all_bytes)} bytes.")
    print(f"  StatusA = 0x{all_bytes[0]:02X}" if all_bytes else "  (empty)")
    if all_bytes and (all_bytes[0] & 0x40):
        print("  StatusA bit 0x40 SET -> has version info")
    else:
        print("  StatusA bit 0x40 NOT SET -> NO version info on this row")
        print("\n*** No version pointer found. Both Beat 1 updates may have committed")
        print("    and the PVS cleaner may have already cleaned up the versions.")
        print("    Re-run demo0 and then run only the Beat 1 updates to recreate.")
        conn.close()
        exit()

# Step 3: DBCC PAGE on PVS page — dump EVERYTHING for ALL slots
pvs_page = int(vp_page)
pvs_file = int(vp_file)
pvs_target_slot = int(vp_slot)

print(f"\n{'='*70}")
print(f"=== PVS PAGE: file={pvs_file}, page={pvs_page} ===")
print(f"=== Target slot from version pointer: {pvs_target_slot} ===")
print(f"{'='*70}")

cursor.execute(f"DBCC PAGE('texasrangerswillwinitthisyear', {pvs_file}, {pvs_page}, 3) WITH TABLERESULTS")
pvs_rows = cursor.fetchall()

# Also dump page header info
print(f"\nTotal DBCC PAGE rows returned: {len(pvs_rows)}")

# Group by slot, also capture page header
slots = {}
header_fields = {}
for r in pvs_rows:
    parent = str(r[0]) if r[0] else ""
    field = str(r[2]) if r[2] else ""
    value = str(r[3]) if r[3] else ""
    
    slot_match = re.search(r'Slot (\d+)', parent)
    if slot_match:
        sn = int(slot_match.group(1))
        if sn not in slots:
            slots[sn] = {'fields': {}, 'hex_lines': [], 'raw_rows': []}
        slots[sn]['raw_rows'].append((parent, field, value))
        if not field and re.match(r'[0-9a-fA-F]{10,}:', value):
            slots[sn]['hex_lines'].append(value)
        elif field:
            slots[sn]['fields'][field] = value
    elif 'PAGE HEADER' in parent.upper() or 'BUFFER' in parent.upper() or parent.startswith('PAGE:'):
        if field:
            header_fields[field] = value

# Print page header
if header_fields:
    print("\nPage Header (key fields):")
    for k in ('m_type', 'm_typeFlagBits', 'm_level', 'm_flagBits', 'm_objId', 
              'm_indexId', 'm_slotCnt', 'm_freeCnt', 'm_freeData', 'm_pageId',
              'm_prevPage', 'm_nextPage', 'pminlen'):
        if k in header_fields:
            print(f"  {k} = {header_fields[k]}")

print(f"\nSlots found on PVS page: {sorted(slots.keys())}")

# Dump each slot in full detail
for sn in sorted(slots.keys()):
    sd = slots[sn]
    marker = " <<<< VERSION POINTER TARGET" if sn == pvs_target_slot else ""
    print(f"\n{'='*60}")
    print(f"--- PVS Slot {sn}{marker} ---")
    print(f"{'='*60}")
    
    # All named fields
    print(f"\nNamed fields ({len(sd['fields'])}):")
    for k in sorted(sd['fields'].keys()):
        print(f"  {k} = {sd['fields'][k]}")
    
    # Parse hex dump
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
    
    print(f"\nRaw hex dump ({len(all_bytes)} bytes):")
    # Print in rows of 16
    for i in range(0, len(all_bytes), 16):
        chunk = all_bytes[i:i+16]
        hex_part = ' '.join(f'{b:02X}' for b in chunk)
        ascii_part = ''.join(chr(b) if 32 <= b < 127 else '.' for b in chunk)
        print(f"  {i:04d}: {hex_part:<48s}  {ascii_part}")
    
    if len(all_bytes) < 4:
        print("  (too short to parse)")
        continue
    
    # Parse PVS record structure
    status_a = all_bytes[0]
    status_b = all_bytes[1]
    pminlen = int.from_bytes(bytes(all_bytes[2:4]), 'little')
    print(f"\nRecord structure:")
    print(f"  StatusA      = 0x{status_a:02X} (has_var={bool(status_a & 0x20)}, has_version={bool(status_a & 0x40)})")
    print(f"  StatusB      = 0x{status_b:02X}")
    print(f"  pminlen      = {pminlen}")
    
    # Decode fixed columns (PVS internal table layout)
    if pminlen >= 12:
        xdes_ts_push = int.from_bytes(bytes(all_bytes[4:12]), 'little')
        print(f"  [4:12]  xdes_ts_push    = {xdes_ts_push}")
    if pminlen >= 20:
        xdes_ts_tran = int.from_bytes(bytes(all_bytes[12:20]), 'little')
        print(f"  [12:20] xdes_ts_tran    = {xdes_ts_tran}")
    if pminlen >= 22:
        min_len_val = int.from_bytes(bytes(all_bytes[20:22]), 'little')
        print(f"  [20:22] min_len         = {min_len_val}")
    if pminlen >= 30:
        seq_num = int.from_bytes(bytes(all_bytes[22:30]), 'little')
        print(f"  [22:30] seq_num         = {seq_num}")
    if pminlen >= 34:
        subid_push = int.from_bytes(bytes(all_bytes[30:34]), 'little')
        print(f"  [30:34] subid_push      = {subid_push}")
    if pminlen >= 38:
        subid_tran = int.from_bytes(bytes(all_bytes[34:38]), 'little')
        print(f"  [34:38] subid_tran      = {subid_tran}")
    if pminlen >= 46:
        rowset_id = int.from_bytes(bytes(all_bytes[38:46]), 'little')
        print(f"  [38:46] rowset_id       = {rowset_id}")
    if pminlen >= 54:
        prev_bytes = all_bytes[46:54]
        prev_page = int.from_bytes(bytes(prev_bytes[0:4]), 'little')
        prev_file = int.from_bytes(bytes(prev_bytes[4:6]), 'little')
        prev_slot = int.from_bytes(bytes(prev_bytes[6:8]), 'little')
        prev_hex = bytes(prev_bytes).hex()
        print(f"  [46:54] prev_row_chain  = 0x{prev_hex} -> page={prev_page}, file={prev_file}, slot={prev_slot}")
    if pminlen >= 62:
        sec_bytes = all_bytes[54:62]
        sec_page = int.from_bytes(bytes(sec_bytes[0:4]), 'little')
        sec_file = int.from_bytes(bytes(sec_bytes[4:6]), 'little')
        sec_slot = int.from_bytes(bytes(sec_bytes[6:8]), 'little')
        sec_hex = bytes(sec_bytes).hex()
        print(f"  [54:62] sec_version_rid = 0x{sec_hex} -> page={sec_page}, file={sec_file}, slot={sec_slot}")
    
    # Parse variable-length columns
    pos = pminlen
    if pos + 2 <= len(all_bytes):
        col_count = int.from_bytes(bytes(all_bytes[pos:pos+2]), 'little')
        null_bitmap_len = (col_count + 7) // 8
        null_bitmap = all_bytes[pos+2:pos+2+null_bitmap_len]
        print(f"\n  Column count = {col_count}")
        print(f"  Null bitmap  = {' '.join(f'{b:02X}' for b in null_bitmap)} ({null_bitmap_len} bytes)")
        pos += 2 + null_bitmap_len
        
        if status_a & 0x20 and pos + 2 <= len(all_bytes):
            var_col_count = int.from_bytes(bytes(all_bytes[pos:pos+2]), 'little')
            pos += 2
            var_offsets = []
            for vc in range(var_col_count):
                if pos + 2 <= len(all_bytes):
                    var_offsets.append(int.from_bytes(bytes(all_bytes[pos:pos+2]), 'little'))
                    pos += 2
            
            print(f"  Var col count = {var_col_count}")
            print(f"  Var offsets   = {var_offsets}")
            print(f"  Var data starts at byte {pos}")
            
            # Decode each variable column
            for vi in range(var_col_count):
                if vi == 0:
                    v_start = pos
                else:
                    v_start = var_offsets[vi - 1]
                v_end = var_offsets[vi]
                v_data = all_bytes[v_start:v_end]
                print(f"\n  Variable column #{vi}: bytes [{v_start}:{v_end}] = {len(v_data)} bytes")
                # Print hex
                for j in range(0, len(v_data), 16):
                    chunk = v_data[j:j+16]
                    hex_part = ' '.join(f'{b:02X}' for b in chunk)
                    ascii_part = ''.join(chr(b) if 32 <= b < 127 else '.' for b in chunk)
                    print(f"    {j:04d}: {hex_part:<48s}  {ascii_part}")
                
                # Try to decode as embedded user row (last var col = row_version)
                if vi == var_col_count - 1 and len(v_data) > 25:
                    print(f"\n  Attempting embedded row decode (last var col):")
                    if len(v_data) >= 4:
                        emb_status = v_data[0]
                        emb_pminlen = int.from_bytes(bytes(v_data[2:4]), 'little')
                        print(f"    Embedded StatusA = 0x{emb_status:02X}")
                        print(f"    Embedded pminlen = {emb_pminlen}")
                    
                    # Balance DECIMAL(18,2) @ offset 8, 9 bytes
                    dec_bytes = v_data[8:17]
                    if len(dec_bytes) == 9:
                        sign = dec_bytes[0]
                        int_val = int.from_bytes(bytes(dec_bytes[1:9]), 'little')
                        decimal_val = int_val / 100.0
                        if sign == 0:
                            decimal_val = -decimal_val
                        print(f"    >>> BALANCE = {decimal_val:,.2f} <<<")
                    
                    # LastUpdated DATETIME2(7) @ offset 17, 8 bytes
                    dt_bytes = v_data[17:25]
                    if len(dt_bytes) == 8:
                        time_val = int.from_bytes(bytes(dt_bytes[0:5]), 'little')
                        date_val = int.from_bytes(bytes(dt_bytes[5:8]), 'little')
                        try:
                            from datetime import datetime, timedelta
                            base = datetime(1, 1, 1)
                            dt = base + timedelta(days=date_val, microseconds=time_val / 10)
                            print(f"    >>> LASTUPDATED = {dt.strftime('%Y-%m-%d %H:%M:%S.%f')} <<<")
                        except (ValueError, OverflowError):
                            print(f"    LastUpdated raw: {' '.join(f'{b:02X}' for b in dt_bytes)}")

# If we found a chain pointer, follow it
if pvs_target_slot in slots:
    sd = slots[pvs_target_slot]
    # Re-parse to get chain pointer
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
    
    pminlen = int.from_bytes(bytes(all_bytes[2:4]), 'little') if len(all_bytes) >= 4 else 0
    
    # Check named field first
    chain_val = sd['fields'].get('prev_row_in_chain', '')
    if chain_val and chain_val not in ('(0:0:0)', '0x0000000000000000', ''):
        print(f"\n{'='*70}")
        print(f"CHAIN POINTER (named field): {chain_val}")
        rid_match = re.match(r'\((\d+):(\d+):(\d+)\)', chain_val)
        if rid_match:
            cf, cp, cs = int(rid_match.group(1)), int(rid_match.group(2)), int(rid_match.group(3))
            print(f"Following chain to file={cf}, page={cp}, slot={cs}")
            cursor.execute(f"DBCC PAGE('texasrangerswillwinitthisyear', {cf}, {cp}, 3) WITH TABLERESULTS")
            chain_rows = cursor.fetchall()
            print(f"Chain page returned {len(chain_rows)} rows")
    elif pminlen >= 54:
        prev_bytes = all_bytes[46:54]
        prev_page = int.from_bytes(bytes(prev_bytes[0:4]), 'little')
        prev_file = int.from_bytes(bytes(prev_bytes[4:6]), 'little')
        prev_slot_id = int.from_bytes(bytes(prev_bytes[6:8]), 'little')
        if prev_page != 0:
            print(f"\n{'='*70}")
            print(f"CHAIN POINTER (hex offset 46): page={prev_page}, file={prev_file}, slot={prev_slot_id}")
        else:
            print(f"\n*** prev_row_in_chain is NULL (all zeros at offset 46)")
            print(f"    Named field value: '{chain_val}'")
            # Also check offset 54
            if pminlen >= 62:
                sec_bytes = all_bytes[54:62]
                sec_page = int.from_bytes(bytes(sec_bytes[0:4]), 'little')
                if sec_page != 0:
                    print(f"    BUT sec_version_rid at offset 54 is non-zero: page={sec_page}")

conn.close()
print("\nDone.")
