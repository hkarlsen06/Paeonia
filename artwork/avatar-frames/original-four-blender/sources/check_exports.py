from PIL import Image
import numpy as np, json
from pathlib import Path
root=Path('/tmp/paeonia-avatar-frames')
y,x=np.mgrid[0:1024,0:1024];r=np.hypot(x+.5-512,y+.5-512)
result={'canvas_px':[1024,1024],'center_px':[512,512],'photo_diameter_in_export_coordinates_px':1024/1.8,'placement':{'overlay_width_in_photo_diameters':1.8,'overlay_height_in_photo_diameters':1.8,'centered':True,'trim_transparent_margin':False},'frames':{}}
for p in sorted((root/'exports').glob('*.png')):
 a=np.asarray(Image.open(p))[:,:,3];ys,xs=np.nonzero(a);rr=r[a>0]
 entry={'alpha_bounds_px':[int(xs.min()),int(ys.min()),int(xs.max()+1),int(ys.max()+1)],'clear_aperture_radius_px':round(float(rr.min()-.71),2),'max_alpha_inside_320px_radius':int(a[r<320].max()),'corner_alpha':[int(a[yy,xx]) for yy,xx in [(0,0),(0,-1),(-1,0),(-1,-1)]]}
 # Own plus mockup at lower right. 32pt button and 2pt outline, D=64.
 scale=1024/(64*1.8);cx=512+(64/2-10)*scale;cy=512+(64/2-10)*scale
 entry['nontransparent_pixels_in_64pt_plus_zone']=int(np.count_nonzero(a[np.hypot(x+.5-cx,y+.5-cy)<16*scale]))
 # The centered badge's top is 8pt below the photo; all frame pixels at that
 # vertical position must lie outside a 64pt-wide pill footprint.
 pill=(abs(x+.5-512)<32*scale)&(y+.5>512+40*scale)&(y+.5<512+62*scale)
 entry['nontransparent_pixels_in_64pt_story_pill_zone']=int(np.count_nonzero(a[pill]))
 assert entry['max_alpha_inside_320px_radius']==0,(p.name,entry)
 assert not any(entry['corner_alpha'])
 assert entry['nontransparent_pixels_in_64pt_plus_zone']==0
 assert entry['nontransparent_pixels_in_64pt_story_pill_zone']==0
 result['frames'][p.name]=entry
(root/'geometry.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
