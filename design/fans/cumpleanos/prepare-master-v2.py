"""Reproducible broad-region v2 editing assets; approved master stays immutable.
The provider input is a transparent spatial opening, not a man's silhouette.
"""
from pathlib import Path
import hashlib,json,shutil
from PIL import Image,ImageDraw,ImageFilter,ImageChops
ROOT=Path(__file__).resolve().parents[3]
folder=Path(__file__).resolve().parent
public=ROOT/'public'/'cumpleanos';public.mkdir(parents=True,exist_ok=True)
master=folder/'master-v1.png';raw=master.read_bytes()
assert hashlib.sha256(raw).hexdigest()=='155f37db37855cc4af04ca5a88260211526ed21c56477b4d9e5c0d4e4dcdbbc4'
image=Image.open(master).convert('RGBA');assert image.size==(1122,1402)
w,h=image.size
# One connected RIGHT spatial region, bounded by the protected left artist and
# foreground. The interior intentionally includes all right-side chair gaps,
# both sides of the old person and room for long hair/dresses/body variation.
polygon=[(670,225),(1121,225),(1121,1401),(782,1401),(772,1350),(746,1317),(717,1290),
 (681,1260),(650,1227),(626,1188),(620,1148),(637,1110),(644,1062),(639,1020),(624,980),
 (608,950),(605,929),(613,909),(616,891),(611,863),(609,832),(605,808),(595,793),
 (579,781),(573,760),(575,730),(581,712),(590,698),(606,690),(617,678),(618,667),
 (677,665),(681,649),(676,622),(670,596)]
allowed=Image.new('L',(w,h),0);ImageDraw.Draw(allowed).polygon(polygon,fill=255)
# Along the toast contact, preserve the visible green velvet of the LEFT
# artist. This moves only the outer connected boundary, never introduces holes
# or follows the new fan's body/clothing. Every editable pixel to its right is
# still one continuous regeneration region.
rgb=image.convert('RGB');adjusted_contact_rows=[]
for yy in range(667,931):
 row=[xx for xx in range(550,690) if allowed.getpixel((xx,yy))]
 if not row:continue
 start=row[0];edge=start
 for xx in range(start,min(start+24,690)):
  rr,gg,bb=rgb.getpixel((xx,yy))
  if gg>rr*1.10+2 and bb>rr*1.10+2:edge=xx+1
  else:break
 if edge>start:
  ImageDraw.Draw(allowed).line((start,yy,edge-1,yy),fill=0)
  adjusted_contact_rows.append([yy,start,edge])

# Distance feather ONLY against the protected top/left boundary. Extending the
# right/bottom edge with editable pixels avoids a preserved border there.
radius=20
extended=Image.new('L',(w+radius*2,h+radius*2),255);extended.paste(allowed,(radius,radius))
draw=ImageDraw.Draw(extended);draw.rectangle((0,0,w+radius*2-1,radius-1),fill=0);draw.rectangle((0,0,radius-1,h+radius*2-1),fill=0)
blend_alpha=Image.new('L',(w,h),0);current=extended
for level in range(radius):
 increment=((level+1)*255)//radius-(level*255)//radius
 layer=current.crop((radius,radius,radius+w,radius+h)).point(lambda value,amount=increment:amount if value else 0)
 blend_alpha=ImageChops.add(blend_alpha,layer)
 current=current.filter(ImageFilter.MinFilter(3))
# The old subject must be 100% regenerated, never mixed back into the fan.
# This is solely a blend-core guarantee, NOT an editing/silhouette constraint.
# All new body/hair/clothes may occupy the much broader connected allowed area.
core_polygon=[(710,245),(1121,245),(1121,1401),(775,1401),(739,1342),(704,1286),(669,1221),
 (640,1164),(618,1110),(620,1060),(651,1017),(696,978),(722,948),(729,921),(712,900),
 (682,878),(656,845),(636,809),(614,789),(591,769),(578,742),(580,708),(593,682),
 (614,659),(648,650),(679,665),(690,625),(708,581),(713,536),(704,487),(710,429)]
core=Image.new('L',(w,h),0);ImageDraw.Draw(core).polygon(core_polygon,fill=255)
# Previous pixel coverage is used ONLY to guarantee no old subject is blended
# back. It neither shapes the new edit region nor reaches the provider input.
legacy=Image.open(folder/'blend-v1.png').getchannel('A').point(lambda value:255 if value else 0)
core=ImageChops.lighter(core,legacy)
core=ImageChops.darker(core,allowed)
blend_alpha=ImageChops.lighter(blend_alpha,core)
blend=Image.new('RGBA',(w,h),'white');blend.putalpha(blend_alpha);blend.save(folder/'blend-v2.png',compress_level=9)
# Native scene framing: no letterbox or crop transform. Clear RGB as well as
# alpha inside the opening so no old man/clothing pixels reach the provider.
canvas=image.resize((1024,1280),Image.Resampling.LANCZOS)
canvas_allowed=allowed.resize(canvas.size,Image.Resampling.NEAREST)
canvas.paste((0,0,0,0),(0,0),canvas_allowed)
canvas.save(folder/'canvas-v2.png',compress_level=9)
mask=Image.new('RGBA',canvas.size,'white');mask.putalpha(ImageChops.invert(canvas_allowed));mask.save(folder/'mask-v2.png',compress_level=9)
for name in ['canvas-v2.png','mask-v2.png','blend-v2.png']:shutil.copyfile(folder/name,public/name)
def record(name):
 b=(folder/name).read_bytes();im=Image.open(folder/name)
 return {'file':name,'width':im.width,'height':im.height,'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()}
manifest={'version':2,'status':'broad_region_prepared_requires_live_quality_review','master':record('master-v1.png'),
 'canvas':record('canvas-v2.png'),'mask':record('mask-v2.png'),'blend':record('blend-v2.png'),
 'sceneRect':{'x':0,'y':0,'width':1024,'height':1280},'editablePolygons':[polygon],'protectedPolygons':[],
 'maskConvention':'alpha_zero_is_editable','blendConvention':'alpha_zero_preserves_master',
 'contactBoundaryAdjustedRows':adjusted_contact_rows,'featherPixelsInsideMask':radius,'featherEdges':['protected_top','protected_left'],
 'fullyEditableEdges':['right','bottom'],
 'inputPreparation':'editable_region_rgba_zeroed_before_provider',
 'blendCorePurpose':'All original guest pixels fully replaced; no male clothing or skin mixed back into the fan.',
 'blendCorePolygons':[core_polygon],
 'blendCoreLegacyCoverage':{'file':'blend-v1.png','sha256':hashlib.sha256((folder/'blend-v1.png').read_bytes()).hexdigest(),'rule':'alpha_gt_zero_intersected_with_connected_v2_region'},
 'model':'gpt-image-2.5-sunburst-2026-09-08','modelSize':'1024x1280','quality':'high',
 'protectedElements':['left_artist','caption','left_foreground_table_cake_and_bottle'],
 'regeneratedContext':['right_guest_entire_appearance','right_chair','right_background'],
 'protection':'Exact approved master RGBA pixels where blend alpha is zero; no original right-chair holes or guest silhouette constraints.'}
(folder/'render-v2.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
work=ROOT/'work'/'local';work.mkdir(parents=True,exist_ok=True)
overlay=Image.new('RGBA',(w,h),(235,0,160,0));overlay.putalpha(allowed.point(lambda value:round(value*.38)))
Image.alpha_composite(image,overlay).save(work/'fans-birthday-mask-v2-review.png')
alpha_preview=Image.new('RGBA',(w,h),(0,200,240,0));alpha_preview.putalpha(blend_alpha.point(lambda value:round(value*.5)))
Image.alpha_composite(image,alpha_preview).save(work/'fans-birthday-blend-v2-review.png')
checker=Image.new('RGBA',canvas.size,(206,206,206,255));d=ImageDraw.Draw(checker)
for yy in range(0,1280,32):
 for xx in range(0,1024,32):
  if (xx//32+yy//32)%2:d.rectangle((xx,yy,xx+31,yy+31),fill=(238,238,238,255))
Image.alpha_composite(checker,canvas).convert('RGB').save(work/'fans-birthday-canvas-v2-review.png')
print(json.dumps({key:manifest[key] for key in ['canvas','mask','blend']}))
