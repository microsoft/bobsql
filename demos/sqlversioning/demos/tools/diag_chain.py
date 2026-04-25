"""Chase the PVS chain for AccountId 42 to find all versions."""
from mssql_python import connect as mssql_connect
import re, struct

conn = mssql_connect('Server=localhost;Database=texasrangerswillwinitthisyear;Trusted_Connection=yes;Encrypt=no')
cur = conn.cursor()

# Current row values
cur.execute("SELECT AccountId, Balance, LastUpdated FROM dbo.Accounts WHERE AccountId = 42")
row = cur.fetchone()
print(f"Current row: AccountId={row[0]}, Balance={row[1]}, LastUpdated={row[2]}")

# VP says: PVS page 14952, file 1, slot 0
pvs_page = 14952
pvs_file = 1
pvs_slot = 0

def chase_pvs(cur, db, fid, pid, slot, depth=0):
    prefix = "  " * depth
    print(f"\n{prefix}=== Chasing PVS: file={fid}, page={pid}, slot={slot} (depth {depth}) ===")
    cur.execute("DBCC TRACEON(3604)")
    cur.execute(f"DBCC PAGE(N'{db}', {fid}, {pid}, 3) WITH TABLERESULTS")
    rows = cur.fetchall()
    
    target = f"Slot {slot}"
    fields = {}
    hex_lines = []
    record_length = 0
    all_slots = set()
    
    for r in rows:
        parent = str(r[0]) if r[0] else ""
        field = str(r[2]) if r[2] else ""
        value = str(r[3]) if r[3] else ""
        sm = re.search(r'Slot (\d+)', parent)
        if sm:
            all_slots.add(int(sm.group(1)))
        if target in parent:
            lm = re.search(r'Length (\d+)', parent)
            if lm:
                record_length = int(lm.group(1))
            if not field and re.match(r'[0-9a-fA-F]{10,}:', value):
                hex_lines.append(value)
            elif field:
                fields[field] = value
    
    print(f"{prefix}Slots found on page: {sorted(all_slots)}")
    print(f"{prefix}Record length: {record_length}")
    print(f"{prefix}Named fields: {fields}")
    
    # Parse hex dump
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
    
    if record_length and len(all_bytes) > record_length:
        all_bytes = all_bytes[:record_length]
    
    print(f"{prefix}Hex bytes parsed: {len(all_bytes)}")
    if all_bytes:
        print(f"{prefix}First 40 bytes: {' '.join(f'{b:02X}' for b in all_bytes[:40])}")
    
    # Try to decode embedded row from PVS record
    if len(all_bytes) > 4:
        pvs_status = all_bytes[0]
        pvs_pminlen = int.from_bytes(bytes(all_bytes[2:4]), 'little')
        print(f"{prefix}PVS StatusA: 0x{pvs_status:02X}, pminlen: {pvs_pminlen}")
        
        pos = pvs_pminlen
        if pos + 2 <= len(all_bytes):
            col_count = int.from_bytes(bytes(all_bytes[pos:pos+2]), 'little')
            null_bitmap_len = (col_count + 7) // 8
            pos += 2 + null_bitmap_len
            print(f"{prefix}PVS col_count: {col_count}, null_bitmap: {null_bitmap_len} bytes")
            
            if pvs_status & 0x20 and pos + 2 <= len(all_bytes):
                var_col_count = int.from_bytes(bytes(all_bytes[pos:pos+2]), 'little')
                pos += 2
                var_offsets = []
                for vc in range(var_col_count):
                    if pos + 2 <= len(all_bytes):
                        var_offsets.append(int.from_bytes(bytes(all_bytes[pos:pos+2]), 'little'))
                        pos += 2
                print(f"{prefix}var_col_count: {var_col_count}, offsets: {var_offsets}")
                
                if var_offsets:
                    # Last var col = embedded row (row_version)
                    if len(var_offsets) >= 2:
                        row_start = var_offsets[-2]
                    else:
                        # Only one var col — starts right after offset array
                        row_start = pos  # which is where we are after reading offsets
                    row_end = var_offsets[-1]
                    embedded = all_bytes[row_start:row_end]
                    print(f"{prefix}Embedded row: bytes [{row_start}:{row_end}] = {len(embedded)} bytes")
                    if embedded:
                        print(f"{prefix}Embedded first 30: {' '.join(f'{b:02X}' for b in embedded[:30])}")
                    
                    # Decode Balance @ offset 8 (DECIMAL 9 bytes)
                    if len(embedded) >= 17:
                        dec_bytes = embedded[8:17]
                        sign = dec_bytes[0]
                        int_val = int.from_bytes(bytes(dec_bytes[1:9]), 'little')
                        decimal_val = int_val / 100.0
                        if sign == 0:
                            decimal_val = -decimal_val
                        print(f"{prefix}>>> DECODED Balance: {decimal_val:,.2f}")
                    
                    # Decode LastUpdated @ offset 17 (DATETIME2 8 bytes)
                    if len(embedded) >= 25:
                        dt_bytes = embedded[17:25]
                        time_val = int.from_bytes(bytes(dt_bytes[0:5]), 'little')
                        date_val = int.from_bytes(bytes(dt_bytes[5:8]), 'little')
                        from datetime import datetime, timedelta
                        try:
                            base = datetime(1, 1, 1)
                            dt = base + timedelta(days=date_val, microseconds=time_val / 10)
                            print(f"{prefix}>>> DECODED LastUpdated: {dt}")
                        except:
                            print(f"{prefix}>>> LastUpdated raw: {' '.join(f'{b:02X}' for b in dt_bytes)}")
    
    # Follow prev_row_in_chain
    chain_ptr = fields.get('prev_row_in_chain', '')
    print(f"{prefix}prev_row_in_chain: '{chain_ptr}'")
    if chain_ptr and chain_ptr not in ('0x0000000000000000', '(null)', ''):
        try:
            chain_hex = chain_ptr[2:] if chain_ptr.startswith('0x') else chain_ptr
            chain_raw = bytes.fromhex(chain_hex)
            if len(chain_raw) >= 8:
                c_page = int.from_bytes(chain_raw[0:4], 'little')
                c_file = int.from_bytes(chain_raw[4:6], 'little')
                c_slot = int.from_bytes(chain_raw[6:8], 'little')
                if c_page > 0 and depth < 5:
                    chase_pvs(cur, db, c_file, c_page, c_slot, depth + 1)
        except Exception as e:
            print(f"{prefix}Chain parse error: {e}")

chase_pvs(cur, 'texasrangerswillwinitthisyear', pvs_file, pvs_page, pvs_slot)

conn.close()
