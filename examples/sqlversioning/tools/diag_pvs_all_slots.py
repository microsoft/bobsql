"""Diagnostic: Dump ALL slots on the PVS page for AccountId 42's version chain."""
import sys, re
sys.path.insert(0, '.')
from dbcc_page_viewer_adr import get_connection, find_page_for_row, run_dbcc_page, parse_version_from_hex

DATABASE = 'texasrangerswillwinitthisyear'
conn = get_connection('localhost', DATABASE, 'windows')
cursor = conn.cursor()

# Find AccountId 42
file_id, page_id, slot_num = find_page_for_row(cursor, DATABASE, '42', 'Accounts')
print(f"Data page: file={file_id}, page={page_id}, slot={slot_num}")

# Parse version tag from data page
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
ptr_file = vi.get('pointer_file')
ptr_slot = vi.get('pointer_slot')
dbcc_fid = vi.get('dbcc_file_id', ptr_file)
print(f"Version pointer -> PVS file={dbcc_fid}, page={ptr_page}, slot={ptr_slot}")
print(f"  is_inrow={vi.get('is_inrow')}, pvs_bit={vi.get('pointer_pvs')}")

# Now dump ALL slots on the PVS page
print(f"\n=== ALL SLOTS on PVS page {ptr_page} ===")
pvs_rows = run_dbcc_page(cursor, DATABASE, int(dbcc_fid), int(ptr_page))

# Collect all slots
slots = {}
for r in pvs_rows:
    parent = str(r[0]) if r[0] else ""
    field = str(r[2]) if r[2] else ""
    value = str(r[3]) if r[3] else ""
    slot_match = re.search(r'Slot (\d+)', parent)
    if slot_match:
        sn = int(slot_match.group(1))
        if sn not in slots:
            slots[sn] = {'fields': {}, 'hex_lines': [], 'record_length': 0}
        len_match = re.search(r'Length (\d+)', parent)
        if len_match:
            slots[sn]['record_length'] = int(len_match.group(1))
        if not field and re.match(r'[0-9a-fA-F]{10,}:', value):
            slots[sn]['hex_lines'].append(value)
        elif field:
            slots[sn]['fields'][field] = value

for sn in sorted(slots.keys()):
    s = slots[sn]
    print(f"\n--- Slot {sn} (length={s['record_length']}) ---")
    for k, v in s['fields'].items():
        marker = ""
        if 'prev' in k.lower():
            marker = " <<<"
        if 'balance' in k.lower() or k == 'min_len':
            marker = " ***"
        print(f"  {k} = {v}{marker}")
    
    # Parse hex to get raw bytes at offset 46 (prev_row_in_chain)
    all_bytes = []
    for line in s['hex_lines']:
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
    
    if len(all_bytes) >= 54:
        chain_bytes = all_bytes[46:54]
        chain_page = int.from_bytes(bytes(chain_bytes[0:4]), 'little')
        chain_file = int.from_bytes(bytes(chain_bytes[4:6]), 'little')
        chain_slot = int.from_bytes(bytes(chain_bytes[6:8]), 'little')
        print(f"  [hex@46] prev_row_in_chain: page={chain_page}, file={chain_file}, slot={chain_slot}")
        print(f"           raw: {' '.join(f'{b:02X}' for b in chain_bytes)}")

conn.close()
