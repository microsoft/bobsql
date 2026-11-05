"""
ADR Page Viewer — Web app to display DBCC PAGE output with
ADR versioning: in-row version stubs vs off-row PVS records.

Usage:
  python dbcc_page_viewer_adr.py
  Open http://localhost:5051 in browser

Enter: server, database, file_id, page_id (or Find Row by AccountId)
Shows formatted page contents with ADR version info highlighted.
Runs on port 5051 so it can coexist with the tempdb page viewer on 5050.
"""
from flask import Flask, render_template_string, request
from mssql_python import connect as mssql_connect
import re

app = Flask(__name__)

HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>ADR Page Viewer</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: 'Segoe UI', sans-serif; 
            background: #f2f7f5; 
            color: #1e1e28; 
            padding: 20px;
        }
        h1 { color: #0e7c5a; margin-bottom: 5px; font-size: 24px; }
        .subtitle { color: #78788c; font-size: 14px; margin-bottom: 20px; }
        
        .form-row {
            display: flex; gap: 12px; margin-bottom: 20px; align-items: end;
        }
        .form-group { display: flex; flex-direction: column; }
        .form-group label { font-size: 12px; color: #78788c; margin-bottom: 3px; }
        .form-group input, .form-group select {
            padding: 8px 12px; border: 1px solid #ccc; border-radius: 6px;
            font-size: 14px; font-family: 'Segoe UI', sans-serif;
        }
        .form-group input:focus { outline: 2px solid #0e7c5a; border-color: transparent; }
        button {
            padding: 8px 20px; background: #0e7c5a; color: white; border: none;
            border-radius: 6px; font-size: 14px; cursor: pointer;
        }
        button:hover { background: #0a5e44; }
        
        .results { margin-top: 20px; }
        
        .page-header-box {
            background: #e4f0ec; border: 2px solid #0e7c5a; border-radius: 10px;
            padding: 15px; margin-bottom: 15px;
        }
        .page-header-box h2 { color: #0e7c5a; font-size: 16px; margin-bottom: 10px; }
        .page-header-box .field { display: inline-block; margin-right: 20px; margin-bottom: 5px; }
        .page-header-box .field-label { font-size: 11px; color: #78788c; }
        .page-header-box .field-value { font-size: 14px; font-weight: bold; }
        
        .slot-box {
            background: white; border: 2px solid #ddd; border-radius: 10px;
            padding: 15px; margin-bottom: 12px; transition: all 0.2s;
        }
        .slot-box:hover { border-color: #0e7c5a; box-shadow: 0 2px 8px rgba(14,124,90,0.1); }
        .slot-box.has-inrow { border-color: #0e7c5a; border-width: 3px; }
        .slot-box.has-offrow { border-color: #8b5cf6; border-width: 3px; }
        .slot-header { 
            font-size: 14px; font-weight: bold; color: #0e7c5a; 
            margin-bottom: 8px; 
        }
        .slot-header .slot-num { 
            background: #0e7c5a; color: white; padding: 2px 8px; 
            border-radius: 4px; font-size: 12px; margin-right: 8px;
        }
        
        .field-grid { 
            display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); 
            gap: 8px; margin-bottom: 10px;
        }
        .field-item {
            background: #f0f5f3; padding: 6px 10px; border-radius: 6px;
            overflow: hidden; min-width: 0;
        }
        .field-item .fname { font-size: 11px; color: #78788c; }
        .field-item .fval { font-size: 13px; font-weight: 500; overflow-wrap: break-word; word-break: break-all; }
        
        .version-inrow {
            background: #e6f7ef; border: 2px solid #0e7c5a; border-radius: 8px;
            padding: 10px 15px; margin-top: 10px;
        }
        .version-inrow h3 { color: #0e7c5a; font-size: 13px; margin-bottom: 6px; }
        
        .version-offrow {
            background: #f0e8ff; border: 2px solid #8b5cf6; border-radius: 8px;
            padding: 10px 15px; margin-top: 10px;
        }
        .version-offrow h3 { color: #8b5cf6; font-size: 13px; margin-bottom: 6px; }
        
        .version-tag-table {
            border-collapse: collapse; width: 100%; font-size: 13px; margin-bottom: 8px;
        }
        .version-tag-table td { padding: 4px 10px; border: 1px solid #ddd; }
        .version-tag-table td.mono { font-family: monospace; font-size: 12px; }
        
        .no-version {
            background: #f5f5f5; border: 1px solid #ccc; border-radius: 8px;
            padding: 8px 15px; margin-top: 10px; color: #78788c; font-size: 12px;
        }
        
        .error { color: #c82828; background: #fde; padding: 15px; border-radius: 10px; }
        
        .pvs-stats-box {
            background: #f0e8ff; border: 2px solid #8b5cf6; border-radius: 10px;
            padding: 15px; margin-top: 20px;
        }
        .pvs-stats-box h2 { color: #8b5cf6; font-size: 16px; margin-bottom: 10px; }
        .pvs-stats-box .stat { display: inline-block; margin-right: 25px; margin-bottom: 8px; }
        .pvs-stats-box .stat-label { font-size: 11px; color: #78788c; }
        .pvs-stats-box .stat-value { font-size: 18px; font-weight: bold; color: #1e1e28; }
        
        .tempdb-clean-box {
            background: #e6f7ef; border: 2px solid #0e7c5a; border-radius: 10px;
            padding: 12px 20px; margin-top: 15px; text-align: center;
        }
        .tempdb-clean-box .label { font-size: 14px; color: #0e7c5a; font-weight: bold; }
        .tempdb-clean-box .value { font-size: 13px; color: #78788c; }
        
        .adr-callout {
            border-radius: 10px; padding: 12px 20px; margin: 15px 0; 
            text-align: center; font-size: 15px; font-weight: bold;
        }
        .adr-callout.inrow {
            background: linear-gradient(135deg, #e6f7ef, #d4f0e4);
            border: 2px dashed #0e7c5a; color: #0e7c5a;
        }
        .adr-callout.offrow {
            background: linear-gradient(135deg, #f0e8ff, #e4d8f8);
            border: 2px dashed #8b5cf6; color: #8b5cf6;
        }
        .adr-callout .arrow { font-size: 24px; margin: 0 10px; }
        
    </style>
</head>
<body>
    <h1>ADR Page Viewer</h1>
    <div class="subtitle">Accelerated Database Recovery — In-Row vs Off-Row (PVS) Versioning</div>
    
    <form method="POST" class="form-row">
        <div class="form-group">
            <label>Server</label>
            <input name="server" value="{{ server or 'localhost' }}" style="width:200px">
        </div>
        <div class="form-group">
            <label>Database</label>
            <input name="database" value="{{ database or 'texasrangerswillwinitthisyear' }}" style="width:250px">
        </div>
        <div class="form-group">
            <label>Auth</label>
            <select name="auth">
                <option value="trusted" {{ 'selected' if auth != 'sql' else '' }}>Windows Auth</option>
                <option value="sql" {{ 'selected' if auth == 'sql' else '' }}>SQL Auth</option>
            </select>
        </div>
        <div class="form-group">
            <label>Table</label>
            <select name="table_name">
                <option value="Accounts" {{ 'selected' if table_name == 'Accounts' else '' }}>Accounts</option>
                <option value="SavingsAccounts" {{ 'selected' if table_name == 'SavingsAccounts' else '' }}>SavingsAccounts</option>
            </select>
        </div>
        <div class="form-group">
            <label>File ID</label>
            <input name="file_id" value="{{ file_id or '1' }}" style="width:60px">
        </div>
        <div class="form-group">
            <label>Page ID</label>
            <input name="page_id" value="{{ page_id or '' }}" style="width:100px" placeholder="e.g. 320">
        </div>
        <div class="form-group">
            <label>Find Row (AccountId)</label>
            <input name="find_row" value="{{ find_row or '42' }}" style="width:120px" placeholder="e.g. 42">
        </div>
        <button type="submit">View Page</button>
    </form>
    
    {% if error %}
    <div class="error">{{ error }}</div>
    {% endif %}
    
    {% if page_data %}
    <div class="results">
        {{ page_data | safe }}
    </div>
    {% endif %}
</body>
</html>
"""


def get_connection(server, database, auth):
    parts = [f"Server={server}", f"Database={database}", "Encrypt=no", "TrustServerCertificate=yes"]
    if auth != 'sql':
        parts.append("Trusted_Connection=yes")
    conn = mssql_connect(";".join(parts))
    conn.autocommit = True
    return conn


def find_page_for_row(cursor, database, account_id, table_name='Accounts'):
    """Find the page for a specific AccountId using system metadata + DBCC PAGE."""
    cursor.execute(f"""
        SELECT allocated_page_file_id, allocated_page_page_id
        FROM sys.dm_db_database_page_allocations(DB_ID(), OBJECT_ID('dbo.{table_name}'), NULL, NULL, 'DETAILED')
        WHERE page_type_desc = 'DATA_PAGE'
        ORDER BY allocated_page_page_id
    """)
    pages = [(row[0], row[1]) for row in cursor.fetchall()]

    cursor.execute("DBCC TRACEON(3604)")
    for fid, pid in pages:
        cursor.execute(f"DBCC PAGE(N'{database}', {fid}, {pid}, 3) WITH TABLERESULTS")
        rows = cursor.fetchall()
        for r in rows:
            parent = str(r[0]) if r[0] else ""
            field = str(r[2]) if r[2] else ""
            value = str(r[3]) if r[3] else ""
            if field == "AccountId" and value == str(int(account_id)):
                slot_match = re.search(r'Slot (\d+)', parent)
                if slot_match:
                    return fid, pid, int(slot_match.group(1))
    return None, None, None


def run_dbcc_page(cursor, database, file_id, page_id):
    """Run DBCC PAGE WITH TABLERESULTS and return rows."""
    cursor.execute("DBCC TRACEON(3604)")
    cursor.execute(f"DBCC PAGE(N'{database}', {file_id}, {page_id}, 3) WITH TABLERESULTS")
    rows = cursor.fetchall()
    return rows


def read_pvs_record(cursor, database, dbcc_file_id, page_id, slot_id):
    """Chase an off-row PVS pointer: DBCC PAGE the PVS page and extract
    the embedded before-image row from the target slot.
    
    PVS records store the full before-image row in a variable-length column
    (row_version). We parse the PVS record hex dump to find and decode it.
    
    Returns (dict_of_decoded_values, None) on success, or (None, error_string) on failure."""
    try:
        rows = run_dbcc_page(cursor, database, int(dbcc_file_id), int(page_id))
        target_slot = f"Slot {slot_id}"
        fields = {}
        hex_lines = []
        record_length = 0
        all_slots_found = set()
        for r in rows:
            parent = str(r[0]) if r[0] else ""
            field = str(r[2]) if r[2] else ""
            value = str(r[3]) if r[3] else ""
            slot_match = re.search(r'Slot (\d+)', parent)
            if slot_match:
                all_slots_found.add(int(slot_match.group(1)))
            if target_slot in parent:
                len_match = re.search(r'Length (\d+)', parent)
                if len_match:
                    record_length = int(len_match.group(1))
                if not field and re.match(r'[0-9a-fA-F]{10,}:', value):
                    hex_lines.append(value)
                elif field:
                    if field not in ('KeyHashValue', 'UNIQUIFIER'):
                        fields[field] = value

        if not hex_lines and not fields:
            slots_str = ', '.join(str(s) for s in sorted(all_slots_found)) if all_slots_found else 'none'
            return None, (f"DBCC PAGE('{database}', {dbcc_file_id}, {page_id}, 3) returned "
                          f"{len(rows)} rows. Slots found: [{slots_str}]. "
                          f"Looking for '{target_slot}' - no matching fields.")

        # Parse hex dump to get PVS record bytes
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

        # The PVS record is a standard SQL record for the internal PVS table.
        # The embedded user row is in a variable-length column (row_version).
        # Parse the PVS record structure to find it.
        decoded = {}
        if len(all_bytes) > 4:
            import struct
            pvs_status = all_bytes[0]
            pvs_pminlen = int.from_bytes(bytes(all_bytes[2:4]), 'little')

            # Skip to null bitmap after fixed columns
            pos = pvs_pminlen
            if pos + 2 <= len(all_bytes):
                col_count = int.from_bytes(bytes(all_bytes[pos:pos+2]), 'little')
                null_bitmap_len = (col_count + 7) // 8
                pos += 2 + null_bitmap_len

                # Variable columns (if StatusA & 0x20)
                if pvs_status & 0x20 and pos + 2 <= len(all_bytes):
                    var_col_count = int.from_bytes(bytes(all_bytes[pos:pos+2]), 'little')
                    pos += 2
                    var_offsets = []
                    for vc in range(var_col_count):
                        if pos + 2 <= len(all_bytes):
                            var_offsets.append(int.from_bytes(bytes(all_bytes[pos:pos+2]), 'little'))
                            pos += 2

                    # The last variable column should be row_version (the embedded row).
                    # Variable offset array stores cumulative end offsets.
                    # Start of var col N = end of var col N-1 (or start of var data area).
                    if var_offsets:
                        # pos now points just after the offset array = start of variable data
                        var_data_start = pos
                        if len(var_offsets) >= 2:
                            row_start = var_offsets[-2]
                        else:
                            row_start = var_data_start
                        row_end = var_offsets[-1]
                        embedded_row = all_bytes[row_start:row_end]

                        # Decode the embedded user row
                        if len(embedded_row) > 25:
                            # Balance DECIMAL(18,2) @ offset 8, 9 bytes
                            dec_bytes = embedded_row[8:17]
                            if len(dec_bytes) == 9:
                                sign = dec_bytes[0]
                                int_val = int.from_bytes(bytes(dec_bytes[1:9]), 'little')
                                decimal_val = int_val / 100.0
                                if sign == 0:
                                    decimal_val = -decimal_val
                                decoded['Balance'] = f'{decimal_val:,.2f}'

                            # LastUpdated DATETIME2(7) @ offset 17, 8 bytes
                            dt_bytes = embedded_row[17:25]
                            if len(dt_bytes) == 8:
                                time_val = int.from_bytes(bytes(dt_bytes[0:5]), 'little')
                                date_val = int.from_bytes(bytes(dt_bytes[5:8]), 'little')
                                try:
                                    from datetime import datetime, timedelta
                                    base = datetime(1, 1, 1)
                                    dt = base + timedelta(days=date_val, microseconds=time_val / 10)
                                    decoded['LastUpdated'] = dt.strftime('%Y-%m-%d %H:%M:%S.%f')
                                except (ValueError, OverflowError):
                                    decoded['LastUpdated'] = f'(raw: {" ".join(f"{b:02X}" for b in dt_bytes)})'

        if decoded:
            # Parse embedded version pointer from the PVS row_version bytes.
            # This is the REAL version chain link (VersionRecPtr within the row data),
            # NOT the PVS metadata prev_row_in_chain column.
            try:
                embedded_vi = parse_version_ptr_from_record_bytes(embedded_row, force=True)
                if embedded_vi:
                    decoded['_embedded_version_info'] = embedded_vi
                    # If INROW_FULLROW, the payload within this row IS the next-older version
                    if embedded_vi.get('inrow_payload_type_raw') == 1:
                        payload = embedded_vi.get('inrow_payload_bytes')
                        if payload and len(payload) > 25:
                            dec_b = payload[8:17]
                            if len(dec_b) == 9:
                                sign = dec_b[0]
                                int_v = int.from_bytes(bytes(dec_b[1:9]), 'little')
                                dv = int_v / 100.0
                                if sign == 0:
                                    dv = -dv
                                decoded['_inrow_old_Balance'] = f'{dv:,.2f}'
                            dt_b = payload[17:25]
                            if len(dt_b) == 8:
                                time_v = int.from_bytes(bytes(dt_b[0:5]), 'little')
                                date_v = int.from_bytes(bytes(dt_b[5:8]), 'little')
                                try:
                                    from datetime import datetime, timedelta
                                    base = datetime(1, 1, 1)
                                    dt = base + timedelta(days=date_v, microseconds=time_v / 10)
                                    decoded['_inrow_old_LastUpdated'] = dt.strftime('%Y-%m-%d %H:%M:%S.%f')
                                except (ValueError, OverflowError):
                                    decoded['_inrow_old_LastUpdated'] = f'(raw: {" ".join(f"{b:02X}" for b in dt_b)})'
                    # If INROW_MODIFY_DIFF, reconstruct V0 by splicing old bytes into V1
                    elif embedded_vi.get('inrow_payload_type_raw') == 2:
                        payload = embedded_vi.get('inrow_payload_bytes')
                        if payload and len(payload) >= 4:
                            try:
                                v0_row = _reconstruct_from_modify_diff(embedded_row, payload)
                                if v0_row and len(v0_row) > 25:
                                    dec_b = v0_row[8:17]
                                    if len(dec_b) == 9:
                                        sign = dec_b[0]
                                        int_v = int.from_bytes(bytes(dec_b[1:9]), 'little')
                                        dv = int_v / 100.0
                                        if sign == 0:
                                            dv = -dv
                                        decoded['_inrow_old_Balance'] = f'{dv:,.2f}'
                                    dt_b = v0_row[17:25]
                                    if len(dt_b) == 8:
                                        time_v = int.from_bytes(bytes(dt_b[0:5]), 'little')
                                        date_v = int.from_bytes(bytes(dt_b[5:8]), 'little')
                                        try:
                                            from datetime import datetime, timedelta
                                            base = datetime(1, 1, 1)
                                            dt = base + timedelta(days=date_v, microseconds=time_v / 10)
                                            decoded['_inrow_old_LastUpdated'] = dt.strftime('%Y-%m-%d %H:%M:%S.%f')
                                        except (ValueError, OverflowError):
                                            decoded['_inrow_old_LastUpdated'] = f'(raw: {" ".join(f"{b:02X}" for b in dt_b)})'
                            except Exception:
                                pass
            except Exception as e:
                decoded['_vp_parse_error'] = str(e)

            # Include chain pointer from named fields so renderer can display it.
            # Use case-insensitive matching since DBCC PAGE field names may vary.
            chain_val = None
            for fname, fval in fields.items():
                if fname.lower().replace(' ', '_') == 'prev_row_in_chain':
                    chain_val = fval
                    break
            if not chain_val:
                # Fallback: look for any field containing "prev" and "chain"
                for fname, fval in fields.items():
                    fl = fname.lower()
                    if 'prev' in fl and 'chain' in fl:
                        chain_val = fval
                        break
            if not chain_val and len(all_bytes) >= 54:
                # Fallback: parse prev_row_in_chain from PVS record hex dump.
                # PVS internal table fixed layout (after StatusA/B/pminlen):
                #   offset 4:  xdes_ts_push (8)
                #   offset 12: xdes_ts_tran (8)
                #   offset 20: min_len (2)
                #   offset 22: seq_num (8)
                #   offset 30: subid_push (4)
                #   offset 34: subid_tran (4)
                #   offset 38: rowset_id (8)
                #   offset 46: prev_row_in_chain (8)  = PageId(4)+FileId(2)+SlotId(2)
                chain_bytes = all_bytes[46:54]
                chain_page = int.from_bytes(bytes(chain_bytes[0:4]), 'little')
                chain_file = int.from_bytes(bytes(chain_bytes[4:6]), 'little')
                chain_slot = int.from_bytes(bytes(chain_bytes[6:8]), 'little')
                if chain_page != 0:
                    chain_val = f'0x{bytes(chain_bytes).hex()}'
            if chain_val:
                decoded['_prev_row_in_chain'] = chain_val
            return decoded, None
        elif fields:
            # Fallback: return PVS metadata fields if we couldn't decode the row
            return fields, None
        else:
            return None, "Could not decode embedded row from PVS record hex dump"
    except Exception as e:
        return None, f"Exception chasing PVS: {e}"


def get_pvs_stats(cursor, database):
    """Get PVS stats for this database."""
    cursor.execute(f"""
        SELECT 
            persistent_version_store_size_kb,
            online_index_version_store_size_kb,
            current_aborted_transaction_count,
            aborted_version_cleaner_start_time,
            aborted_version_cleaner_end_time
        FROM sys.dm_tran_persistent_version_store_stats
        WHERE database_id = DB_ID(N'{database}')
    """)
    row = cursor.fetchone()
    if row:
        return {
            'pvs_size_kb': row[0],
            'online_idx_kb': row[1],
            'aborted_txn_count': row[2],
            'cleaner_start': str(row[3]) if row[3] else 'N/A',
            'cleaner_end': str(row[4]) if row[4] else 'N/A',
        }
    return None


def get_tempdb_version_store_kb(cursor, database):
    """Get tempdb version store usage for this database."""
    cursor.execute(f"""
        SELECT reserved_space_kb
        FROM sys.dm_tran_version_store_space_usage
        WHERE database_id = DB_ID(N'{database}')
    """)
    row = cursor.fetchone()
    return row[0] if row else 0


def parse_version_from_hex(hex_lines, record_length):
    """Parse version tag from the hex dump of a DBCC PAGE record.
    
    The version pointer (RecVersioningInfo, 14 bytes) is placed right after
    the last variable-length column, NOT at the end of the record. For in-row
    diff records (slot = -4), the diff data is appended AFTER the pointer,
    making the record longer. We must parse the record structure to find
    the correct offset.
    
    Record layout:
      [0]    StatusA  (1 byte)
      [1]    StatusB  (1 byte)
      [2-3]  pminlen  (INT16, end of fixed columns)
      [4..pminlen-1]  fixed column data
      [pminlen..pminlen+1]  column count (INT16)
      [pminlen+2..] null bitmap (ceil(col_count/8) bytes)
      if StatusA & 0x20 (has variable columns):
        var_col_count (INT16)
        var_col_offsets (INT16 * var_col_count)
        variable column data
      [vp_offset..vp_offset+13]  RecVersioningInfo (14 bytes, if StatusA & 0x40)
      [vp_offset+14..]  in-row diff data (if slot = -4)
    """
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

    if not all_bytes or len(all_bytes) < 4:
        return None

    status_byte = all_bytes[0]
    if not (status_byte & 0x40):
        return None

    result = {'status_byte': status_byte}

    # Parse record structure to find version pointer offset
    pminlen = int.from_bytes(bytes(all_bytes[2:4]), 'little')
    if pminlen >= len(all_bytes):
        return result  # truncated record

    col_count = int.from_bytes(bytes(all_bytes[pminlen:pminlen+2]), 'little')
    null_bitmap_bytes = (col_count + 7) // 8
    after_null = pminlen + 2 + null_bitmap_bytes

    if status_byte & 0x20 and after_null + 2 <= len(all_bytes):
        # Has variable-length columns
        var_col_count = int.from_bytes(bytes(all_bytes[after_null:after_null+2]), 'little')
        if var_col_count > 0:
            # Last var col end offset tells us where column data ends
            last_offset_pos = after_null + 2 + (var_col_count - 1) * 2
            if last_offset_pos + 2 <= len(all_bytes):
                vp_offset = int.from_bytes(bytes(all_bytes[last_offset_pos:last_offset_pos+2]), 'little')
            else:
                vp_offset = len(all_bytes) - 14  # fallback
        else:
            vp_offset = after_null + 2
    else:
        # No variable columns — version pointer right after null bitmap
        vp_offset = after_null

    if vp_offset + 14 > len(all_bytes):
        return result  # not enough bytes

    vp = all_bytes[vp_offset:vp_offset+14]

    # Check if there's diff data after the version pointer
    diff_data_len = len(all_bytes) - (vp_offset + 14)
    result['vp_offset'] = vp_offset
    result['diff_data_len'] = diff_data_len

    # Parse per RecVersioningInfo layout (pvs-version-pointer-format.md)
    raw_page_id = int.from_bytes(bytes(vp[0:4]), 'little', signed=True)  # INT32
    pvs = bool(raw_page_id & 0x80000000)
    page_id = raw_page_id & 0x7FFFFFFF  # clear PVS bit for real page number
    file_id = int.from_bytes(bytes(vp[4:6]), 'little')  # UINT16
    slot_id_raw = int.from_bytes(bytes(vp[6:8]), 'little', signed=True)  # INT16

    # PVS-specific: LONG_PVS_MASK (bit 15) means long-term PVS version
    is_long_pvs = bool(slot_id_raw & 0x8000) if pvs else False
    slot_id = slot_id_raw & 0x07FF if is_long_pvs else slot_id_raw

    ts_low = int.from_bytes(bytes(vp[8:12]), 'little')
    ts_high = int.from_bytes(bytes(vp[12:14]), 'little')
    xdes_ts = (ts_high << 32) | ts_low

    # For DBCC PAGE, FileId 0 = primary data file = file_id 1
    dbcc_file_id = file_id if file_id > 0 else 1

    result['pointer_page'] = str(page_id)
    result['pointer_file'] = str(file_id)
    result['dbcc_file_id'] = str(dbcc_file_id)
    result['pointer_slot'] = str(slot_id)
    result['pointer_slot_raw'] = str(slot_id_raw)
    result['pointer_pvs'] = pvs
    result['is_long_pvs'] = is_long_pvs
    result['pointer_hex'] = ' '.join(f'{b:02X}' for b in vp[0:8])
    result['XSN'] = str(xdes_ts)
    result['xsn_hex'] = ' '.join(f'{b:02X}' for b in vp[8:14])
    result['is_inrow'] = (slot_id_raw == -4)

    # If in-row diff, parse InRowVer fields from the 8-byte VersionRecPtr
    if slot_id_raw == -4:
        nest_id = int.from_bytes(bytes(vp[0:4]), 'little')  # UINT32 m_NestId
        fileid_raw = file_id  # UINT16 with bitfields (MSVC LSB-first)
        payload_type = fileid_raw & 0x1F           # lower 5 bits
        payload_len = (fileid_raw >> 5) & 0x7FF    # upper 11 bits
        type_names = {0: 'INROW_NULL', 1: 'INROW_FULLROW',
                      2: 'INROW_MODIFY_DIFF', 3: 'INROW_NEW_INSERT'}
        result['inrow_nest_id'] = nest_id
        result['inrow_payload_type'] = type_names.get(payload_type, f'UNKNOWN({payload_type})')
        result['inrow_payload_type_raw'] = payload_type
        result['inrow_payload_len'] = payload_len

        # Extract the diff payload bytes (immediately after the 14-byte version tag)
        diff_start = vp_offset + 14
        if payload_len > 0 and diff_start + payload_len <= len(all_bytes):
            diff_bytes = all_bytes[diff_start:diff_start + payload_len]
            result['diff_payload_hex'] = ' '.join(f'{b:02X}' for b in diff_bytes)

            # Parse INROW_MODIFY_DIFF: ModifyRowVector serialization format
            # Layout: count(4) + sizes(8*N) + offsets(4*N) + padding(4*N) + old_values
            # The payload stores OLD (pre-modification) values.
            # The current on-page row has the NEW (post-modification) values.
            # (FindDiff args are reversed: newRec.FindDiff(oldRec) so eNew = old bytes)
            if payload_type == 2 and len(diff_bytes) >= 4:
                import struct
                count = struct.unpack_from('<I', bytes(diff_bytes), 0)[0]
                diff_entries = []
                pos = 4

                # Sizes: 2*count × UINT32 (interleaved old_size, new_size)
                for i in range(count):
                    if pos + 8 > len(diff_bytes):
                        break
                    old_sz = struct.unpack_from('<I', bytes(diff_bytes), pos)[0]; pos += 4
                    new_sz = struct.unpack_from('<I', bytes(diff_bytes), pos)[0]; pos += 4
                    diff_entries.append({'old_size': old_sz, 'new_size': new_sz})

                # Offsets: 2*count × UINT16 (interleaved old_offset, new_offset)
                for i in range(count):
                    if pos + 4 > len(diff_bytes):
                        break
                    old_off = struct.unpack_from('<H', bytes(diff_bytes), pos)[0]; pos += 2
                    new_off = struct.unpack_from('<H', bytes(diff_bytes), pos)[0]; pos += 2
                    diff_entries[i]['old_offset'] = old_off
                    diff_entries[i]['new_offset'] = new_off

                # Skip padding: 4 × count bytes (serialization overread)
                pos += 4 * count

                # Old (pre-modification) values from payload
                for i in range(count):
                    nb = diff_entries[i].get('new_size', 0)
                    if pos + nb <= len(diff_bytes):
                        diff_entries[i]['old_value'] = diff_bytes[pos:pos + nb]
                    pos += nb

                result['diff_info'] = {'count': count, 'entries': diff_entries}
                result['record_bytes'] = all_bytes  # current on-page row bytes

    return result


def classify_version(vi):
    """Classify a version tag as in-row or off-row PVS."""
    if not vi:
        return None
    slot_id = vi.get('pointer_slot', '0')
    try:
        slot_int = int(slot_id)
    except (ValueError, TypeError):
        return 'off-row'
    if slot_int == -4:
        return 'in-row'
    return 'off-row'


def _reconstruct_from_modify_diff(current_row, diff_payload):
    """Reconstruct the old (pre-modification) row by applying an INROW_MODIFY_DIFF.

    The diff_payload is a serialized ModifyRowVector:
      4 bytes: count (number of diff entries)
      8*count bytes: interleaved old/new sizes (UINT32 pairs)
      4*count bytes: interleaved old/new offsets (UINT16 pairs)
      4*count bytes: padding (overread from serialization bug — skip)
      Σ new_size[i] bytes: old (pre-modification) values concatenated

    We splice the old values back into the current row at the specified offsets.
    """
    import struct
    pos = 0
    count = struct.unpack_from('<I', bytes(diff_payload[pos:pos+4]))[0]
    pos += 4
    if count == 0 or count > 100:
        return None

    entries = []
    for i in range(count):
        old_sz = struct.unpack_from('<I', bytes(diff_payload[pos:pos+4]))[0]; pos += 4
        new_sz = struct.unpack_from('<I', bytes(diff_payload[pos:pos+4]))[0]; pos += 4
        entries.append({'old_size': old_sz, 'new_size': new_sz})

    for i in range(count):
        old_off = struct.unpack_from('<H', bytes(diff_payload[pos:pos+2]))[0]; pos += 2
        new_off = struct.unpack_from('<H', bytes(diff_payload[pos:pos+2]))[0]; pos += 2
        entries[i]['old_offset'] = old_off
        entries[i]['new_offset'] = new_off

    # Skip padding (4 * count bytes — serialization overread artifact)
    pos += 4 * count

    # Extract old values
    for i in range(count):
        nb = entries[i]['new_size']
        if pos + nb > len(diff_payload):
            return None
        entries[i]['old_value'] = list(diff_payload[pos:pos + nb])
        pos += nb

    # Reconstruct: start with a copy of the current row, splice old values back
    result = list(current_row)
    for e in entries:
        off = e['new_offset']
        old_val = e['old_value']
        for j, b in enumerate(old_val):
            if off + j < len(result):
                result[off + j] = b

    return result


def parse_version_ptr_from_record_bytes(record_bytes, force=False):
    """Parse the RecVersioningInfo from raw record bytes (list of ints).

    Same logic as parse_version_from_hex but operates on pre-parsed byte array
    rather than DBCC PAGE hex dump lines. Used to extract the version pointer
    embedded within PVS row_version column data (which is a full user row snapshot).

    When force=True, skip the StatusA 0x40 version-tag check. Use this when
    parsing rows extracted from PVS row_version column — the engine may clear
    the version tag when storing the row in PVS since PVS has its own chain
    metadata, but the VP bytes and in-row payload are still present.

    Returns dict with pointer info, or None if no version tag / null pointer.
    """
    if not record_bytes or len(record_bytes) < 4:
        return None

    status_byte = record_bytes[0]
    if not force and not (status_byte & 0x40):
        return None  # No version tag

    pminlen = int.from_bytes(bytes(record_bytes[2:4]), 'little')
    if pminlen >= len(record_bytes):
        return None

    col_count = int.from_bytes(bytes(record_bytes[pminlen:pminlen+2]), 'little')
    null_bitmap_bytes = (col_count + 7) // 8
    after_null = pminlen + 2 + null_bitmap_bytes

    if status_byte & 0x20 and after_null + 2 <= len(record_bytes):
        var_col_count = int.from_bytes(bytes(record_bytes[after_null:after_null+2]), 'little')
        if var_col_count > 0:
            last_offset_pos = after_null + 2 + (var_col_count - 1) * 2
            if last_offset_pos + 2 <= len(record_bytes):
                vp_offset = int.from_bytes(bytes(record_bytes[last_offset_pos:last_offset_pos+2]), 'little')
            else:
                vp_offset = len(record_bytes) - 14
        else:
            vp_offset = after_null + 2
    else:
        vp_offset = after_null

    if vp_offset + 14 > len(record_bytes):
        return None

    vp = record_bytes[vp_offset:vp_offset+14]

    # Null pointer check (all zeros in the 8-byte VersionRecPtr)
    if all(b == 0 for b in vp[0:8]):
        return None

    raw_page_id = int.from_bytes(bytes(vp[0:4]), 'little', signed=True)
    pvs = bool(raw_page_id & 0x80000000)
    page_id = raw_page_id & 0x7FFFFFFF
    file_id = int.from_bytes(bytes(vp[4:6]), 'little')
    slot_id_raw = int.from_bytes(bytes(vp[6:8]), 'little', signed=True)

    is_long_pvs = bool(slot_id_raw & 0x8000) if pvs else False
    slot_id = slot_id_raw & 0x07FF if is_long_pvs else slot_id_raw

    ts_low = int.from_bytes(bytes(vp[8:12]), 'little')
    ts_high = int.from_bytes(bytes(vp[12:14]), 'little')
    xdes_ts = (ts_high << 32) | ts_low

    dbcc_file_id = file_id if file_id > 0 else 1

    result = {
        'pointer_page': str(page_id),
        'pointer_file': str(file_id),
        'dbcc_file_id': str(dbcc_file_id),
        'pointer_slot': str(slot_id),
        'pointer_slot_raw': str(slot_id_raw),
        'pointer_pvs': pvs,
        'is_long_pvs': is_long_pvs,
        'XSN': str(xdes_ts),
        'is_inrow': (slot_id_raw == -4),
        'vp_offset': vp_offset,
    }

    if slot_id_raw == -4:
        nest_id = int.from_bytes(bytes(vp[0:4]), 'little')
        fileid_raw = file_id
        payload_type = fileid_raw & 0x1F
        payload_len = (fileid_raw >> 5) & 0x7FF
        type_names = {0: 'INROW_NULL', 1: 'INROW_FULLROW',
                      2: 'INROW_MODIFY_DIFF', 3: 'INROW_NEW_INSERT'}
        result['inrow_payload_type'] = type_names.get(payload_type, f'UNKNOWN({payload_type})')
        result['inrow_payload_type_raw'] = payload_type
        result['inrow_payload_len'] = payload_len

        # Extract payload bytes (immediately after the 14-byte version tag)
        payload_start = vp_offset + 14
        if payload_len > 0 and payload_start + payload_len <= len(record_bytes):
            result['inrow_payload_bytes'] = record_bytes[payload_start:payload_start + payload_len]

    return result


def format_page_output(rows, highlight_slot=None, cursor=None, database=None):
    """Format DBCC PAGE rows into ADR-focused HTML.
    
    Returns (html_string, version_info_dict_or_None).
    """
    html_parts = []
    slot_data = {}
    page_header = {}
    for row in rows:
        parent = str(row[0]) if row[0] else ""
        obj = str(row[1]) if row[1] else ""
        field = str(row[2]) if row[2] else ""
        value = str(row[3]) if row[3] else ""

        if "PAGE HEADER" in parent.upper() or "BUFFER" in parent.upper():
            if field:
                page_header[field] = value

        if "Slot " in parent:
            slot_match = re.search(r'Slot (\d+)', parent)
            if slot_match:
                slot_num = int(slot_match.group(1))
                if slot_num not in slot_data:
                    slot_data[slot_num] = {
                        "fields": {}, "version_info": None,
                        "hex_lines": [], "record_length": 0,
                        "status_byte": None,
                    }

                len_match = re.search(r'Length (\d+)', parent)
                if len_match:
                    slot_data[slot_num]["record_length"] = int(len_match.group(1))

                if not field and re.match(r'[0-9a-fA-F]{10,}:', value):
                    slot_data[slot_num]["hex_lines"].append(value)
                elif field:
                    slot_data[slot_num]["fields"][field] = value

    # Parse hex dumps for version tags
    for slot_num, sd in slot_data.items():
        if sd["hex_lines"]:
            first_line = sd["hex_lines"][0]
            after_colon = first_line.split(':', 1)
            if len(after_colon) >= 2:
                hex_str = re.split(r'  +', after_colon[1].strip(), maxsplit=1)[0].replace(' ', '')
                if len(hex_str) >= 2:
                    sd["status_byte"] = int(hex_str[0:2], 16)
            vi = parse_version_from_hex(sd["hex_lines"], sd["record_length"])
            if vi:
                sd["version_info"] = vi

    # Page header
    if page_header:
        html_parts.append('<div class="page-header-box">')
        html_parts.append('<h2>Page Header</h2>')
        for f in ['m_pageId', 'm_type', 'm_typeFlagBits', 'm_level', 'm_slotCnt',
                   'm_freeData', 'm_freeCnt', 'm_lsn', 'pminlen']:
            if f in page_header:
                html_parts.append(f'<span class="field"><span class="field-label">{f}</span><br>'
                                  f'<span class="field-value">{page_header[f]}</span></span>')
        html_parts.append('</div>')

    def render_slot(slot_num, sd):
        parts = []
        vi = sd["version_info"]
        vtype = classify_version(vi)
        rec_len = sd.get("record_length", 0)
        status_byte = sd.get("status_byte")

        if vtype == 'in-row':
            css_class = "slot-box has-inrow"
        elif vtype == 'off-row':
            css_class = "slot-box has-offrow"
        else:
            css_class = "slot-box"

        parts.append(f'<div class="{css_class}" id="slot{slot_num}">')

        # Header line
        parts.append(f'<div class="slot-header"><span class="slot-num">Slot {slot_num}</span>')
        for key in ['AccountId', 'Balance', 'AccountName']:
            if key in sd["fields"]:
                parts.append(f' {key}={sd["fields"][key]}')

        if status_byte is not None:
            has_vp = bool(status_byte & 0x40)
            if has_vp:
                if vtype == 'in-row':
                    payload_len = vi.get('inrow_payload_len', 0) if vi else 0
                    base = rec_len - 14 - payload_len if rec_len else '?'
                    parts.append(f' &nbsp;<span style="font-size:11px;color:#0e7c5a;font-weight:bold;">'
                                 f'Record: {rec_len} bytes ({base} data + 14 version tag + '
                                 f'{payload_len} diff payload) &middot; IN-ROW version</span>')
                else:
                    base = rec_len - 14 if rec_len else '?'
                    parts.append(f' &nbsp;<span style="font-size:11px;color:#8b5cf6;font-weight:bold;">'
                                 f'Record: {rec_len} bytes ({base} + 14 version tag) &middot; '
                                 f'OFF-ROW PVS pointer</span>')
            else:
                parts.append(f' &nbsp;<span style="font-size:11px;color:#78788c;">'
                             f'Record: {rec_len} bytes &middot; No version pointer</span>')
        parts.append('</div>')

        # Column fields
        hide_fields = {'Filler', 'KeyHashValue'}
        truncate_fields = {'ComplianceNotes': 80}
        parts.append('<div class="field-grid">')
        for fname, fval in sd["fields"].items():
            if fname in hide_fields:
                continue
            display_val = fval
            span_style = ''
            if fname in truncate_fields:
                span_style = ' style="grid-column:1/-1;"'
                if len(fval) > truncate_fields[fname]:
                    display_val = fval[:truncate_fields[fname]] + f'... <span style="font-size:10px;color:#999;">({len(fval)} chars)</span>'
            parts.append(f'<div class="field-item"{span_style}><div class="fname">{fname}</div>'
                         f'<div class="fval">{display_val}</div></div>')
        parts.append('</div>')

        # Version tag detail
        if vi:
            ptr_hex = vi.get('pointer_hex', '')
            ptr_page = vi.get('pointer_page', '')
            ptr_file = vi.get('pointer_file', '')
            ptr_slot = vi.get('pointer_slot', '')
            ptr_pvs = vi.get('pointer_pvs', False)
            xsn_hex = vi.get('xsn_hex', '')
            xsn_val = vi.get('XSN', '')

            if vtype == 'in-row':
                parts.append('<div class="version-inrow">')
                parts.append('<h3>IN-ROW Version Stub (slot = -4)</h3>')
                parts.append('<p style="font-size:13px;margin-bottom:8px;">'
                             'The before-image is stored directly on this data page as a diff record. '
                             'No separate PVS page needed — fast, but makes the row wider.</p>')
            else:
                parts.append('<div class="version-offrow">')
                parts.append('<h3>OFF-ROW PVS Record (slot = ' + str(ptr_slot) + ')</h3>')
                parts.append('<p style="font-size:13px;margin-bottom:8px;">'
                             'The before-image was too large for in-row storage. '
                             'ADR wrote it to a dedicated PVS page <b>in the user database</b> (not tempdb). '
                             'This row has a pointer to that PVS page.</p>')

            # Version tag table
            td = 'style="padding:4px 10px;border:1px solid #ddd;"'
            td_mono = 'style="padding:4px 10px;border:1px solid #ddd;font-family:monospace;font-size:12px;"'

            if vtype == 'in-row':
                th_bg = '#c8f0dc'
                th_border = '#0e7c5a'
            else:
                th_bg = '#e4d8f8'
                th_border = '#8b5cf6'
            th = f'style="text-align:left;padding:4px 10px;border:1px solid {th_border};background:{th_bg};"'

            parts.append('<table class="version-tag-table">')
            parts.append(f'<tr><th {th}>Offset</th><th {th}>Size</th>'
                         f'<th {th}>Field</th><th {th}>Raw</th><th {th}>Decoded</th></tr>')

            if vtype == 'in-row':
                # InRowVer layout: NestId(4) + PayloadType:5|PayloadLen:11(2) + SlotId=-4(2)
                nest_id = vi.get('inrow_nest_id', '?')
                payload_type = vi.get('inrow_payload_type', '?')
                payload_len = vi.get('inrow_payload_len', 0)
                parts.append(f'<tr><td {td}>0-3</td><td {td}>4 bytes</td>'
                             f'<td {td}>NestId (CTR)</td>'
                             f'<td class="mono" {td_mono}>{" ".join(ptr_hex.split()[:4])}</td>'
                             f'<td {td}>{nest_id}</td></tr>')
                parts.append(f'<tr><td {td}>4-5</td><td {td}>2 bytes</td>'
                             f'<td {td}>PayloadType + PayloadLen</td>'
                             f'<td class="mono" {td_mono}>{" ".join(ptr_hex.split()[4:6])}</td>'
                             f'<td {td}>Type={payload_type}, Len={payload_len} bytes</td></tr>')
                parts.append(f'<tr><td {td}>6-7</td><td {td}>2 bytes</td>'
                             f'<td {td}>SlotId (IS_INROW_DIFF)</td>'
                             f'<td class="mono" {td_mono}>{" ".join(ptr_hex.split()[6:8])}</td>'
                             f'<td {td}>-4 (0xFFFC)</td></tr>')
                parts.append(f'<tr style="background:#e6f7ef;"><td {td} colspan="5" '
                             f'style="padding:4px 10px;border:1px solid #ddd;font-weight:bold;color:#0e7c5a;">'
                             f'{payload_type} ({payload_len} bytes) stored IN-ROW on this data page '
                             f'-- no PVS I/O needed</td></tr>')
            else:
                # Off-row PVS pointer: PageId(4) + FileId(2) + SlotId(2)
                parts.append(f'<tr><td {td}>0-3</td><td {td}>4 bytes</td>'
                             f'<td {td}>PageId</td>'
                             f'<td class="mono" {td_mono}>{" ".join(ptr_hex.split()[:4])}</td>'
                             f'<td {td}>{ptr_page}'
                             f'{" (bit 31 = PVS)" if ptr_pvs else ""}</td></tr>')
                parts.append(f'<tr><td {td}>4-5</td><td {td}>2 bytes</td>'
                             f'<td {td}>FileId</td>'
                             f'<td class="mono" {td_mono}>{" ".join(ptr_hex.split()[4:6])}</td>'
                             f'<td {td}>{ptr_file}</td></tr>')
                parts.append(f'<tr><td {td}>6-7</td><td {td}>2 bytes</td>'
                             f'<td {td}>SlotId</td>'
                             f'<td class="mono" {td_mono}>{" ".join(ptr_hex.split()[6:8])}</td>'
                             f'<td {td}>{ptr_slot}</td></tr>')
                parts.append(f'<tr style="background:#f0e8ff;"><td {td} colspan="5" '
                             f'style="padding:4px 10px;border:1px solid #ddd;font-weight:bold;color:#8b5cf6;">'
                             f'Old value stored OFF-ROW at PVS file {ptr_file}, '
                             f'page {ptr_page}, slot {ptr_slot} (in user database)</td></tr>')

            parts.append(f'<tr style="background:#fff5e0;"><td {td}>8-11</td><td {td}>4 bytes</td>'
                         f'<td {td}>XdesTs m_low</td>'
                         f'<td class="mono" {td_mono}>{" ".join(xsn_hex.split()[:4])}</td>'
                         f'<td {td}></td></tr>')
            parts.append(f'<tr style="background:#fff5e0;"><td {td}>12-13</td><td {td}>2 bytes</td>'
                         f'<td {td}>XdesTs m_high</td>'
                         f'<td class="mono" {td_mono}>{" ".join(xsn_hex.split()[4:6])}</td>'
                         f'<td {td}></td></tr>')
            parts.append(f'<tr style="background:#fff0c0;"><td {td} colspan="5" '
                         f'style="padding:4px 10px;border:1px solid #ddd;font-weight:bold;">'
                         f'XdesTs (transaction timestamp): <b>{xsn_val}</b></td></tr>')
            parts.append('</table>')

            # Show in-row diff payload (the actual before-image)
            if vtype == 'in-row' and vi.get('diff_info'):
                diff_info = vi.get('diff_info', {})
                diff_hex = vi.get('diff_payload_hex', '')
                payload_len = vi.get('inrow_payload_len', 0)
                entries = diff_info.get('entries', [])

                parts.append('<div style="margin-top:12px;padding:14px 18px;'
                             'background:linear-gradient(135deg,#e8f5e9,#c8e6c9);'
                             'border:3px solid #2e7d32;border-radius:10px;'
                             'box-shadow:0 2px 8px rgba(46,125,50,0.2);'
                             'position:relative;">')
                parts.append('<div style="position:absolute;top:-14px;left:20px;'
                             'background:#2e7d32;color:white;padding:2px 12px;'
                             'border-radius:4px;font-size:11px;font-weight:bold;">'
                             'BEFORE-IMAGE (IN-ROW DIFF)</div>')
                parts.append(f'<h4 style="margin:4px 0 8px;color:#2e7d32;">'
                             f'{diff_info.get("count", 0)} diff region(s), '
                             f'{payload_len} bytes on this data page</h4>')

                # Reconstruct the old row:
                # Start with current on-page bytes (new values), then overlay
                # old_value bytes from the diff payload at the diff offset.
                record_bytes = vi.get('record_bytes', [])
                old_row = list(record_bytes)  # copy
                for entry in entries:
                    off = entry.get('new_offset', 0)
                    old_val = entry.get('old_value', [])
                    for j, b in enumerate(old_val):
                        if off + j < len(old_row):
                            old_row[off + j] = b

                # Decode columns from the reconstructed old row
                # Accounts schema:
                #   Record offset  8: Balance      DECIMAL(18,2) (9 bytes)
                #   Record offset 17: LastUpdated  DATETIME2(7)  (8 bytes)
                decoded_values = []
                if len(old_row) >= 25:
                    # Balance DECIMAL(18,2) @ offset 8, 9 bytes
                    dec_bytes = old_row[8:17]
                    sign = dec_bytes[0]
                    int_val = int.from_bytes(bytes(dec_bytes[1:9]), 'little')
                    decimal_val = int_val / 100.0
                    if sign == 0:
                        decimal_val = -decimal_val
                    decoded_values.append(('Balance', f'{decimal_val:,.2f}'))

                    # LastUpdated DATETIME2(7) @ offset 17, 8 bytes
                    dt_bytes = old_row[17:25]
                    time_val = int.from_bytes(bytes(dt_bytes[0:5]), 'little')
                    date_val = int.from_bytes(bytes(dt_bytes[5:8]), 'little')
                    try:
                        from datetime import datetime, timedelta
                        base = datetime(1, 1, 1)
                        dt = base + timedelta(days=date_val, microseconds=time_val / 10)
                        decoded_values.append(('LastUpdated',
                                               dt.strftime('%Y-%m-%d %H:%M:%S.%f')))
                    except (ValueError, OverflowError):
                        decoded_values.append(('LastUpdated',
                            f'(raw: {" ".join(f"{b:02X}" for b in dt_bytes)})'))

                if decoded_values:
                    parts.append('<div class="field-grid">')
                    for fname, fval in decoded_values:
                        parts.append(f'<div class="field-item" style="border-left:4px solid #2e7d32;min-width:auto;">'
                                     f'<div class="fname">{fname} <span style="font-size:10px;'
                                     f'color:#888;">(old value)</span></div>'
                                     f'<div class="fval" style="font-size:14px;font-weight:bold;'
                                     f'color:#2e7d32;white-space:nowrap;">{fval}</div></div>')
                    parts.append('</div>')
                else:
                    parts.append(f'<p style="font-size:12px;color:#777;margin:4px 0;">'
                                 f'Diff payload: <code>{diff_hex}</code></p>')

                parts.append('</div>')  # close before-image div

            # Chase the PVS pointer: read the version record from the PVS page
            if vtype == 'off-row' and cursor and database and ptr_page and ptr_page != '0':
                dbcc_fid = vi.get('dbcc_file_id', ptr_file)
                pvs_fields, pvs_error = read_pvs_record(cursor, database, dbcc_fid, ptr_page, ptr_slot)
                if pvs_fields:
                    parts.append('</div>')  # close version-offrow div
                    parts.append('</div>')  # close slot-box div
                    parts.append('<div style="margin:20px 0 0 0;padding:16px 20px;'
                                 'background:linear-gradient(135deg,#f8f0ff,#f0e8ff);'
                                 'border:3px solid #8b5cf6;border-radius:10px;'
                                 'box-shadow:0 2px 8px rgba(139,92,246,0.2);'
                                 'position:relative;">')
                    parts.append('<div style="position:absolute;top:-14px;left:20px;'
                                 'background:#8b5cf6;color:white;padding:2px 12px;'
                                 'border-radius:4px;font-size:11px;font-weight:bold;">'
                                 'BEFORE-IMAGE (OFF-ROW PVS PAGE)</div>')
                    parts.append(f'<h4 style="margin:4px 0 4px;color:#8b5cf6;">'
                                 f'&#x2197; PVS page: file {dbcc_fid}, '
                                 f'page {ptr_page}, slot {ptr_slot}</h4>')

                    # Check if we got decoded old values or PVS metadata
                    has_decoded = 'Balance' in pvs_fields or 'LastUpdated' in pvs_fields
                    if has_decoded:
                        parts.append('<p style="font-size:12px;color:#666;margin:0 0 10px;">'
                                     'ADR stored the full before-image row on a separate PVS page. '
                                     'Old column values decoded from the embedded row_version payload:</p>')
                        parts.append('<div class="field-grid">')
                        for fname in ('Balance', 'LastUpdated'):
                            if fname in pvs_fields:
                                parts.append(f'<div class="field-item" style="border-left:4px solid #8b5cf6;min-width:auto;">'
                                             f'<div class="fname">{fname} <span style="font-size:10px;'
                                             f'color:#888;">(old value)</span></div>'
                                             f'<div class="fval" style="font-size:14px;font-weight:bold;'
                                             f'color:#8b5cf6;white-space:nowrap;">{pvs_fields[fname]}</div></div>')
                        parts.append('</div>')
                    else:
                        parts.append('<p style="font-size:12px;color:#666;margin:0 0 10px;">'
                                     'The before-image is stored as a version record on this '
                                     'separate PVS page in the user database. PVS record metadata:</p>')
                        pvs_labels = {
                            'xdes_ts_push': 'Transaction Timestamp',
                            'xdes_ts_tran': 'Transaction Start Ts',
                            'min_len': 'Original Row Size (bytes)',
                            'seq_num': 'Sequence Number',
                            'prev_row_in_chain': 'Previous Version Ptr',
                            'sec_version_rid': 'Secondary Version RID',
                            'subid_push': 'SubId Push',
                            'subid_tran': 'SubId Tran',
                            'rowset_id': 'Rowset ID',
                        }
                        show_fields = ['min_len', 'xdes_ts_push', 'seq_num', 'prev_row_in_chain']
                        parts.append('<div class="field-grid">')
                        for fname in show_fields:
                            if fname in pvs_fields:
                                label = pvs_labels.get(fname, fname)
                                parts.append(f'<div class="field-item">'
                                             f'<div class="fname">{label}</div>'
                                             f'<div class="fval">{pvs_fields[fname]}</div></div>')
                        parts.append('</div>')
                    parts.append('</div>')
                    # Chase version chain via embedded version pointers in row data
                    # (NOT prev_row_in_chain which is a separate PVS cleanup mechanism)
                    embedded_vi = pvs_fields.get('_embedded_version_info')
                    chain_depth = 1
                    while embedded_vi and chain_depth < 5:
                        if embedded_vi.get('is_inrow') and embedded_vi.get('inrow_payload_type_raw') in (1, 2):
                            # INROW_FULLROW or INROW_MODIFY_DIFF: V0 is embedded within this PVS record
                            payload_type_name = embedded_vi.get('inrow_payload_type', 'IN-ROW')
                            chain_depth += 1
                            parts.append(f'<div style="margin:12px 0 0 0;padding:16px 20px;'
                                         f'background:linear-gradient(135deg,#faf5ff,#f3e8ff);'
                                         f'border:3px solid #d946ef;border-radius:10px;'
                                         f'box-shadow:0 2px 8px rgba(217,70,239,0.2);'
                                         f'position:relative;">')
                            parts.append(f'<div style="position:absolute;top:-14px;left:20px;'
                                         f'background:#d946ef;color:white;padding:2px 12px;'
                                         f'border-radius:4px;font-size:11px;font-weight:bold;">'
                                         f'VERSION CHAIN #{chain_depth} ({payload_type_name})</div>')
                            parts.append(f'<h4 style="margin:4px 0 4px;color:#d946ef;">'
                                         f'&#x21B3; version pointer &#x2192; in-row '
                                         f'(payload {embedded_vi.get("inrow_payload_len", "?")} bytes)</h4>')
                            parts.append('<p style="font-size:12px;color:#666;margin:0 0 10px;">'
                                         'Original row reconstructed from in-row version within the PVS record:</p>')
                            parts.append('<div class="field-grid">')
                            for fname, key in [('Balance', '_inrow_old_Balance'),
                                               ('LastUpdated', '_inrow_old_LastUpdated')]:
                                val = pvs_fields.get(key)
                                if val:
                                    parts.append(f'<div class="field-item" style="border-left:4px solid #d946ef;min-width:auto;">'
                                                 f'<div class="fname">{fname} <span style="font-size:10px;'
                                                 f'color:#888;">(original value)</span></div>'
                                                 f'<div class="fval" style="font-size:14px;font-weight:bold;'
                                                 f'color:#d946ef;white-space:nowrap;">{val}</div></div>')
                            parts.append('</div>')
                            parts.append('</div>')
                            break  # In-row payload terminates the chain

                        elif embedded_vi.get('pointer_pvs'):
                            # Off-row PVS pointer: chase to the next PVS record
                            chain_file_id = int(embedded_vi['dbcc_file_id'])
                            chain_page_id = int(embedded_vi['pointer_page'])
                            chain_slot_id = int(embedded_vi['pointer_slot'])

                            pvs2, pvs2_err = read_pvs_record(cursor, database,
                                                             chain_file_id, chain_page_id, chain_slot_id)
                            if not pvs2:
                                parts.append(f'<div style="margin:12px 0 0 0;padding:10px 15px;'
                                             f'background:#fff3cd;border:2px solid #ffc107;'
                                             f'border-radius:8px;font-size:12px;">'
                                             f'<b>Chain link #{chain_depth+1}:</b> '
                                             f'file {chain_file_id}, page {chain_page_id}, '
                                             f'slot {chain_slot_id} — {pvs2_err or "not found"}</div>')
                                break

                            chain_depth += 1
                            parts.append(f'<div style="margin:12px 0 0 0;padding:16px 20px;'
                                         f'background:linear-gradient(135deg,#fff0f5,#ffe8ef);'
                                         f'border:3px solid #d946ef;border-radius:10px;'
                                         f'box-shadow:0 2px 8px rgba(217,70,239,0.2);'
                                         f'position:relative;">')
                            parts.append(f'<div style="position:absolute;top:-14px;left:20px;'
                                         f'background:#d946ef;color:white;padding:2px 12px;'
                                         f'border-radius:4px;font-size:11px;font-weight:bold;">'
                                         f'VERSION CHAIN #{chain_depth} (OFF-ROW PVS)</div>')
                            parts.append(f'<h4 style="margin:4px 0 4px;color:#d946ef;">'
                                         f'&#x21B3; version pointer &#x2192; file {chain_file_id}, '
                                         f'page {chain_page_id}, slot {chain_slot_id}</h4>')

                            has_decoded2 = 'Balance' in pvs2 or 'LastUpdated' in pvs2
                            if has_decoded2:
                                parts.append('<p style="font-size:12px;color:#666;margin:0 0 10px;">'
                                             'Older version in the chain — decoded from embedded row:</p>')
                                parts.append('<div class="field-grid">')
                                for fname in ('Balance', 'LastUpdated'):
                                    if fname in pvs2:
                                        parts.append(f'<div class="field-item" style="border-left:4px solid #d946ef;min-width:auto;">'
                                                     f'<div class="fname">{fname} <span style="font-size:10px;'
                                                     f'color:#888;">(old value)</span></div>'
                                                     f'<div class="fval" style="font-size:14px;font-weight:bold;'
                                                     f'color:#d946ef;white-space:nowrap;">{pvs2[fname]}</div></div>')
                                parts.append('</div>')
                            else:
                                parts.append('<div class="field-grid">')
                                pvs_labels2 = {
                                    'xdes_ts_push': 'Transaction Timestamp',
                                    'min_len': 'Original Row Size',
                                    'seq_num': 'Sequence Number',
                                    'prev_row_in_chain': 'Previous Version Ptr',
                                }
                                for fname in ('min_len', 'xdes_ts_push', 'seq_num', 'prev_row_in_chain'):
                                    if fname in pvs2:
                                        parts.append(f'<div class="field-item">'
                                                     f'<div class="fname">{pvs_labels2.get(fname, fname)}</div>'
                                                     f'<div class="fval">{pvs2[fname]}</div></div>')
                                parts.append('</div>')
                            parts.append('</div>')

                            # Continue chain via next record's embedded pointer
                            pvs_fields = pvs2
                            embedded_vi = pvs2.get('_embedded_version_info')
                        else:
                            break  # Null or tempdb pointer

                    return '\n'.join(parts), vi
                else:
                    # PVS chase failed — show diagnostic
                    parts.append(f'<div style="margin-top:10px;padding:10px 15px;'
                                 f'background:#fff3cd;border:2px solid #ffc107;'
                                 f'border-radius:8px;font-size:12px;">')
                    parts.append(f'<b>PVS Chase Debug:</b> '
                                 f'Attempted DBCC PAGE(\'{database}\', {dbcc_fid}, '
                                 f'{ptr_page}, 3) for slot {ptr_slot}<br>')
                    parts.append(f'<span style="color:#856404;">{pvs_error or "Unknown error"}</span>')
                    parts.append('</div>')

            parts.append('</div>')  # close version-inrow or version-offrow

        else:
            parts.append('<div class="no-version">No version tag on this row</div>')

        parts.append('</div>')  # close slot-box
        return '\n'.join(parts), vi

    # Render slots
    result_vi = None
    if highlight_slot is not None and highlight_slot in slot_data:
        slot_html, result_vi = render_slot(highlight_slot, slot_data[highlight_slot])
        html_parts.append(slot_html)
    else:
        for slot_num in sorted(slot_data.keys()):
            slot_html, vi = render_slot(slot_num, slot_data[slot_num])
            html_parts.append(slot_html)
            if vi and not result_vi:
                result_vi = vi

    return '\n'.join(html_parts), result_vi


@app.route('/', methods=['GET', 'POST'])
def index():
    ctx = {
        'server': request.form.get('server', 'localhost'),
        'database': request.form.get('database', 'texasrangerswillwinitthisyear'),
        'auth': request.form.get('auth', 'trusted'),
        'table_name': request.form.get('table_name', 'Accounts'),
        'file_id': request.form.get('file_id', '1'),
        'page_id': request.form.get('page_id', ''),
        'find_row': request.form.get('find_row', '42'),
        'page_data': None,
        'error': None,
    }

    if request.method == 'POST':
        try:
            conn = get_connection(ctx['server'], ctx['database'], ctx['auth'])
            cursor = conn.cursor()
            highlight_slot = None

            if ctx['find_row']:
                fid, pid, sid = find_page_for_row(cursor, ctx['database'], ctx['find_row'], ctx['table_name'])
                if pid:
                    ctx['file_id'] = str(fid)
                    ctx['page_id'] = str(pid)
                    highlight_slot = sid
                else:
                    ctx['error'] = f"Could not find AccountId {ctx['find_row']} in dbo.{ctx['table_name']} on any data page."

            if ctx['page_id']:
                rows = run_dbcc_page(cursor, ctx['database'],
                                     int(ctx['file_id']), int(ctx['page_id']))

                html, vi = format_page_output(rows, highlight_slot, cursor, ctx['database'])

                ctx['page_data'] = html
            else:
                if not ctx['error']:
                    ctx['error'] = "Enter a Page ID or AccountId to find."

            conn.close()
        except Exception as e:
            ctx['error'] = str(e)

    return render_template_string(HTML_TEMPLATE, **ctx)


if __name__ == '__main__':
    print("ADR Page Viewer starting on http://localhost:5051")
    print("Press Ctrl+C to stop")
    app.run(host='0.0.0.0', port=5051, debug=True)
