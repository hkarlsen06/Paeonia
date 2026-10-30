from pathlib import Path
from PIL import Image,ImageDraw
import json
root=Path('/tmp/paeonia-avatar-expansion');data=json.loads((root/'geometry.json').read_text())
photo=Image.open('ios/PaeoniaApp/App/DeveloperScenarios/MemoriesMapPhotos/scenario-memory-avatar-alex.webp').convert('RGBA')
side=min(photo.size);photo=photo.crop(((photo.width-side)//2,(photo.height-side)//2,(photo.width+side)//2,(photo.height+side)//2))
sheet=Image.new('RGBA',(800,9*156),(56,15,39,255));draw=ImageDraw.Draw(sheet)
for row,(name,g) in enumerate(data.items()):
 for col,size in enumerate([64,72,80,104]):
  tile=Image.new('RGBA',(200,156),(56,15,39,255));p=photo.resize((size,size));mask=Image.new('L',(size,size));ImageDraw.Draw(mask).ellipse((0,0,size-1,size-1),fill=255);p.putalpha(mask);tile.alpha_composite(p,((200-size)//2,(136-size)//2))
  im=Image.open('ios/PaeoniaApp/Resources/Assets.xcassets/AvatarFrames/AvatarFrame'+name.title()+'.imageset/AvatarFrame'+name.title()+'.png');w=round(size*g['artworkScale']);im=im.resize((w,w),Image.Resampling.LANCZOS);tile.alpha_composite(im,((200-w)//2,(136-w)//2));ImageDraw.Draw(tile).text((8,137),name+' '+str(size),fill='white');sheet.alpha_composite(tile,(col*200,row*156))
sheet.save(root/'actual-size-composites.png')
