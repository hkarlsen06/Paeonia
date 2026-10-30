exec(open('/tmp/paeonia-avatar-expansion/measure.py').read().split('for name,source in zip')[0])
import json
measurements={}
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
 band={'cosy':65,'woodland':55,'christmas':55,'flame':55,'winter':45}.get(name,30)
 photo_diameter=2*(radius+band)
 # Center the measured aperture, retain alpha and uniform scale, never auto-trim.
 factor=.65
 resized=im.resize((round(w*factor),round(h*factor)),Image.Resampling.LANCZOS)
 canvas=Image.new('RGBA',(1024,1024));canvas.alpha_composite(resized,(round(512-fx*factor),round(512-fy*factor)))
 scale=1024/(photo_diameter*factor)
 box=canvas.getchannel('A').point(lambda v:255 if v>8 else 0).getbbox()
 outsets=[max(0,(512-box[0])*scale/1024-.5),max(0,(512-box[1])*scale/1024-.5),max(0,(box[2]-512)*scale/1024-.5),max(0,(box[3]-512)*scale/1024-.5)]
 asset='AvatarFrame'+name.title();folder=Path('ios/PaeoniaApp/Resources/Assets.xcassets/AvatarFrames')/(asset+'.imageset');folder.mkdir(exist_ok=True)
 canvas.save(folder/(asset+'.png'))
 (folder/'Contents.json').write_text(json.dumps({'images':[{'filename':asset+'.png','idiom':'universal'}],'info':{'author':'xcode','version':1}},indent=2)+'\n')
 measurements[name]={'source':str(source),'aperture_center':[fx,fy],'aperture_radius':radius,'photo_diameter_source':photo_diameter,'canvas_factor':factor,'artworkScale':scale,'outsets':outsets,'bounds':box}
 p=Path('ios/PaeoniaApp/Shared/Components/AvatarDecoration.swift');s=p.read_text().replace(f'case .{name}: 1\n',f'case .{name}: {scale:.5f}\n');p.write_text(s)
 print(name,'scale',round(scale,5),'outsets',*[round(v,3) for v in outsets])
(root/'geometry.json').write_text(json.dumps(measurements,indent=2))
