from pathlib import Path
import json,shutil,hashlib,math
import numpy as np
from PIL import Image
root=Path('/tmp/paeonia-avatar-expansion-remaining')
names=list(json.loads((root/'prompts.json').read_text()))
sources=sorted(Path('/Users/hkarlsen06/.codex/generated_images/01a18dd6-cfc9-7b02-b47f-90816410a26b').glob('*.png'),key=lambda p:p.stat().st_mtime)
assert len(sources)==10
geometry={};provenance={}
for name,source in zip(names,sources):
 shutil.copy2(source,root/(name+'-original.png'))
 im=Image.open(source).convert('RGBA');a=np.array(im)[:,:,3];h,w=a.shape
 pts=[]
 for theta in np.linspace(0,2*np.pi,360,endpoint=False):
  for r in range(100,int(min(w,h)*.49)):
   x,y=int(w/2+r*np.cos(theta)),int(h/2+r*np.sin(theta))
   if a[y,x]>200:pts.append((x,y));break
 pts=np.array(pts);x,y=pts[:,0],pts[:,1]
 fit=np.linalg.lstsq(np.column_stack([2*x,2*y,np.ones(len(x))]),x*x+y*y,rcond=None)[0]
 fx,fy=fit[:2];radius=np.sqrt(fit[2]+fx*fx+fy*fy)
 box=im.getchannel('A').point(lambda v:255 if v>8 else 0).getbbox()
 # Photo extends under the band. Also contain every axis within existing 0.28 spacing.
 extent=max(fx-box[0],fy-box[1],box[2]-fx,box[3]-fy)
 diameter=max(2*(radius+38),extent/.775)
 factor=.52
 canvas=Image.new('RGBA',(1024,1024));canvas.alpha_composite(im.resize((round(w*factor),round(h*factor)),Image.Resampling.LANCZOS),(round(512-fx*factor),round(512-fy*factor)))
 scale=1024/(diameter*factor)
 box=canvas.getchannel('A').point(lambda v:255 if v>8 else 0).getbbox()
 outsets=[max(0,v*scale/1024-.5) for v in [512-box[0],512-box[1],box[2]-512,box[3]-512]]
 outset=math.ceil(max(outsets)*100)/100
 assert outset<=.28,(name,outset)
 assert canvas.getpixel((512,512))[3]==0
 asset='AvatarFrame'+name.title();folder=Path('ios/PaeoniaApp/Resources/Assets.xcassets/AvatarFrames')/(asset+'.imageset');folder.mkdir(exist_ok=True)
 canvas.save(folder/(asset+'.png'));(folder/'Contents.json').write_text(json.dumps({'images':[{'filename':asset+'.png','idiom':'universal'}],'info':{'author':'xcode','version':1}},indent=2)+'\n')
 geometry[name]={'source':str(source),'aperture_center':[fx,fy],'aperture_radius':radius,'photo_diameter_source':diameter,'canvas_factor':factor,'artworkScale':scale,'outsets':outsets,'outset':outset,'bounds':box}
 provenance[name]={'source':str(source),'sha256':hashlib.sha256(source.read_bytes()).hexdigest()}
 print(name,round(scale,5),outset,'opening/photo',round(2*radius/diameter,3))
(root/'geometry.json').write_text(json.dumps(geometry,indent=2));(root/'sources.json').write_text(json.dumps(provenance,indent=2))
