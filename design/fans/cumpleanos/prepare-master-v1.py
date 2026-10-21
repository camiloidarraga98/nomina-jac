"""Reproducible technical masks/canvas. Never changes the approved photograph.
Run manually with Pillow when deliberately revising render-v1 assets.
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
# A carefully bounded envelope for the right guest, hat, raised hand and body.
# The left artist, heading and foreground table/bottle/cake stay protected.
polygons=[
 # Hair/face/neck and red birthday hat, with room for different hairstyles.
 [(741,247),(876,247),(903,335),(972,379),(995,432),(993,519),(971,552),(947,587),(880,620),(792,592),(746,566),(716,527),(711,480),(718,436),(732,399),(746,373)],
 # Shirt/torso. Preserve the furniture visible between the arm and this torso.
 [(779,574),(840,594),(924,556),(981,554),(1048,574),(1121,587),(1121,1065),(1089,1129),(1034,1154),(960,1161),(909,1151),(866,1152),(812,1176),(751,1153),(709,1100),(751,1037),(793,995),(806,973),(790,957),(783,932),(780,903),(777,867),(773,842),(758,816),(748,799),(728,762),(714,720),(696,692),(701,668),(717,634),(739,606)],
 # Raised glass, fingers, forearm and sleeve; the nearby green suit stays outside.
 [(620,664),(667,667),(672,692),(685,701),(695,717),(690,740),(677,768),(670,795),(685,823),(704,840),(714,875),(704,897),(691,918),(669,930),(639,916),(621,894),(616,859),(613,822),(604,796),(585,779),(582,749),(584,725),(592,705),(608,694),(618,690)],
 # Black sleeve surrounding the raised forearm.
 [(676,770),(700,736),(722,751),(749,791),(770,833),(765,875),(750,904),(724,927),(702,939),(681,930),(695,910),(707,888),(710,866),(699,841),(681,819),(670,795)],
 # Left trouser leg, traced around the ivory seat instead of covering the seat.
 [(802,986),(902,985),(976,1046),(958,1135),(899,1145),(845,1165),(813,1180),(832,1214),(855,1255),(878,1303),(907,1350),(950,1401),(817,1401),(784,1365),(755,1327),(730,1288),(709,1257),(691,1221),(675,1181),(661,1148),(650,1114),(651,1081),(668,1050),(709,1028),(752,1006)],
 # Right trouser leg at the far edge, leaving the visible chair untouched.
 [(1079,1005),(1121,1003),(1121,1401),(1048,1401),(1059,1335),(1072,1284),(1091,1221),(1100,1180),(1081,1148),(1050,1124),(1029,1079)]
]
allowed=Image.new('L',image.size,0);draw=ImageDraw.Draw(allowed)
for polygon in polygons:draw.polygon(polygon,fill=255)
# Clear the exposed gold/ivory chair between elbow, torso and trouser leg.
protected=[[(750,815),(767,832),(773,867),(774,897),(785,932),(797,959),(799,980),(775,998),(746,1016),(713,1030),(703,1038),(689,1022),(689,991),(698,963),(715,944),(736,929),(738,906),(725,890),(735,867)]]
for polygon in protected:draw.polygon(polygon,fill=0)
# The defocused foreground decoration remains in front of the leg.
draw.ellipse((1032,1328,1134,1435),fill=0)
# Feather only on the INSIDE of the allowed region. Zero outside is exact.
blend_alpha=ImageChops.darker(allowed,allowed.filter(ImageFilter.GaussianBlur(2)))
blend=Image.new('RGBA',image.size,'white');blend.putalpha(blend_alpha)
blend.save(folder/'blend-v1.png',compress_level=9)
canvas=Image.new('RGBA',(1024,1536),(38,2,2,255))
canvas.alpha_composite(image.resize((1024,1280),Image.Resampling.LANCZOS),(0,128))
canvas.save(folder/'canvas-v1.png',compress_level=9)
mask=Image.new('RGBA',(1024,1536),'white')
canvas_allowed=Image.new('L',(1024,1536),0)
canvas_allowed.paste(allowed.resize((1024,1280),Image.Resampling.NEAREST),(0,128))
mask.putalpha(ImageChops.invert(canvas_allowed))
mask.save(folder/'mask-v1.png',compress_level=9)
shutil.copyfile(master,public/'master-v1.png')
for name in ['canvas-v1.png','mask-v1.png','blend-v1.png']:shutil.copyfile(folder/name,public/name)
def record(name):
 b=(folder/name).read_bytes();im=Image.open(folder/name)
 return {'file':name,'width':im.width,'height':im.height,'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()}
manifest={'version':1,'status':'prepared_mask_requires_live_quality_review','master':record('master-v1.png'),
 'canvas':record('canvas-v1.png'),'mask':record('mask-v1.png'),'blend':record('blend-v1.png'),
 'sceneRect':{'x':0,'y':128,'width':1024,'height':1280},'editablePolygons':polygons,'protectedPolygons':protected,
 'maskConvention':'alpha_zero_is_editable','blendConvention':'alpha_zero_preserves_master',
 'featherPixelsInsideMask':2,'model':'gpt-image-1.5','modelSize':'1024x1536',
 'protection':'Exact approved master RGBA pixels where blend alpha is zero; provider result never replaces the full frame.'}
(folder/'render-v1.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
preview=image.copy();overlay=Image.new('RGBA',image.size,(235,0,160,0));overlay.putalpha(allowed.point(lambda p:round(p*.4)));preview=Image.alpha_composite(preview,overlay)
work=ROOT/'work'/'local';work.mkdir(parents=True,exist_ok=True);preview.save(work/'fans-birthday-mask-review.png')
print(json.dumps({key:manifest[key] for key in ['canvas','mask','blend']}))
