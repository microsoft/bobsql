"""Quick check: what's at offset 54 of the PVS record?"""
import sys, re
sys.path.insert(0, '.')
from dbcc_page_viewer_adr import get_connection, find_page_for_row, run_dbcc_page, parse_version_from_hex

DATABASE = 'texasrangerswillwinitthisyear'
conn = get_connection('localhost', DATABASE, 'windows')
cursor = conn.cursor()

file_id, page_id, slot_num = find_page_for_row(cursor, DATABASE, '42', 'Accounts')
rows = run_dbcc_page(cursor, DATABASE, file_id, page_id)
hex_lines = []
record_length = 0
for r in rows:
    parent = str(r[0]) if r[0] else ""
    field = str(r[2]) if r[2] else ""
    value = str(r[3]) if r[3] else ""
    if re.search(rf'\bSlot {slot_num}\b', parent):
        len_match = re.search(r'Length (\d+)', parent)
        if len_match:
            record_length = int(len_match.group(1))
        if not field and re.match(r'[0-9a-fA-F]{10,}:', value):
            hex_lines.append(value)

vi = parse_version_from_hex(hex_lines, record_length)
ptr_page = vi.get('pointer_page')
dbcc_fid = vi.get('dbcc_file_id')
ptr_slot = vi.get('pointer_slot')

# Read PVS page
pvs_rows = run_dbcc_page(cursor, DATABASE, int(dbcc_fid), int(ptr_page))
pvs_hex = []
pvs_reclen = 0
for r in pvs_rows:
    parent = str(r[0]) if r[0] else ""
    field = str(r[2]) if r[2] else ""
    value = str(r[3]) if r[3] else ""
    if re.search(rf'\bSlot {ptr_slot}\b', parent):
        len_match = re.search(r'Length (\d+)', parent)
        if len_match:
            pvs_reclen = int(len_match.group(1))
        if not field and re.match(r'[0-9a-fA-F]{10,}:', value):
            pvs_hex.append(value)

# Parse all bytes
all_bytes = []
for line in pvs_hex:
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

print(f"PVS record: {pvs_reclen} bytes total, parsed {len(all_bytes)} hex bytes")
print(f"pminlen = {int.from_bytes(bytes(all_bytes[2:4]), 'little')}")

# Dump key offsets
for offset, name, size in [
    (4, 'xdes_ts_push', 8),
    (12, 'xdes_ts_tran', 8),
    (20, 'subid_push', 4),
    (24, 'subid_tran', 4),
    (28, 'rowset_id', 8),
    (36, 'sec_version_rid', 8),
    (44, 'min_len', 2),
    (46, 'seq_num', 8),
    (54, 'prev_row_in_chain', 8),
    (62, 'UNKNOWN', 8),
]:
    raw = all_bytes[offset:offset+size]
    val = int.from_bytes(bytes(raw), 'little')
    hex_str = ' '.join(f'{b:02X}' for b in raw)
    print(f"  offset {offset:2d} ({size}B) {name:25s} = {val:20d}  hex: {hex_str}")

# If prev_row_in_chain at 54 has a non-zero page:
chain_bytes = all_bytes[54:62]
chain_page = int.from_bytes(bytes(chain_bytes[0:4]), 'little')
chain_file = int.from_bytes(bytes(chain_bytes[4:6]), 'little')
chain_slot = int.from_bytes(bytes(chain_bytes[6:8]), 'little')
pvs_bit = bool(chain_page & 0x80000000)
real_page = chain_page & 0x7FFFFFFF
print(f"\nprev_row_in_chain parsed: page={real_page} (pvs={pvs_bit}), file={chain_file}, slot={chain_slot}")

if real_page != 0:
    print(f"\n=== CHASING to V0: file={chain_file or 1}, page={real_page}, slot={chain_slot} ===")
    from dbcc_page_viewer_adr import read_pvs_record
    v0, err = read_pvs_record(cursor, DATABASE, chain_file or 1, real_page, chain_slot)
    if err:
        print(f"  ERROR: {err}")
    if v0:
        for k, vv in v0.items():
            print(f"  {k} = {vv}")
else:
    print("\nprev_row_in_chain at offset 54 is also NULL")
    # Try a few more offsets
    for try_off in [56, 58, 60, 62, 64, 66, 68, 70]:
        if try_off + 8 <= len(all_bytes):
            tb = all_bytes[try_off:try_off+8]
            tp = int.from_bytes(bytes(tb[0:4]), 'little')
            tf = int.from_bytes(bytes(tb[4:6]), 'little')
            ts = int.from_bytes(bytes(tb[6:8]), 'little')
            rp = tp & 0x7FFFFFFF
            print(f"  offset {try_off}: page={rp} (pvs={bool(tp & 0x80000000)}), file={tf}, slot={ts}  raw: {' '.join(f'{b:02X}' for b in tb)}")

conn.close()
