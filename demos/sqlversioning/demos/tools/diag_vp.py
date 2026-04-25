"""Diagnostic: parse the version pointer bytes for AccountId 42."""
from mssql_python import connect as mssql_connect
import re, struct

conn = mssql_connect('Server=localhost;Database=texasrangerswillwinitthisyear;Trusted_Connection=yes;Encrypt=no')
cur = conn.cursor()

# Find page for AccountId 42
cur.execute("""SELECT allocated_page_file_id, allocated_page_page_id
FROM sys.dm_db_database_page_allocations(DB_ID(), OBJECT_ID('dbo.Accounts'), NULL, NULL, 'DETAILED')
WHERE page_type_desc = 'DATA_PAGE' ORDER BY allocated_page_page_id""")
pages = [(r[0], r[1]) for r in cur.fetchall()]

cur.execute('DBCC TRACEON(3604)')
for fid, pid in pages:
    cur.execute(f"DBCC PAGE(N'texasrangerswillwinitthisyear', {fid}, {pid}, 3) WITH TABLERESULTS")
    rows = cur.fetchall()
    target_slot = None
    for r in rows:
        parent = str(r[0]) if r[0] else ''
        field = str(r[2]) if r[2] else ''
        value = str(r[3]) if r[3] else ''
        if field == 'AccountId' and value == '42':
            slot_match = re.search(r'Slot (\d+)', parent)
            target_slot = f'Slot {slot_match.group(1)}' if slot_match else None
            print(f'Found AccountId 42: file={fid} page={pid} slot={slot_match.group(1)}')
            break
    if not target_slot:
        continue

    # Collect hex lines and record length for this slot
    hex_lines = []
    record_length = 0
    for r in rows:
        parent = str(r[0]) if r[0] else ''
        field = str(r[2]) if r[2] else ''
        value = str(r[3]) if r[3] else ''
        if target_slot in parent:
            len_match = re.search(r'Length (\d+)', parent)
            if len_match:
                record_length = int(len_match.group(1))
            if not field and re.match(r'[0-9a-fA-F]{10,}:', value):
                hex_lines.append(value)

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

    print(f'Record length: {record_length}, parsed bytes: {len(all_bytes)}')
    print(f'StatusA: 0x{all_bytes[0]:02X} (version tag: {bool(all_bytes[0] & 0x40)}, var cols: {bool(all_bytes[0] & 0x20)})')

    # Parse to find VP offset
    pminlen = int.from_bytes(bytes(all_bytes[2:4]), 'little')
    print(f'pminlen: {pminlen}')

    col_count = int.from_bytes(bytes(all_bytes[pminlen:pminlen+2]), 'little')
    null_bitmap_bytes = (col_count + 7) // 8
    after_null = pminlen + 2 + null_bitmap_bytes
    print(f'col_count: {col_count}, null_bitmap_bytes: {null_bitmap_bytes}, after_null: {after_null}')

    var_col_count = int.from_bytes(bytes(all_bytes[after_null:after_null+2]), 'little')
    print(f'var_col_count: {var_col_count}')

    # Print all var col end offsets
    for vc in range(var_col_count):
        off_pos = after_null + 2 + vc * 2
        off_val = int.from_bytes(bytes(all_bytes[off_pos:off_pos+2]), 'little')
        print(f'  var_col[{vc}] end offset: {off_val} (0x{off_val:04X})')

    last_offset_pos = after_null + 2 + (var_col_count - 1) * 2
    vp_offset = int.from_bytes(bytes(all_bytes[last_offset_pos:last_offset_pos+2]), 'little')
    print(f'VP offset (from last var col end): {vp_offset}')

    # Show VP bytes
    vp = all_bytes[vp_offset:vp_offset+14]
    print(f'VP bytes ({len(vp)}): {" ".join(f"{b:02X}" for b in vp)}')

    # Decode VP
    if len(vp) >= 8:
        raw_page = int.from_bytes(bytes(vp[0:4]), 'little', signed=True)
        pvs_bit = bool(raw_page & 0x80000000)
        page_id = raw_page & 0x7FFFFFFF
        file_id = int.from_bytes(bytes(vp[4:6]), 'little')
        slot_raw = int.from_bytes(bytes(vp[6:8]), 'little', signed=True)

        print(f'\nOff-row interpretation:')
        print(f'  raw_page_id: {raw_page} (0x{raw_page & 0xFFFFFFFF:08X})')
        print(f'  PVS bit: {pvs_bit}')
        print(f'  page_id: {page_id}')
        print(f'  file_id: {file_id}')
        print(f'  slot_id_raw: {slot_raw} (0x{slot_raw & 0xFFFF:04X})')

        # In-row check
        if slot_raw == -4:
            print(f'\n*** IN-ROW version (slot = -4) ***')
            nest_id = int.from_bytes(bytes(vp[0:4]), 'little')
            payload_type = file_id & 0x1F
            payload_len = (file_id >> 5) & 0x7FF
            print(f'  NestId: {nest_id}')
            print(f'  PayloadType: {payload_type}')
            print(f'  PayloadLen: {payload_len}')
        else:
            print(f'\n*** OFF-ROW version (slot = {slot_raw}) ***')

    if len(vp) >= 14:
        ts_low = int.from_bytes(bytes(vp[8:12]), 'little')
        ts_high = int.from_bytes(bytes(vp[12:14]), 'little')
        xdes_ts = (ts_high << 32) | ts_low
        print(f'  XdesTs: {xdes_ts}')

    # Show remaining bytes after VP (diff data if any)
    remaining = len(all_bytes) - (vp_offset + 14)
    if remaining > 0:
        diff_bytes = all_bytes[vp_offset+14:]
        print(f'\nBytes after VP ({remaining}): {" ".join(f"{b:02X}" for b in diff_bytes[:50])}')
    else:
        print(f'\nNo bytes after VP (record ends at VP)')

    break

conn.close()
