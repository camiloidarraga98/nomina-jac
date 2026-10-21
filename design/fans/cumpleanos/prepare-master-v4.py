"""Reproduce the complete, opaque reference for maskless birthday editing.

The approved master and earlier versions stay immutable. There is no erasure,
editing mask, output matte or pasted-back master region in this version.
"""
from pathlib import Path
import hashlib,json,shutil
from PIL import Image

folder=Path(__file__).resolve().parent
root=folder.parents[2]
public=root/'public'/'cumpleanos'
master=folder/'master-v1.png'
assert hashlib.sha256(master.read_bytes()).hexdigest()=='155f37db37855cc4af04ca5a88260211526ed21c56477b4d9e5c0d4e4dcdbbc4'
image=Image.open(master).convert('RGBA')
assert image.size==(1122,1402)
canvas=image.resize((1024,1280),Image.Resampling.LANCZOS)
canvas.save(folder/'canvas-v4.png',compress_level=9)
public.mkdir(parents=True,exist_ok=True)
shutil.copyfile(folder/'canvas-v4.png',public/'canvas-v4.png')

def record(name):
    data=(folder/name).read_bytes()
    with Image.open(folder/name) as item:
        return {'file':name,'width':item.width,'height':item.height,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}

manifest={
    'version':4,
    'status':'maskless_full_frame_requires_live_quality_review',
    'master':record('master-v1.png'),
    'canvas':record('canvas-v4.png'),
    'sceneRect':{'x':0,'y':0,'width':1024,'height':1280},
    'mode':'maskless_full_frame',
    'inputPreparation':'complete_opaque_master_without_erasure',
    'providerMask':False,
    'outputPreparation':'resize_complete_provider_frame_only_without_masks_or_master_patches',
    'model':'gpt-image-2.5-sunburst-2026-09-08',
    'modelSize':'1024x1280',
    'quality':'high',
    'preservation':'The prompt requests artist, caption, foreground and scene fidelity. Exact master pixel preservation is not guaranteed by a generative full-frame edit.',
    'naturalOcclusion':'The companion hand and complete glass may naturally overlap the artist suit without a compositing cut.',
}
(folder/'render-v4.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
work=root/'work'/'local'
work.mkdir(parents=True,exist_ok=True)
shutil.copyfile(folder/'canvas-v4.png',work/'fans-birthday-canvas-v4-review.png')
print(json.dumps(manifest['canvas']))
