import bpy
from pathlib import Path
root=Path('/tmp/paeonia-avatar-frames')
bpy.ops.wm.open_mainfile(filepath=str(root/'sources/paeonia-frames-refined.blend'))
# The frame models use procedural materials. The comparison is a separate file.
for image in list(bpy.data.images):
    if image.type!='RENDER_RESULT':bpy.data.images.remove(image)
for scene in bpy.data.scenes:
    scene['guaranteed_clear_aperture_px']=640
    scene['portrait_diameter_px']=1024/1.8
    scene['overlay_width_multiplier']=1.8
    scene['do_not_trim']=True
    scene['process']='Blender Python mesh construction; computer-use viewport composition and refinement; Cycles render. No generated raster material.'
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='OUTLINER':area.spaces.active.filter_text=''
bpy.context.window.scene=bpy.data.scenes['04 • Candy twist']
bpy.ops.wm.save_as_mainfile(filepath=str(root/'sources/paeonia-frames-final.blend'))
print('Saved native final source')
