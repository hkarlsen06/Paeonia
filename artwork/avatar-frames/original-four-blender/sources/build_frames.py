import bpy, math, os
from mathutils import Vector
from math import sin, cos, pi
ROOT='/tmp/paeonia-avatar-frames'
bpy.ops.wm.read_factory_settings(use_empty=True)

def rgba(h):
    vals=[int(h[i:i+2],16)/255 for i in (0,2,4)]
    return tuple(v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in vals)+(1,)
def material(name,h,rough=.3,metal=.0,coat=.25):
    m=bpy.data.materials.new(name); m.diffuse_color=rgba(h); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=rgba(h)
    p.inputs['Roughness'].default_value=rough; p.inputs['Metallic'].default_value=metal
    p.inputs['Coat Weight'].default_value=coat; p.inputs['Coat Roughness'].default_value=.22
    p.inputs['Subsurface Weight'].default_value=.035
    return m
pink=material('Petal pink • satin clay','F27EB2')
rose=material('Rose • shaded folds','E85D86')
blush=material('Blush • cream silk','FBF3F7')
lavender=material('Lavender • satin clay','B99CF2')
purple=material('Iris • shaded folds','8562C6')
gold=material('Honey gold • satin enamel','F2B84B',.24,.18)
blue=material('Sky blue • satin clay','6FB1F0')
plum=material('Plum • dark inlay','4F203A')
leaf=material('Muted sage • botanical clay','9EBA9B')
candy=material('Rose candy • polished enamel','EF5094',.23,.05,.4)

def smooth(o):
    if o.type=='MESH':
        for p in o.data.polygons:p.use_smooth=True
    return o

def mesh(name,verts,faces,mat):
    data=bpy.data.meshes.new(name); data.from_pydata(verts,[],faces); data.update()
    o=bpy.data.objects.new(name,data); bpy.context.scene.collection.objects.link(o); o.data.materials.append(mat);smooth(o)
    return o

def ellipsoid(name,loc,scale,mat,rz=0):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=40,ring_count=24,location=loc)
    o=bpy.context.object;o.name=name;o.scale=scale;o.rotation_euler.z=rz;o.data.materials.append(mat);smooth(o);return o

def tube(name,pts,rad,mat):
    c=bpy.data.curves.new(name,'CURVE');c.dimensions='3D';c.resolution_u=16;c.bevel_depth=rad;c.bevel_resolution=5;c.use_fill_caps=True
    s=c.splines.new('POLY');s.points.add(len(pts)-1)
    for p,v in zip(s.points,pts):p.co=(*v,1)
    o=bpy.data.objects.new(name,c);bpy.context.scene.collection.objects.link(o);o.data.materials.append(mat);return o

def arc(name,r,a,b,rad,mat,z=0):
    return tube(name,[(r*cos(t),r*sin(t),z) for t in [math.radians(a+(b-a)*i/150) for i in range(151)]],rad,mat)

def ribbon(name,pts,width,mat):
    vs=[];n=len(pts);w=width if isinstance(width,list) else [width]*n
    for i,p in enumerate(pts):
        a=Vector(pts[max(0,i-1)]);b=Vector(pts[min(n-1,i+1)]);t=(b-a).normalized();side=Vector((-t.y,t.x,0)).normalized()
        for j in range(9):
            u=j/4-1;v=Vector(p)+side*u*w[i]/2;v.z+=.055*(1-u*u);vs.append(v)
    fs=[]
    for i in range(n-1):
        for j in range(8):k=i*9+j;fs.append((k,k+1,k+10,k+9))
    o=mesh(name,vs,fs,mat)
    sol=o.modifiers.new('Soft ribbon thickness','SOLIDIFY');sol.thickness=.05
    be=o.modifiers.new('Rounded satin edge','BEVEL');be.width=.025;be.segments=3
    sub=o.modifiers.new('Smooth cloth','SUBSURF');sub.levels=1;sub.render_levels=2
    return o

def petal(name,theta,r,length,width,mat,z=0,twist=0):
    vs=[];fs=[];a=math.radians(theta);out=Vector((cos(a),sin(a),0));side=Vector((-sin(a),cos(a),0));origin=out*r
    for i in range(19):
        t=i/18;hw=width*.5*(sin(pi*t)**.36+.015)
        for j in range(15):
            u=j/7-1
            p=origin+out*(t*length)+side*(u*hw+sin(pi*t)*twist)
            p.z=z+.06+.13*sin(pi*t)+.10*(u*u)*sin(pi*t)+.055*t*t
            vs.append(p)
    for i in range(18):
        for j in range(14):k=i*15+j;fs.append((k,k+1,k+16,k+15))
    o=mesh(name,vs,fs,mat)
    sol=o.modifiers.new('Clay petal thickness','SOLIDIFY');sol.thickness=.055
    be=o.modifiers.new('Soft lip','BEVEL');be.width=.022;be.segments=3
    su=o.modifiers.new('Petal polish','SUBSURF');su.levels=1;su.render_levels=2
    return o

def star(name,x,y,r,mat,z=.1,rot=0):
    # five-point enamel star, softly bevelled, no plus-shaped sparkles
    vs=[]
    for zz in [z-.065,z+.065]:
        for i in range(10):
            a=pi/2+i*pi/5+rot;rr=r if i%2==0 else r*.50;vs.append((x+rr*cos(a),y+rr*sin(a),zz))
    fs=[tuple(range(9,-1,-1)),tuple(range(10,20))]+[(i,(i+1)%10,(i+1)%10+10,i+10) for i in range(10)]
    o=mesh(name,vs,fs,mat);b=o.modifiers.new('Round enamel corners','BEVEL');b.width=.038;b.segments=4
    o.modifiers.new('Weighted face normals','WEIGHTED_NORMAL');return o

def scene(name):
    sc=bpy.data.scenes.new(name);bpy.context.window.scene=sc
    sc.render.engine='CYCLES';sc.cycles.samples=48;sc.cycles.use_denoising=True
    sc.render.resolution_x=1024;sc.render.resolution_y=1024;sc.render.resolution_percentage=100
    sc.render.image_settings.file_format='PNG';sc.render.image_settings.color_mode='RGBA';sc.render.film_transparent=True
    sc.world=bpy.data.worlds.new(name+' studio');sc.world.use_nodes=True
    sc.world.node_tree.nodes['Background'].inputs[0].default_value=(.7,.75,1,1)
    sc.world.node_tree.nodes['Background'].inputs[1].default_value=.30
    sc.view_settings.view_transform='AgX';sc.view_settings.look='AgX - Medium High Contrast';sc.view_settings.exposure=0
    bpy.ops.object.camera_add(location=(0,0,8));cam=bpy.context.object;cam.name='CAMERA • centered 2u photo • 3.6u canvas';cam.data.type='ORTHO';cam.data.ortho_scale=3.6;sc.camera=cam
    for nm,loc,power,size,col in [('KEY upper right',(2.8,4.0,5),440,3.2,(1,.88,.93)),('FILL lower left',(-3,-2,4),150,4,(.76,.81,1)),('RIM pink',(3,1,1.8),65,2,(1,.63,.78))]:
        bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.name=nm;o.data.energy=power;o.data.shape='DISK';o.data.size=size;o.data.color=col;o.rotation_euler=(Vector((0,0,0))-o.location).to_track_quat('-Z','Y').to_euler()
    sc['photo_diameter']=2.0;sc['canvas_width']=3.6;sc['safe_aperture_diameter']=2.24;sc['control_clearance']='bottom and lower-right open; story ring inside aperture'
    return sc

s=scene('01 • Peony ruff')
arc('Botanical stem under petals',1.275,-4,220,.065,rose,-.03)
for i,a in enumerate(range(2,224,19)):
    petal('Outer petal %02d'%i,a,1.22,.30+(.065 if 90<a<170 else 0),.52,[pink,rose,pink][i%3],.00,.05)
for i,a in enumerate(range(10,215,18)):
    petal('Inner curled petal %02d'%i,a,1.16,.235,.37,blush if i in [2,5] else pink,.09,-.055)
# Lower left taper is a joined pair of leaves, not a floating sticker.
petal('Left leaf • long',218,1.18,.28,.20,leaf,-.015,.04)
petal('Left leaf • short',230,1.17,.22,.16,leaf,-.02,.04)
# Crown flower built as one grouped sculptural focal point.
root=bpy.data.objects.new('PEONY CROWN • move and rotate as one',None);s.collection.objects.link(root);root.location=(-.82,1.16,.08)
for j in range(7):
    a=j*2*pi/7;o=ellipsoid('Crown outer fold %02d'%j,(root.location.x+.18*cos(a),root.location.y+.17*sin(a),.25),(.18,.12,.095),pink if j%2 else rose,a);o.parent=root;o.matrix_parent_inverse=root.matrix_world.inverted()
for j in range(5):
    a=j*2*pi/5;o=ellipsoid('Crown inner fold %02d'%j,(root.location.x+.09*cos(a),root.location.y+.08*sin(a),.36),(.12,.075,.08),blush if j==1 else pink,a);o.parent=root;o.matrix_parent_inverse=root.matrix_world.inverted()
o=ellipsoid('Peony gold heart',(-.82,1.16,.405),(.065,.065,.045),gold);o.parent=root;o.matrix_parent_inverse=root.matrix_world.inverted()

s=scene('02 • Ribbon hug')
pts=[]
for i in range(181):
    a=math.radians(-5+230*i/180);r=1.30+.024*sin(4*a);pts.append((r*cos(a),r*sin(a),.035*sin(3*a)))
ribbon('Lavender satin wrap',pts,.24,lavender)
# Raised piping follows the outside edge and gives a readable double folded silhouette.
arc('Blush silk edge',1.405,5,216,.027,blush,.015)
a=math.radians(123);out=Vector((cos(a),sin(a),0));tan=Vector((-sin(a),cos(a),0));base=out*1.40
root=bpy.data.objects.new('BOW • tilt and scale as one',None);s.collection.objects.link(root);root.location=base;bpy.context.view_layer.update()
for sign in [-1,1]:
    pts=[]
    for i in range(81):
        t=2*pi*i/80;u=sign*.43*sin(t/2);v=.22*sin(t)+.14*sin(t/2);p=base+tan*u+out*v;p.z=.12+.11*sin(t/2);pts.append(p)
    o=ribbon('Bow loop '+str(sign),pts,.155,lavender if sign==1 else pink);o.parent=root;o.matrix_parent_inverse=root.matrix_world.inverted()
o=ellipsoid('Gold satin knot',(*base.xy,.23),(.13,.105,.11),gold,a);o.parent=root;o.matrix_parent_inverse=root.matrix_world.inverted()
# The sculpted tail follows the left edge, tapering as it leaves the wrap.
pts=[]
for i in range(91):
    t=i/90;a=math.radians(135+92*t);r=1.36+.13*sin(pi*t);pts.append((r*cos(a),r*sin(a),.10+.07*sin(2*pi*t)))
ribbon('Pink flowing tail',pts,[.20*(1-.65*i/90) for i in range(91)],pink)

s=scene('03 • Moon cloud')
# Sculptural crescent follows the avatar edge, with tapered golden ends.
vs=[];fs=[]
for i in range(121):
    t=i/120;a=math.radians(50+178*t);th=.025+.29*sin(pi*t)**.8;r=1.17+th/2
    for j in range(24):
        u=2*pi*j/24;vs.append(((r+th/2*cos(u))*cos(a),(r+th/2*cos(u))*sin(a),.10*sin(u)*sin(pi*t)**.5))
for i in range(120):
    for j in range(24):k=i*24+j;fs.append((k,i*24+(j+1)%24,(i+1)*24+(j+1)%24,k+24))
o=mesh('MOON • continuous honey crescent',vs,fs,gold)
# Sweeping cloud banks, not a row of confetti.
arc('Lavender vapor arc',1.285,-8,66,.105,lavender,-.03)
cloudroot=bpy.data.objects.new('CLOUD BANK • upper right',None);s.collection.objects.link(cloudroot)
for j,(x,y,rx,ry) in enumerate([(.76,1.05,.22,.13),(.94,.95,.22,.16),(1.11,.78,.19,.18),(1.22,.61,.14,.17)]):
    o=ellipsoid('Cloud lobe %02d'%j,(x,y,.13),(rx,ry,.105),blush if j in [0,1] else lavender,-.6);o.parent=cloudroot
# One connected, solid star sits in the crook of the moon.
star('STAR • honey enamel at crown',-.28,1.46,.235,blush,.14,-.18)
arc('Lavender cloud foot',1.27,193,221,.105,lavender,.06)
for j,(a,r) in enumerate([(197,.13),(210,.16),(220,.115)]):
    t=math.radians(a);ellipsoid('Cloud foot %02d'%j,(1.30*cos(t),1.30*sin(t),.12),(r,r*.8,.10),lavender)

s=scene('04 • Candy twist')
# Interwoven solid ropes with color and depth changing together.
for strand,mat,phase in [('Rose strand',candy,0),('Blush strand',blush,pi)]:
    pts=[]
    for i in range(301):
        t=i/300;a=math.radians(-3+225*t);wave=2*pi*4.4*t+phase;r=1.30+.065*sin(wave);z=.07*cos(wave);pts.append((r*cos(a),r*sin(a),z))
    tube(strand,pts,.078,mat)
# A substantial heart-shaped candy clasp is part of the rope, at top left.
# A closed domed heart with smooth candy edges.
vs=[];fs=[];n=128;nr=18;c=(-.74,1.18)
for side in [-1,1]:
    for j in range(nr+1):
        rad=.001+.999*j/nr
        for i in range(n):
            t=2*pi*i/n;x=16*sin(t)**3;y=13*cos(t)-5*cos(2*t)-2*cos(3*t)-cos(4*t)
            vs.append((c[0]+x*.017*rad,c[1]+y*.017*rad,.13+side*.115*math.sqrt(max(0,1-rad**2))))
    off=(0 if side==-1 else (nr+1)*n)
    for j in range(nr):
        for i in range(n):
            k=off+j*n+i;kn=off+j*n+(i+1)%n;face=(k,kn,kn+n,k+n);fs.append(face if side==1 else face[::-1])
for i in range(n):
    a=nr*n+i;b=nr*n+(i+1)%n;c1=(nr+1)*n+nr*n+i;d=(nr+1)*n+nr*n+(i+1)%n;fs.append((a,b,d,c1))
o=mesh('HEART CLASP • rose enamel',vs,fs,candy)
su=o.modifiers.new('Candy polish','SUBSURF');su.levels=1
# Both terminal ends are deliberately rounded, with a single small gold ferrule.
for a in [-3,222]:
    t=math.radians(a);ellipsoid('Golden cord end '+str(a),(1.30*cos(t),1.30*sin(t),.02),(.105,.08,.10),gold,t)

# Every mesh has a useful local origin for direct visual editing.
for ob in bpy.data.objects:
    if ob.type=='MESH' and not ob.parent:
        center=sum((v.co for v in ob.data.vertices),Vector())/len(ob.data.vertices)
        for v in ob.data.vertices:v.co-=center
        ob.location+=center
# Delete unused factory scene. Open in material view and exact camera view.
for s in list(bpy.data.scenes):
    if not s.camera:bpy.data.scenes.remove(s)
bpy.context.window.scene=bpy.data.scenes['01 • Peony ruff']
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_perspective='CAMERA'
            area.spaces.active.overlay.show_overlays=False
            area.spaces.active.shading.type='MATERIAL'
            area.spaces.active.shading.studiolight_rotate_z=.5
            area.spaces.active.region_3d.view_camera_zoom=8
bpy.ops.wm.save_as_mainfile(filepath=ROOT+'/sources/paeonia-frames.blend')
for sc in bpy.data.scenes:
    bpy.context.window.scene=sc
    sc.render.resolution_percentage=60;sc.cycles.samples=24
    slug=['peony-ruff','ribbon-hug','moon-cloud','candy-twist'][int(sc.name[:2])-1]
    sc.render.filepath=ROOT+'/process/draft-'+slug+'.png';bpy.ops.render.render(write_still=True)
print('DRAFTS FINISHED',flush=True)
