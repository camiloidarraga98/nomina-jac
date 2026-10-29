"""Prepare the private contract master. Maintenance only; no Python is used by the app.
Usage: python3 scripts/prepare-contract-template.py supplied-contract.pdf
Requires pypdf/reportlab. Keeps artwork/signature and removes variable text operators,
so the example's identities and prices are not hidden behind replacement text.
"""
import base64, hashlib, io, json, re, sys, subprocess
from pathlib import Path
from pypdf import PdfReader, PdfWriter
from pypdf.generic import ContentStream
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

source = Path(sys.argv[1]).read_bytes()
expected = '0f31bc77d634919e7b6377cc13a5b6b9e7701a3205e3e6a471e9f68e56770e31'
if hashlib.sha256(source).hexdigest() != expected:
    raise ValueError('This is not the approved JAC contract master')
reader = PdfReader(io.BytesIO(source))
if len(reader.pages) != 4:
    raise ValueError('Expected the approved four-page JAC master')
# Operation indices belong to this specific approved master, never another PDF.
print('Master SHA256:', hashlib.sha256(source).hexdigest())
ranges = {0: [(95, 222), (266, 307)], 1: [(437, 519)], 3: [(447, 468)]}
writer = PdfWriter()
for i, original in enumerate(reader.pages):
    page = writer.add_page(original)
    stream = ContentStream(page.get_contents(), writer)
    stream.operations = [(a, op) for j, (a, op) in enumerate(stream.operations)
                         if not (op in (b'Tj', b'TJ', b"'", b'"') and
                                 any(start <= j <= end for start, end in ranges.get(i, [])))]
    page.replace_contents(stream)
writer.add_metadata({'/Title': 'JAC Music — plantilla de contrato', '/Author': 'JAC Music'})
writer.compress_identical_objects(remove_unreferenced=True)
master = io.BytesIO()
writer.write(master)
# Document embedding subsets of the same Arial family, extended for Spanish names.
# Fonts are private PDF resources, not public web fonts or separately downloadable.
font_dir = Path('/System/Library/Fonts/Supplemental')
characters = ''.join(chr(n) for n in list(range(32, 127)) + list(range(160, 256))) + '–—‘’“”€'
pack = io.BytesIO()
c = canvas.Canvas(pack, pagesize=(612, 792), invariant=1)
for name, filename in [('ContractArial', 'Arial.ttf'), ('ContractArialBold', 'Arial Bold.ttf')]:
    pdfmetrics.registerFont(TTFont(name, str(font_dir / filename)))
    c.setFont(name, 10)
    c.drawString(0, 600 if name == 'ContractArial' else 500, characters)
c.save()
fonts = {}
font_reader = PdfReader(io.BytesIO(pack.getvalue()))
for key, ref in font_reader.pages[0]['/Resources']['/Font'].items():
    font = ref.get_object()
    if '/ToUnicode' not in font:
        continue
    mapping = {}
    for group in re.findall(r'beginbfchar(.*?)endbfchar', font['/ToUnicode'].get_data().decode(), re.S):
        for code, unicode in re.findall(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>', group):
            char = bytes.fromhex(unicode).decode('utf-16-be')
            width = float(font['/Widths'][int(code, 16) - int(font['/FirstChar'])])
            mapping[char] = [code, width]
    fonts['bold' if 'Bold' in font['/BaseFont'] else 'regular'] = {'resource': str(key).lstrip('/'), 'glyphs': mapping}
assert len(fonts) == 2 and all('Ñ' in f['glyphs'] and 'ú' in f['glyphs'] for f in fonts.values())
output = {'sourceSha256': hashlib.sha256(source).hexdigest(), 'template': base64.b64encode(master.getvalue()).decode(),
          'fontPack': base64.b64encode(pack.getvalue()).decode(), 'fonts': fonts}
Path('lib/contract-template.json').write_text(json.dumps(output, ensure_ascii=False, separators=(',', ':')) + '\n')
print('Prepared private template and Arial subsets:', len(master.getvalue()), len(pack.getvalue()), 'bytes')
subprocess.run([sys.executable, str(Path(__file__).with_name('prepare-paid-contract-template.py'))], check=True)
