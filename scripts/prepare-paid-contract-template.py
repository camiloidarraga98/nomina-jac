"""Prepare the paid-in-full variant from the approved, sanitized JAC master.
Maintenance only: python scripts/prepare-paid-contract-template.py
Remove actual text operators, preserving the artwork and all other clauses.
"""
import base64
import io
import json
from pathlib import Path
from pypdf import PdfReader, PdfWriter
from pypdf.generic import ContentStream

path = Path('lib/contract-template.json')
data = json.loads(path.read_text())
assert data['sourceSha256'] == '0f31bc77d634919e7b6377cc13a5b6b9e7701a3205e3e6a471e9f68e56770e31'
reader = PdfReader(io.BytesIO(base64.b64decode(data['template'])))
assert len(reader.pages) == 4
writer = PdfWriter()
for index, source in enumerate(reader.pages):
    page = writer.add_page(source)
    if index != 0:
        continue
    stream = ContentStream(page.get_contents(), writer)
    operations = stream.operations
    headings = [i for i, (args, op) in enumerate(operations)
                if op == b'Tj' and str(args[0]) == 'TERCERA. OBLIGACIONES DEL CONTRATANTE:']
    assert len(headings) == 1, 'Approved payment heading must occur exactly once'
    start = next(i for i in range(headings[0] + 1, len(operations)) if operations[i][1] == b'BT')
    end = next(i for i in range(start + 1, len(operations)) if operations[i][1] == b'ET')
    texts = [(args, op) for args, op in operations[start:end] if op in (b'Tj', b'TJ', b"'", b'"')]
    raw = ' '.join(str(args[0]) for args, op in texts)
    assert len(texts) == 5 and 'precio acordado' in raw and 'forma de pago' in raw
    stream.operations = [(args, op) for i, (args, op) in enumerate(operations)
                         if not (start < i < end and op in (b'Tj', b'TJ', b"'", b'"'))]
    page.replace_contents(stream)
writer.add_metadata({'/Title': 'JAC Music — plantilla de pago total', '/Author': 'JAC Music'})
writer.compress_identical_objects(remove_unreferenced=True)
output = io.BytesIO()
writer.write(output)
data['paidTemplate'] = base64.b64encode(output.getvalue()).decode()
path.write_text(json.dumps(data, ensure_ascii=False, separators=(',', ':')) + '\n')
print('Prepared paid-in-full variant; original template, fonts and signature preserved.')
