"""
DBCC PAGE Viewer — Web app to display formatted DBCC PAGE output
with version tag highlighting.

Usage:
  python dbcc_page_viewer.py
  Open http://localhost:5050 in browser
  
Enter: server, database, file_id, page_id
Shows formatted page contents with version information highlighted.
"""
from flask import Flask, render_template_string, request
from mssql_python import connect as mssql_connect
import re

app = Flask(__name__)

HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>DBCC PAGE Viewer</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: 'Segoe UI', sans-serif; 
            background: #f5f5fa; 
            color: #1e1e28; 
            padding: 20px;
        }
        h1 { color: #005ab4; margin-bottom: 5px; font-size: 24px; }
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
        .form-group input:focus { outline: 2px solid #005ab4; border-color: transparent; }
        button {
            padding: 8px 20px; background: #005ab4; color: white; border: none;
            border-radius: 6px; font-size: 14px; cursor: pointer;
        }
        button:hover { background: #004090; }
        
        .results { margin-top: 20px; }
        
        .page-header-box {
            background: #e8e8f0; border: 2px solid #005ab4; border-radius: 10px;
            padding: 15px; margin-bottom: 15px;
        }
        .page-header-box h2 { color: #005ab4; font-size: 16px; margin-bottom: 10px; }
        .page-header-box .field { display: inline-block; margin-right: 20px; margin-bottom: 5px; }
        .page-header-box .field-label { font-size: 11px; color: #78788c; }
        .page-header-box .field-value { font-size: 14px; font-weight: bold; }
        
        .slot-box {
            background: white; border: 2px solid #ddd; border-radius: 10px;
            padding: 15px; margin-bottom: 12px; transition: all 0.2s;
        }
        .slot-box:hover { border-color: #005ab4; box-shadow: 0 2px 8px rgba(0,90,180,0.1); }
        .slot-box.has-version { border-color: #c87800; border-width: 3px; }
        .slot-header { 
            font-size: 14px; font-weight: bold; color: #005ab4; 
            margin-bottom: 8px; 
        }
        .slot-header .slot-num { 
            background: #005ab4; color: white; padding: 2px 8px; 
            border-radius: 4px; font-size: 12px; margin-right: 8px;
        }
        
        .field-grid { 
            display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); 
            gap: 8px; margin-bottom: 10px;
        }
        .field-item {
            background: #f0f0f5; padding: 6px 10px; border-radius: 6px;
            overflow: hidden; min-width: 0;
        }
        .field-item .fname { font-size: 11px; color: #78788c; }
        .field-item .fval { font-size: 13px; font-weight: 500; overflow-wrap: break-word; word-break: break-all; }
        
        .version-info {
            background: #fff5e0; border: 2px solid #c87800; border-radius: 8px;
            padding: 10px 15px; margin-top: 10px;
        }
        .version-info h3 { color: #c87800; font-size: 13px; margin-bottom: 6px; }
        .version-info .vfield { display: inline-block; margin-right: 20px; }
        .version-info .vfield .fname { font-size: 11px; color: #c87800; }
        .version-info .vfield .fval { font-size: 14px; font-weight: bold; color: #1e1e28; }
        .version-info .xsn-match { 
            font-size: 16px; font-weight: bold; color: #c87800; 
            background: #fff0c0; padding: 2px 8px; border-radius: 4px;
            border: 2px solid #c87800;
        }
        
        .xsn-callout {
            background: linear-gradient(135deg, #fff5e0, #f0eefa);
            border: 2px dashed #c87800; border-radius: 10px;
            padding: 12px 20px; margin: 15px 0; text-align: center;
            font-size: 16px; color: #c87800; font-weight: bold;
        }
        .xsn-callout .arrow { font-size: 24px; margin: 0 10px; }
        
        .no-version {
            background: #f0f5f0; border: 1px solid #10780e; border-radius: 8px;
            padding: 8px 15px; margin-top: 10px; color: #10780e; font-size: 12px;
        }
        
        .error { color: #c82828; background: #fde; padding: 15px; border-radius: 10px; }
        
        .version-store-box {
            background: #f0eefa; border: 2px solid #643cc8; border-radius: 10px;
            padding: 15px; margin-top: 20px;
        }
        .version-store-box h2 { color: #643cc8; font-size: 16px; margin-bottom: 10px; }
        .vs-record {
            background: white; border: 1px solid #643cc8; border-radius: 8px;
            padding: 10px; margin-bottom: 8px;
        }
        .vs-record .field { display: inline-block; margin-right: 15px; }
        .vs-record .xsn-match {
            font-size: 13px; font-weight: bold; color: #c87800;
        }
        
    </style>
</head>
<body>
    <h1>DBCC PAGE Viewer</h1>
    <div class="subtitle">Formatted page contents with version tag highlighting</div>
    
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
    return mssql_connect(";".join(parts))

def find_page_for_row(cursor, database, table_filter):
    """Find the page for a specific AccountId using only DBCC PAGE — no SELECT on the user table."""
    # Get data pages from system metadata — no locks on user table
    cursor.execute("""
        SELECT allocated_page_file_id, allocated_page_page_id
        FROM sys.dm_db_database_page_allocations(DB_ID(), OBJECT_ID('dbo.Accounts'), NULL, NULL, 'DETAILED')
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
            if field == "AccountId" and value == str(int(table_filter)):
                slot_match = re.search(r'Slot (\d+)', parent)
                if slot_match:
                    sid = int(slot_match.group(1))
                    bal = None
                    for r2 in rows:
                        p2 = str(r2[0]) if r2[0] else ""
                        if f"Slot {sid}" in p2 and str(r2[2]) == "Balance":
                            bal = r2[3]
                            break
                    return fid, pid, sid, int(table_filter), bal
    return None, None, None, None, None

def run_dbcc_page(cursor, database, file_id, page_id):
    """Run DBCC PAGE WITH TABLERESULTS and return rows."""
    cursor.execute("DBCC TRACEON(3604)")
    cursor.execute(f"DBCC PAGE(N'{database}', {file_id}, {page_id}, 3) WITH TABLERESULTS")
    rows = cursor.fetchall()
    columns = [desc[0] for desc in cursor.description]
    return columns, rows

def get_version_store(cursor, database):
    """Get version store records for this database."""
    cursor.execute(f"""
        SELECT 
            transaction_sequence_num AS XSN,
            version_sequence_num AS SeqInChain,
            record_length_first_part_in_bytes AS RecordBytes,
            status,
            record_image_first_part
        FROM sys.dm_tran_version_store
        WHERE database_id = DB_ID(N'{database}')
        ORDER BY transaction_sequence_num DESC
    """)
    rows = cursor.fetchall()
    columns = [desc[0] for desc in cursor.description]
    return columns, rows


def decode_version_record(image_bytes):
    """Decode a version store record_image_first_part.
    
    The binary is the raw row record — same format as on a data page.
    We decode the status byte, column data, and the 14-byte version tag.
    Returns a dict with status_byte, has_version_tag, column values, and version tag fields.
    """
    if not image_bytes or len(image_bytes) < 4:
        return None
    
    # Handle bytes or memoryview
    if isinstance(image_bytes, memoryview):
        image_bytes = bytes(image_bytes)
    # Strip leading 0x if it's a hex string
    if isinstance(image_bytes, str):
        hex_str = image_bytes.lstrip('0x')
        image_bytes = bytes.fromhex(hex_str)
    
    result = {}
    result['status_byte'] = image_bytes[0]
    result['has_version_tag'] = bool(image_bytes[0] & 0x40)
    result['record_length'] = len(image_bytes)
    
    # Decode column data from the row image.
    # Accounts table physical layout (fixed region = 125 bytes):
    #   [0]    StatusA (1)
    #   [1]    StatusB (1)
    #   [2-3]  Fixed-length offset (2) = 125
    #   [4-7]  AccountId int (4)
    #   [8-16] Balance decimal(18,2) (9)
    #   [17-24] LastUpdated datetime2(7) (8)
    #   [25-124] Filler char(100) (100)
    # Variable region after offset 125:
    #   NullBitmap(3) + VarColCount(2) + VarOffsets(4) + AccountName(nvarchar) + Status(nvarchar)
    columns = {}
    try:
        if len(image_bytes) >= 125:
            # AccountId — int, 4 bytes LE at offset 4
            columns['AccountId'] = int.from_bytes(image_bytes[4:8], 'little', signed=True)
            
            # Balance — decimal(18,2), 9 bytes at offset 8
            # SQL Server decimal: byte 0 = sign (1=positive, 0=negative)
            # bytes 1-8 = integer value in LE; divide by 10^scale
            sign = image_bytes[8]
            int_val = int.from_bytes(image_bytes[9:17], 'little')
            dec_val = int_val / 100  # scale=2
            columns['Balance'] = dec_val if sign else -dec_val
            
            # Variable-length columns: AccountName, Status
            # After fixed data at offset 125:
            #   [125-126] null bitmap col count (2 bytes)
            #   [127]     null bitmap bits (1 byte for 6 cols)
            #   [128-129] var col count (2 bytes)
            #   [130-131] end offset of var col 1 (AccountName)
            #   [132-133] end offset of var col 2 (Status)
            #   then the var data bytes
            if len(image_bytes) >= 134:
                has_var = bool(image_bytes[0] & 0x20)  # StatusA bit 5 = has variable columns
                if has_var:
                    var_count = int.from_bytes(image_bytes[128:130], 'little')
                    var_offsets = []
                    for i in range(var_count):
                        off = int.from_bytes(image_bytes[130 + i*2 : 132 + i*2], 'little')
                        var_offsets.append(off)
                    
                    # var data starts after the offset array
                    var_data_start = 130 + var_count * 2
                    
                    if var_count >= 1 and var_offsets[0] <= len(image_bytes):
                        name_end = var_offsets[0]
                        name_bytes = image_bytes[var_data_start:name_end]
                        columns['AccountName'] = name_bytes.decode('utf-16-le', errors='replace')
                    
                    if var_count >= 2 and var_offsets[1] <= len(image_bytes):
                        name_end = var_offsets[0]
                        status_end = var_offsets[1]
                        status_bytes = image_bytes[name_end:status_end]
                        columns['Status'] = status_bytes.decode('utf-16-le', errors='replace')
    except Exception:
        pass  # If decode fails, we still have the version tag info
    
    result['columns'] = columns
    
    # Version tag (last 14 bytes if bit 6 set)
    if result['has_version_tag'] and len(image_bytes) >= 14:
        vp = image_bytes[-14:]
        # VersionRecPtr (8 bytes)
        raw_page_id = int.from_bytes(vp[0:4], 'little')
        pvs = bool(raw_page_id & 0x80000000)
        page_id = raw_page_id & 0x7FFFFFFF
        file_id = int.from_bytes(vp[4:6], 'little')
        slot_id = int.from_bytes(vp[6:8], 'little', signed=True)
        # XdesTs (6 bytes)
        ts_low = int.from_bytes(vp[8:12], 'little')
        ts_high = int.from_bytes(vp[12:14], 'little')
        xdes_ts = (ts_high << 32) | ts_low
        
        result['pointer_page'] = page_id
        result['pointer_file'] = file_id
        result['pointer_slot'] = slot_id
        result['pointer_pvs'] = pvs
        result['xdes_ts'] = xdes_ts
        result['pointer_hex'] = ' '.join(f'{b:02X}' for b in vp[0:8])
        result['xdes_hex'] = ' '.join(f'{b:02X}' for b in vp[8:14])
    
    return result

def parse_version_from_hex(hex_lines, record_length):
    """Detect version tag by parsing the DBCC PAGE hex dump.

    Record status byte (byte 0) bit 6 (0x40) = 'has version pointer'.
    When set, the last 14 bytes of the record are the version pointer:
      bytes 0-7  : version store pointer (internal tempdb location)
      bytes 8-13 : Transaction Sequence Number (XSN) — links to
                   sys.dm_tran_version_store.transaction_sequence_num
    Returns a dict of version fields for display, or None if no version tag.
    """
    all_bytes = []
    for line in hex_lines:
        # Each line: "0000000000000000:   70007d00 2a000000 ...  p.}.*..."
        after_colon = line.split(':', 1)
        if len(after_colon) < 2:
            continue
        # Split hex groups from ASCII portion (separated by 2+ spaces)
        parts = re.split(r'  +', after_colon[1].strip(), maxsplit=1)
        hex_str = parts[0].replace(' ', '')
        for i in range(0, len(hex_str), 2):
            try:
                all_bytes.append(int(hex_str[i:i+2], 16))
            except ValueError:
                break

    # Truncate to actual record length (hex dump may pad)
    if record_length and len(all_bytes) > record_length:
        all_bytes = all_bytes[:record_length]

    if not all_bytes:
        return None

    status_byte = all_bytes[0]
    if not (status_byte & 0x40):
        return None

    result = {}
    result['Record Status'] = f'0x{status_byte:02X} (bit 6 set — version pointer present)'

    if len(all_bytes) >= 14:
        vp = all_bytes[-14:]
        # Bytes 0-3: ShPageId (ULONG) — bit 31 is PVS flag
        raw_page_id = int.from_bytes(bytes(vp[0:4]), 'little')
        pvs = bool(raw_page_id & 0x80000000)
        page_id = raw_page_id & 0x7FFFFFFF
        # Bytes 4-5: FileId (UINT16)
        file_id = int.from_bytes(bytes(vp[4:6]), 'little')
        # Bytes 6-7: SlotId16 (INT16) — special values: 0=NULL, -4=InRowDiff
        slot_id = int.from_bytes(bytes(vp[6:8]), 'little', signed=True)
        result['pointer_page'] = str(page_id)
        result['pointer_file'] = str(file_id)
        result['pointer_slot'] = str(slot_id)
        result['pointer_pvs'] = pvs
        result['pointer_hex'] = ' '.join(f'{b:02X}' for b in vp[0:8])
        # Bytes 8-13: XdesTs — m_low (UINT32) then m_high (UINT16)
        ts_low = int.from_bytes(bytes(vp[8:12]), 'little')
        ts_high = int.from_bytes(bytes(vp[12:14]), 'little')
        xdes_ts = (ts_high << 32) | ts_low
        result['XSN'] = str(xdes_ts)
        result['xsn_hex'] = ' '.join(f'{b:02X}' for b in vp[8:14])

    return result


def format_page_output(columns, rows, highlight_slot=None):
    """Format DBCC PAGE output into structured HTML.
    
    When highlight_slot is set (i.e. the user searched by AccountId), only
    the target slot is rendered so the audience sees one clean row instead
    of dozens of slots.  The full page is still available under a
    collapsible "Show all slots" section plus the raw output toggle.
    
    Returns (html_string, row_xsn) where row_xsn is the decoded XSN from
    the highlighted slot's version pointer (or None).
    """
    html_parts = []
    current_section = ""
    slot_data = {}
    page_header = {}
    raw_lines = []
    row_xsn = None
    
    for row in rows:
        parent = str(row[0]) if row[0] else ""
        obj = str(row[1]) if row[1] else ""
        field = str(row[2]) if row[2] else ""
        value = str(row[3]) if row[3] else ""
        
        raw_lines.append(f"{parent} | {obj} | {field} | {value}")
        
        if "PAGE HEADER" in parent.upper() or "BUFFER" in parent.upper():
            if field:
                page_header[field] = value
        
        if "Slot " in parent:
            slot_match = re.search(r'Slot (\d+)', parent)
            if slot_match:
                slot_num = int(slot_match.group(1))
                if slot_num not in slot_data:
                    slot_data[slot_num] = {"fields": {}, "version_info": {}, "raw": [],
                                           "hex_lines": [], "record_length": 0,
                                           "status_byte": None}
                
                # Extract record length from ParentObject
                len_match = re.search(r'Length (\d+)', parent)
                if len_match:
                    slot_data[slot_num]["record_length"] = int(len_match.group(1))
                
                # Identify hex dump lines (empty field name, value starts with hex offset)
                if not field and re.match(r'[0-9a-fA-F]{10,}:', value):
                    slot_data[slot_num]["hex_lines"].append(value)
                elif "version" in field.lower() or "xsn" in field.lower() or "timestamp" in field.lower():
                    slot_data[slot_num]["version_info"][field] = value
                elif field:
                    slot_data[slot_num]["fields"][field] = value
                slot_data[slot_num]["raw"].append(f"{field} = {value}")
    
    # Parse hex dumps: extract status byte and detect version tags
    for slot_num, sd in slot_data.items():
        if sd["hex_lines"]:
            # Extract status byte from first hex line
            first_line = sd["hex_lines"][0]
            after_colon = first_line.split(':', 1)
            if len(after_colon) >= 2:
                hex_str = re.split(r'  +', after_colon[1].strip(), maxsplit=1)[0].replace(' ', '')
                if len(hex_str) >= 2:
                    sd["status_byte"] = int(hex_str[0:2], 16)
            if not sd["version_info"]:
                vi = parse_version_from_hex(sd["hex_lines"], sd["record_length"])
                if vi:
                    sd["version_info"] = vi
    
    # Page header
    if page_header:
        html_parts.append('<div class="page-header-box">')
        html_parts.append('<h2>📄 Page Header</h2>')
        important_fields = ['m_pageId', 'm_type', 'm_typeFlagBits', 'm_level', 'm_slotCnt', 
                           'm_freeData', 'm_freeCnt', 'm_lsn', 'pminlen']
        for f in important_fields:
            if f in page_header:
                html_parts.append(f'<span class="field"><span class="field-label">{f}</span><br>'
                                f'<span class="field-value">{page_header[f]}</span></span>')
        html_parts.append('</div>')

    def render_slot(slot_num, sd, force_highlight=False):
        """Return HTML for a single slot box."""
        parts = []
        has_version = bool(sd["version_info"])
        css_class = "slot-box"
        if has_version or force_highlight:
            css_class += " has-version"

        parts.append(f'<div class="{css_class}" id="slot{slot_num}">')
        parts.append(f'<div class="slot-header"><span class="slot-num">Slot {slot_num}</span>')

        for key in ['AccountId', 'Balance', 'AccountName']:
            if key in sd["fields"]:
                parts.append(f' {key}={sd["fields"][key]}')

        # Show record status byte and length next to slot ID
        rec_len = sd.get("record_length", 0)
        status_byte = sd.get("status_byte")
        if status_byte is not None:
            has_vp = bool(status_byte & 0x40)
            status_desc = f'0x{status_byte:02X}'
            if has_vp:
                base = rec_len - 14 if rec_len else '?'
                parts.append(f' &nbsp;<span style="font-size:11px;color:#c87800;font-weight:bold;">'
                            f'Record: {rec_len} bytes ({base} + 14 version tag) &middot; '
                            f'Status: {status_desc} (bit 6 = version pointer)</span>')
            else:
                parts.append(f' &nbsp;<span style="font-size:11px;color:#78788c;font-weight:normal;">'
                            f'Record: {rec_len} bytes &middot; Status: {status_desc} (no version pointer)</span>')
        parts.append('</div>')

        # Hide internal engine fields that add noise for the audience
        hide_fields = {'Filler', 'KeyHashValue'}
        parts.append('<div class="field-grid">')
        for fname, fval in sd["fields"].items():
            if fname in hide_fields:
                continue
            parts.append(f'<div class="field-item"><div class="fname">{fname}</div>'
                        f'<div class="fval">{fval}</div></div>')
        parts.append('</div>')

        if has_version:
            vi = sd["version_info"]
            parts.append('<div class="version-info">')
            parts.append('<h3>🔗 14-Byte Version Tag (RecVersioningInfo)</h3>')
            ptr_hex = vi.get('pointer_hex', '')
            ptr_page = vi.get('pointer_page', '')
            ptr_file = vi.get('pointer_file', '')
            ptr_slot = vi.get('pointer_slot', '')
            ptr_pvs = vi.get('pointer_pvs', False)
            xsn_hex = vi.get('xsn_hex', '')
            xsn_val = vi.get('XSN', '')
            store_name = 'PVS' if ptr_pvs else 'tempdb'
            td = 'style="padding:4px 10px;border:1px solid #ddd;"'
            td_mono = 'style="padding:4px 10px;border:1px solid #ddd;font-family:monospace;font-size:12px;"'
            th = 'style="text-align:left;padding:4px 10px;border:1px solid #c87800;"'
            parts.append('<table style="border-collapse:collapse;width:100%;font-size:13px;margin-bottom:8px;">')
            parts.append(f'<tr style="background:#f5e6c0;"><th {th}>Offset</th>'
                        f'<th {th}>Size</th><th {th}>Field</th>'
                        f'<th {th}>Raw</th><th {th}>Decoded</th></tr>')
            parts.append(f'<tr><td {td}>0–3</td><td {td}>4 bytes</td>'
                        f'<td {td}>PageId (m_id)</td>'
                        f'<td {td_mono}>{" ".join(ptr_hex.split()[:4])}</td>'
                        f'<td {td}>{ptr_page}{" (PVS bit set)" if ptr_pvs else ""}</td></tr>')
            parts.append(f'<tr><td {td}>4–5</td><td {td}>2 bytes</td>'
                        f'<td {td}>FileId (m_file)</td>'
                        f'<td {td_mono}>{" ".join(ptr_hex.split()[4:6])}</td>'
                        f'<td {td}>{ptr_file}</td></tr>')
            parts.append(f'<tr><td {td}>6–7</td><td {td}>2 bytes</td>'
                        f'<td {td}>SlotId (rid_slot)</td>'
                        f'<td {td_mono}>{" ".join(ptr_hex.split()[6:8])}</td>'
                        f'<td {td}>{ptr_slot}</td></tr>')
            parts.append(f'<tr style="background:#eef;"><td {td} colspan="5" style="padding:4px 10px;border:1px solid #ddd;font-weight:bold;">'
                        f'→ Version chain pointer: {store_name} file {ptr_file}, page {ptr_page}, slot {ptr_slot}</td></tr>')
            parts.append(f'<tr style="background:#fff5e0;"><td {td}>8–11</td><td {td}>4 bytes</td>'
                        f'<td {td}>XdesTs m_low</td>'
                        f'<td {td_mono}>{" ".join(xsn_hex.split()[:4])}</td>'
                        f'<td {td}></td></tr>')
            parts.append(f'<tr style="background:#fff5e0;"><td {td}>12–13</td><td {td}>2 bytes</td>'
                        f'<td {td}>XdesTs m_high</td>'
                        f'<td {td_mono}>{" ".join(xsn_hex.split()[4:6])}</td>'
                        f'<td {td}></td></tr>')
            parts.append(f'<tr style="background:#fff0c0;"><td {td} colspan="5" style="padding:4px 10px;border:1px solid #ddd;font-weight:bold;">'
                        f'→ XdesTs (transaction timestamp): '
                        f'<span class="xsn-match" data-xsn="{xsn_val}">{xsn_val}</span>'
                        f' = (m_high &lt;&lt; 32) | m_low</td></tr>')
            parts.append('</table>')
            parts.append('</div>')
        else:
            parts.append('<div class="no-version">✅ No version tag on this row</div>')

        parts.append('</div>')
        return '\n'.join(parts)

    # When a specific slot was searched, show only that slot.
    if highlight_slot is not None and highlight_slot in slot_data:
        html_parts.append(render_slot(highlight_slot, slot_data[highlight_slot], force_highlight=True))
    else:
        # No specific slot targeted — show everything
        for slot_num in sorted(slot_data.keys()):
            html_parts.append(render_slot(slot_num, slot_data[slot_num]))
    
    # Extract XSN from highlighted slot for the callout
    if highlight_slot is not None and highlight_slot in slot_data:
        vi = slot_data[highlight_slot].get("version_info", {})
        if 'XSN' in vi:
            row_xsn = vi['XSN']
    
    return '\n'.join(html_parts), row_xsn

@app.route('/', methods=['GET', 'POST'])
def index():
    ctx = {
        'server': request.form.get('server', 'localhost'),
        'database': request.form.get('database', 'texasrangerswillwinitthisyear'),
        'auth': request.form.get('auth', 'trusted'),
        'file_id': request.form.get('file_id', '1'),
        'page_id': request.form.get('page_id', ''),
        'find_row': request.form.get('find_row', ''),
        'page_data': None,
        'error': None,
    }
    
    if request.method == 'POST':
        try:
            conn = get_connection(ctx['server'], ctx['database'], ctx['auth'])
            cursor = conn.cursor()
            
            highlight_slot = None
            
            # If find_row is specified, look up the page
            if ctx['find_row']:
                fid, pid, sid, aid, bal = find_page_for_row(cursor, ctx['database'], ctx['find_row'])
                if pid:
                    ctx['file_id'] = str(fid)
                    ctx['page_id'] = str(pid)
                    highlight_slot = sid
                else:
                    ctx['error'] = f"Could not find AccountId {ctx['find_row']} on any data page."
            
            if ctx['page_id']:
                # Get DBCC PAGE results
                columns, rows = run_dbcc_page(cursor, ctx['database'], 
                                              int(ctx['file_id']), int(ctx['page_id']))
                
                html, row_xsn = format_page_output(columns, rows, highlight_slot)
                
                # Get version store
                vs_cols, vs_rows = get_version_store(cursor, ctx['database'])
                if vs_rows:
                    # Bridge arrow from row's version tag XSN to the version store chain
                    if row_xsn:
                        first_xsn = str(vs_rows[0][0])
                        html += '<div class="xsn-callout">'
                        html += f'Row XSN <b>{row_xsn}</b> <span class="arrow">⟶</span> '
                        html += f'version pointer leads to tempdb <span class="arrow">⟶</span> '
                        html += f'chain starts at XSN <b>{first_xsn}</b>'
                        html += '</div>'
                        html += '<div style="text-align:center;font-size:28px;color:#c87800;margin:-8px 0 -4px 0;">⬇</div>'
                    html += '<div class="version-store-box">'
                    html += '<h2>🗄️ tempdb Version Store — Version Chain</h2>'
                    
                    for idx, vr in enumerate(vs_rows):
                        xsn = str(vr[0])       # XSN
                        seq = str(vr[1])        # SeqInChain
                        rec_len = vr[2]         # RecordBytes
                        status = vr[3]          # status (0=single, 1=split)
                        image = vr[4]           # record_image_first_part (bytes)
                        
                        decoded = decode_version_record(image) if image else None
                        
                        html += '<div class="vs-record">'
                        
                        # Header line: XSN and record size
                        html += f'<div style="font-weight:bold;font-size:14px;margin-bottom:6px;">'
                        html += f'XSN {xsn}'
                        html += f' <span style="font-size:12px;font-weight:normal;color:#78788c;">({rec_len} bytes, seq {seq})</span>'
                        html += f'</div>'
                        
                        if decoded:
                            sb = decoded['status_byte']
                            has_vt = decoded['has_version_tag']
                            cols = decoded.get('columns', {})
                            
                            # Row data values
                            if cols:
                                html += '<div style="background:#e8f4e8;border:1px solid #10780e;border-radius:6px;padding:8px;margin:4px 0;font-size:13px;">'
                                parts = []
                                if 'AccountId' in cols:
                                    parts.append(f'<b>AccountId</b> = {cols["AccountId"]}')
                                if 'Balance' in cols:
                                    parts.append(f'<b>Balance</b> = {cols["Balance"]:,.2f}')
                                if 'AccountName' in cols:
                                    parts.append(f'<b>AccountName</b> = {cols["AccountName"]}')
                                if 'Status' in cols:
                                    parts.append(f'<b>Status</b> = {cols["Status"]}')
                                html += ' &nbsp;|&nbsp; '.join(parts)
                                html += '</div>'
                            
                            # Status byte
                            if has_vt:
                                html += f'<div style="font-size:12px;color:#c87800;font-weight:bold;margin-bottom:4px;">'
                                html += f'Record Status: 0x{sb:02X} (bit 6 set — has version pointer)'
                                html += f'</div>'
                            else:
                                html += f'<div style="font-size:12px;color:#10780e;font-weight:bold;margin-bottom:4px;">'
                                html += f'Record Status: 0x{sb:02X} (no version pointer — end of chain)'
                                html += f'</div>'
                            
                            # Version tag decode if present
                            if has_vt:
                                store = 'PVS' if decoded.get('pointer_pvs') else 'tempdb'
                                html += '<div style="background:#fff5e0;border:1px solid #c87800;border-radius:6px;padding:8px;margin:4px 0;font-size:12px;">'
                                html += f'<b>Version Pointer:</b> {store} file {decoded["pointer_file"]}, page {decoded["pointer_page"]}, slot {decoded["pointer_slot"]}'
                                html += f' &nbsp;|&nbsp; <b>XdesTs:</b> {decoded["xdes_ts"]}'
                                html += f' <span style="color:#78788c;">({decoded["xdes_hex"]})</span>'
                                html += f'</div>'
                        
                        html += '</div>'
                        
                        # Chain arrow between records
                        if idx < len(vs_rows) - 1:
                            next_xsn = str(vs_rows[idx + 1][0])
                            html += '<div style="text-align:center;font-size:24px;color:#643cc8;margin:4px 0;">'
                            html += f'⬇ <span style="font-size:12px;">version pointer → XSN {next_xsn}</span>'
                            html += '</div>'
                    
                    # End of chain marker
                    last_decoded = decode_version_record(vs_rows[-1][4]) if vs_rows[-1][4] else None
                    if last_decoded and not last_decoded['has_version_tag']:
                        html += '<div style="text-align:center;font-size:13px;color:#10780e;font-weight:bold;margin-top:4px;">— End of Version Chain —</div>'
                    
                    html += '</div>'
                else:
                    # No version store records — show ghost pointer message if row has a version tag
                    if row_xsn:
                        html += '<div class="xsn-callout" style="border-color:#999;color:#666;background:linear-gradient(135deg,#f5f5f5,#eee);">'
                        html += f'Row has version tag (XSN {row_xsn}) but tempdb version store is <b>empty</b> — '
                        html += 'stale pointer, cleaner already removed the versions. '
                        html += 'Next reader\'s XSN will be ≥ row XSN → current row is correct, pointer ignored.'
                        html += '</div>'
                
                ctx['page_data'] = html
            else:
                if not ctx['error']:
                    ctx['error'] = "Enter a Page ID or AccountId to find."
                
            conn.close()
        except Exception as e:
            ctx['error'] = str(e)
    
    return render_template_string(HTML_TEMPLATE, **ctx)

if __name__ == '__main__':
    print("DBCC PAGE Viewer starting on http://localhost:5050")
    print("Press Ctrl+C to stop")
    app.run(host='0.0.0.0', port=5050, debug=True)
