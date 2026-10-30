import bpy, math
from math import sin,cos,pi
from mathutils import Vector
ROOT='/tmp/paeonia-avatar-frames'
bpy.ops.wm.open_mainfile(filepath=ROOT+'/sources/paeonia-frames.blend')
# Replace the first surface study with closed, rounded petal meshes. All GUI
# transforms, bow proportions, new cloud objects, and candy placement survive.
def bowl(theta,r,length,width,z,twist=0,center=(0,0)):
    vs=[];fs=[];n=72;nr=12;a=math.radians(theta);out=Vector((cos(a),sin(a),0));side=Vector((-sin(a),cos(a),0))
    for back in [False,True]:
        for j in range(nr+1):
            rad=.001+.999*j/nr
            for i in range(n):
                t=2*pi*i/n;u=rad*cos(t);v=rad*sin(t)
                p=out*(r+length*(u+1)/2)+side*(v*width*.5*(.90+.10*u)+twist*(1-u*u))
                p.x+=center[0];p.y+=center[1]
                p.z=z+.07+.10*rad*rad+.035*u
                if back:p.z-=.045*math.sqrt(max(0,1-rad*rad))+.012
                vs.append(p)
        off=(nr+1)*n if back else 0
        for j in range(nr):
            for i in range(n):
                k=off+j*n+i;kn=off+j*n+(i+1)%n;f=(k,kn,kn+n,k+n);fs.append(f[::-1] if back else f)
    for i in range(n):
        k=nr*n+i;kn=nr*n+(i+1)%n;off=(nr+1)*n;fs.append((k,kn,kn+off,k+off))
    return vs,fs
sc=bpy.data.scenes['01 • Peony ruff'];bpy.context.window.scene=sc
for ob in list(sc.objects):
    if ob.name.startswith('Outer petal'):
        i=int(ob.name.rsplit(' ',1)[1]);a=2+19*i;args=(a,1.22,.30+(.065 if 90<a<170 else 0),.52,0,.05)
    elif ob.name.startswith('Inner curled petal'):
        i=int(ob.name.rsplit(' ',1)[1]);args=(10+18*i,1.16,.235,.37,.09,-.055)
    else:continue
    vs,fs=bowl(*args);oldcenter=ob.location.copy();vs=[v-oldcenter for v in vs]
    me=bpy.data.meshes.new(ob.name+' rounded closed clay');me.from_pydata(vs,[],fs);me.update()
    mats=list(ob.data.materials);ob.data=me
    for m in mats:me.materials.append(m)
    ob.modifiers.clear();su=ob.modifiers.new('Smooth closed petals','SUBSURF');su.levels=1;su.render_levels=2
    for p in me.polygons:p.use_smooth=True
# More natural concentric flower folds replace the first ellipsoid study.
root=bpy.data.objects['PEONY CROWN • move and rotate as one']
for ob in list(sc.objects):
    if ob.name.startswith('Crown outer fold') or ob.name.startswith('Crown inner fold'):
        bpy.data.objects.remove(ob,do_unlink=True)
for layer,count,length,width,z,offset in [(0,7,.26,.25,.13,0),(1,6,.18,.21,.23,23),(2,5,.115,.135,.30,0)]:
    for j in range(count):
        vs,fs=bowl(j*360/count+offset,.015,length,width,z,0,(-.82,1.16))
        me=bpy.data.meshes.new('Crown cup mesh');me.from_pydata(vs,[],fs);me.update();ob=bpy.data.objects.new('Crown petal %d.%d'%(layer,j),me);sc.collection.objects.link(ob)
        me.materials.append(bpy.data.materials['Petal pink • satin clay' if layer>0 else 'Rose • shaded folds'])
        ob.parent=root;ob.matrix_parent_inverse=root.matrix_world.inverted()
        su=ob.modifiers.new('Soft lip','SUBSURF');su.levels=1
        for p in me.polygons:p.use_smooth=True
for sc in bpy.data.scenes:
    sc.cycles.samples=96;sc.render.resolution_percentage=100
    slug=['peony-ruff','ribbon-hug','moon-cloud','candy-twist'][int(sc.name[:2])-1]
    sc.render.filepath=ROOT+'/exports/'+slug+'.png'
bpy.context.window.scene=bpy.data.scenes['01 • Peony ruff']
bpy.ops.wm.save_as_mainfile(filepath=ROOT+'/sources/paeonia-frames-refined.blend')
for sc in bpy.data.scenes:
    bpy.context.window.scene=sc;bpy.ops.render.render(write_still=True)
print('FINISHED EXPORTS')
