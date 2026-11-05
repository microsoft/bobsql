"""Diagnostic: Check PVS chain for AccountId 42.
Shows what read_pvs_record sees and whether prev_row_in_chain exists."""
import sys, re, struct
sys.path.insert(0, '.')
from dbcc_page_viewer_adr import (
    get_connection, find_page_for_row, run_dbcc_page,
    parse_version_from_hex, read_pvs_record
)

DATABASE = 'texasrangerswillwinitthisyear'

conn = get_connection('localhost', DATABASE, 'windows')
cursor = conn.cursor()

# Find AccountId 42's page
file_id, page_id, slot_num = find_page_for_row(cursor, DATABASE, '42', 'Accounts')
print(f"Page for AccountId 42: file={file_id}, page={page_id}, slot={slot_num}")

# DBCC PAGE on data page
rows = run_dbcc_page(cursor, DATABASE, file_id, page_id)

# Find the slot with AccountId 42 (we already know it)
target_slot = slot_num

print(f"AccountId 42 is at slot {target_slot}")

# Get hex lines and fields for this slot
hex_lines = []
fields = {}
record_length = 0
target_str = f"Slot {target_slot}"
for r in rows:
    parent = str(r[0]) if r[0] else ""
    field = str(r[2]) if r[2] else ""
    value = str(r[3]) if r[3] else ""
    # Use word boundary matching to avoid Slot 4 matching Slot 42
    if re.search(rf'\bSlot {target_slot}\b', parent):
        len_match = re.search(r'Length (\d+)', parent)
        if len_match:
            record_length = int(len_match.group(1))
        if not field and re.match(r'[0-9a-fA-F]{10,}:', value):
            hex_lines.append(value)
        elif field:
            fields[field] = value

print(f"\nData page fields for slot {target_slot}:")
for k, v in fields.items():
    print(f"  {k} = {v}")

# Parse version info
vi = parse_version_from_hex(hex_lines, record_length)
if not vi:
    print("\nNo version tag found!")
    sys.exit(1)

slot_id = vi.get('pointer_slot', '?')
is_inrow = vi.get('is_inrow', False)
print(f"\nVersion tag: slot={slot_id}, is_inrow={is_inrow}")
print(f"  pointer_page={vi.get('pointer_page')}, pointer_file={vi.get('pointer_file')}")
print(f"  pointer_pvs={vi.get('pointer_pvs')}")
print(f"  XSN={vi.get('XSN')}")

if is_inrow:
    print(f"  inrow_payload_type={vi.get('inrow_payload_type')}")
    print(f"  inrow_payload_len={vi.get('inrow_payload_len')}")
    if vi.get('diff_info'):
        di = vi['diff_info']
        print(f"  diff_info: count={di['count']}")
        for i, e in enumerate(di['entries']):
            print(f"    entry[{i}]: old_offset={e.get('old_offset')}, new_offset={e.get('new_offset')}, "
                  f"old_size={e.get('old_size')}, new_size={e.get('new_size')}")
            if 'old_value' in e:
                print(f"      old_value hex: {' '.join(f'{b:02X}' for b in e['old_value'])}")
    print("\n(In-row version - no PVS chain to chase)")
else:
    # Off-row: chase PVS
    ptr_page = vi.get('pointer_page')
    ptr_file = vi.get('pointer_file')
    ptr_slot = vi.get('pointer_slot')
    dbcc_fid = vi.get('dbcc_file_id', ptr_file)

    print(f"\n--- Chasing PVS: file={dbcc_fid}, page={ptr_page}, slot={ptr_slot} ---")
    
    # Raw DBCC PAGE on PVS page to see all fields
    pvs_rows = run_dbcc_page(cursor, DATABASE, int(dbcc_fid), int(ptr_page))
    pvs_target = f"Slot {ptr_slot}"
    pvs_fields_raw = {}
    pvs_hex = []
    for r in pvs_rows:
        parent = str(r[0]) if r[0] else ""
        field = str(r[2]) if r[2] else ""
        value = str(r[3]) if r[3] else ""
        if re.search(rf'\bSlot {ptr_slot}\b', parent):
            if not field and re.match(r'[0-9a-fA-F]{10,}:', value):
                pvs_hex.append(value)
            elif field:
                pvs_fields_raw[field] = value

    print(f"\nPVS record V1 (slot {ptr_slot}) - ALL fields from DBCC PAGE:")
    for k, v in pvs_fields_raw.items():
        marker = " <<<" if 'prev' in k.lower() or 'chain' in k.lower() else ""
        print(f"  {k} = {v}{marker}")

    # Now use read_pvs_record
    decoded, err = read_pvs_record(cursor, DATABASE, dbcc_fid, ptr_page, ptr_slot)
    print(f"\nread_pvs_record result:")
    if err:
        print(f"  ERROR: {err}")
    if decoded:
        for k, v in decoded.items():
            print(f"  {k} = {v}")
        chain_ptr = decoded.get('_prev_row_in_chain', decoded.get('prev_row_in_chain', ''))
        print(f"\n  chain_ptr = '{chain_ptr}'")
        if chain_ptr and chain_ptr not in ('0x0000000000000000', ''):
            # Parse and chase
            chain_hex = chain_ptr[2:] if chain_ptr.startswith('0x') else chain_ptr
            chain_bytes_raw = bytes.fromhex(chain_hex)
            chain_page_id = int.from_bytes(chain_bytes_raw[0:4], 'little')
            chain_file_id = int.from_bytes(chain_bytes_raw[4:6], 'little')
            chain_slot_id = int.from_bytes(chain_bytes_raw[6:8], 'little')
            print(f"  Parsed chain: file={chain_file_id}, page={chain_page_id}, slot={chain_slot_id}")

            print(f"\n--- Chasing chain to V2: file={chain_file_id}, page={chain_page_id}, slot={chain_slot_id} ---")
            decoded2, err2 = read_pvs_record(cursor, DATABASE, chain_file_id, chain_page_id, chain_slot_id)
            if err2:
                print(f"  ERROR: {err2}")
            if decoded2:
                for k, v in decoded2.items():
                    print(f"  {k} = {v}")
        else:
            print("  No chain link (end of chain or prev_row_in_chain not found)")
    else:
        print("  No decoded values")
        if pvs_fields_raw:
            print("  (But raw fields exist - check field names above)")

conn.close()
print("\nDone.")
