from pathlib import Path
import shutil,numpy as np
from PIL import Image
root=Path('/tmp/paeonia-avatar-expansion')
sources=sorted(Path('/Users/hkarlsen06/.codex/generated_images/01a18dbd-7e9b-7523-8e99-90af64209716').glob('*.png'),key=lambda p:p.stat().st_mtime)
names=['mischief','flame','rose','woodland','cosy','silver','halloween','christmas','winter']
for name,source in zip(names,sources):
 shutil.copy2(source,root/(name+'-original.png'))
 a=np.array(Image.open(source).convert('RGBA'))[:,:,3];h,w=a.shape
 # Sample first opaque band along rays, ignoring small semitransparent fringe.
 cx,cy=w/2,h/2
 pts=[]
 for theta in np.linspace(0,2*np.pi,360,endpoint=False):
  for r in range(100,int(min(w,h)*.49)):
   x,y=int(cx+r*np.cos(theta)),int(cy+r*np.sin(theta))
   if a[y,x]>200:
    pts.append((x,y));break
 pts=np.array(pts);x,y=pts[:,0],pts[:,1]
 fit=np.linalg.lstsq(np.column_stack([2*x,2*y,np.ones(len(x))]),x*x+y*y,rcond=None)[0]
 fx,fy=fit[:2];radius=np.sqrt(fit[2]+fx*fx+fy*fy)
 print(name,'size',w,h,'aperture fit',round(fx),round(fy),round(radius),'bbox',Image.fromarray(a).point(lambda v:255 if v>8 else 0).getbbox())
