import bpy
from pathlib import Path
root = Path(__file__).resolve().parent.parent
bpy.ops.wm.open_mainfile(filepath=str(root / 'sources/paeonia-frames-final.blend'))
for scene in bpy.data.scenes:
    bpy.context.window.scene = scene
    slug = ['peony-ruff', 'ribbon-hug', 'moon-cloud', 'candy-twist'][int(scene.name[:2]) - 1]
    scene.render.filepath = str(root / 'exports' / (slug + '.png'))
    bpy.ops.render.render(write_still=True)
