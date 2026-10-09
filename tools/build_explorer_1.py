#!/usr/bin/env python3
"""Deterministic, dependency-free Explorer-1 exterior mesh generator (metres, Y up)."""
import json, math, struct
from pathlib import Path
from collections import defaultdict

OUT = Path(__file__).resolve().parents[1] / 'assets/models/explorer_1'
TAU = math.tau
materials = [
    ('Ceramic ivory', '#d6d5ce', .12, .64), ('Alternate ceramic', '#bfbfb8', .15, .68),
    ('Panel seals', '#303639', .25, .72), ('Heat tiles', '#242829', .12, .9),
    ('Heat tiles alternate', '#303334', .12, .88), ('Titanium', '#727b7e', .8, .32),
    ('Window glass', '#233d54', .65, .16), ('Glass reflection', '#486278', .55, .21),
    ('Ochre markings', '#dc943d', .22, .53), ('Nozzle bronze', '#9d8560', .8, .37),
    ('Nozzle interior', '#10191e', .3, .85), ('Warning yellow', '#e2b74c', .15, .6)]
mesh = defaultdict(list)
def add(a,b): return tuple(x+y for x,y in zip(a,b))
def sub(a,b): return tuple(x-y for x,y in zip(a,b))
def mul(a,s): return tuple(x*s for x in a)
def cross(a,b): return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def norm(a): return mul(a,1/max(1e-12,math.sqrt(sum(x*x for x in a))))
def tri(mat,a,b,c):
    n=norm(cross(sub(b,a),sub(c,a)))
    for v in (a,b,c): mesh[mat].append((*v,*n, v[0],v[1]))
def quad(mat,a,b,c,d): tri(mat,a,b,c); tri(mat,a,c,d)
def lathe(mat,profile,segments=96,start=0,end=TAU):
    for j in range(len(profile)-1):
        r,y=profile[j]; rr,yy=profile[j+1]
        for i in range(segments):
            a=start+(end-start)*i/segments; b=start+(end-start)*(i+1)/segments
            quad(mat,(r*math.sin(a),y,r*math.cos(a)),(r*math.sin(b),y,r*math.cos(b)),(rr*math.sin(b),yy,rr*math.cos(b)),(rr*math.sin(a),yy,rr*math.cos(a)))
def radius(y): return .93-(y-.3)*(.61/1.92)
def face(angle,x,y,d=0):
    z=math.sqrt(max(.001,radius(y)**2-x*x))+d
    return (x*math.cos(angle)+z*math.sin(angle), y, z*math.cos(angle)-x*math.sin(angle))
def polygon(mat,points,angle,depth):
    center=tuple(sum(p[i] for p in points)/len(points) for i in range(2))
    for i,p in enumerate(points): tri(mat,face(angle,*center,depth),face(angle,*p,depth),face(angle,*points[(i+1)%len(points)],depth))
def outline(x,y,w,h,corner=.025,taper=0):
    # CCW rounded trapezoid.
    pts=[]
    for cx,cy,begin in [(w/2-corner,-h/2+corner,-90),(w/2-corner,h/2-corner,0),(-w/2+corner,h/2-corner,90),(-w/2+corner,-h/2+corner,180)]:
        for j in range(5):
            a=math.radians(begin+j*90/4)
            px=cx+corner*math.cos(a); py=cy+corner*math.sin(a)
            pts.append((x+px*(1-taper*(py/h+.5)),y+py))
    return pts
def panel(mat,angle,x,y,w,h,depth=.018,corner=.025,taper=0):
    pts=outline(x,y,w,h,min(corner,w/4,h/4),taper)
    polygon(mat,pts,angle,depth)
    for i,p in enumerate(pts):
        q=pts[(i+1)%len(pts)]
        quad(mat,face(angle,*p,0),face(angle,*q,0),face(angle,*q,depth),face(angle,*p,depth))
def bolt(a,x,y,d=.026):
    pts=[(x+.007*math.cos(i*TAU/8),y+.007*math.sin(i*TAU/8)) for i in range(8)]
    polygon(5,pts,a,d)
    panel(2,a,x,y,.008,.0015,d+.001,.0001)
def tube(mat,center,axis,profile,segments=24):
    up=norm(axis); right=norm(cross((1,0,0) if abs(up[0])<.9 else (0,0,1),up)); forward=cross(right,up)
    def point(r,z,a): return add(center,add(mul(up,z),add(mul(right,r*math.cos(a)),mul(forward,r*math.sin(a)))))
    for (r,z),(rr,zz) in zip(profile,profile[1:]):
        for i in range(segments):
            a=i*TAU/segments; b=(i+1)*TAU/segments
            quad(mat,point(r,z,a),point(rr,zz,a),point(rr,zz,b),point(r,z,b))

# Continuous pressure shell beneath individually separated ceramic panels.
lathe(2,[(.0,.13),(.84,.13),(.91,.29),(.908,.31),(.302,2.22),(.30,2.24)])
for band,(lo,hi) in enumerate([(.315,.9),(.905,1.48),(1.485,1.97),(1.975,2.215)]):
    for sector in range(16):
        a=(sector-.5)*TAU/16+.003; b=(sector+.5)*TAU/16-.003
        lathe(1 if (sector+band*3)%9==0 else 0,[(radius(lo)+.002,lo),(radius(hi)+.002,hi)],8,a,b)
        for yy in [lo+.026,hi-.026]:
            for aa in [a+.022,b-.022]: bolt(aa,0,yy,.009)
# Rounded segmented heat shield, underside concentric tiles.
lathe(2,[(0,0),(.70,0),(.85,.055),(.93,.16),(.95,.27),(.94,.315)])
for row,prof in enumerate([[(.70,.003),(.85,.06),(.92,.15)],[(.922,.155),(.948,.235),(.942,.3)]]):
    for i in range(48): lathe(3+(i%5==0),prof,3,i*TAU/48+.003,(i+1)*TAU/48-.003)
for inner,outer in [(.0,.27),(.275,.52),(.525,.70)]:
    for i in range(32): lathe(3+(i%7==0),[(inner,.001),(outer,.001)],3,i*TAU/32+.006,(i+1)*TAU/32-.006)
lathe(5,[(.937,.30),(.94,.31),(.934,.32)])
# Panoramic trapezoidal windows with three stepped seals.
for a in [0,.88,-.88,2.18,-2.18,math.pi]:
    panel(5,a,0,1.63,.335,.455,.016,.035,.22)
    panel(2,a,0,1.63,.31,.43,.027,.03,.22)
    panel(6,a,0,1.63,.245,.352,.032,.022,.22)
    polygon(7,[(-.09,1.48),(-.065,1.79),(-.02,1.79),(-.052,1.56)],a,.034)
    for x in [-.135,.135]: bolt(a,x,1.44,.03)
    panel(8,a,0,1.965,.12,.045,.012,.004)
# Crew hatch gasket, slab, viewport, hinge barrels, external grab handle.
for mat,w,h,d in [(5,.60,.94,.021),(2,.58,.92,.03),(0,.535,.87,.041)]: panel(mat,0,0,.85,w,h,d,.07,.10)
for mat,w,h,d in [(5,.235,.22,.05),(2,.209,.194,.055),(6,.174,.155,.061)]: panel(mat,0,0,1.08,w,h,d,.026)
polygon(7,[(-.07,1.02),(-.053,1.14),(-.014,1.14),(-.04,1.02)],0,.063)
panel(11,0,0,.86,.15,.039,.053,.003)
for x in [-.054,-.024,.006,.036]: polygon(2,[(x,.841),(x+.018,.841),(x+.039,.879),(x+.021,.879)],0,.055)
for y in [.58,1.02]:
    panel(5,0,-.274,y,.06,.125,.063,.013)
    tube(2,face(0,-.28,y-.065,.055),(0,1,-.318),[(.025,0),(.025,.13)],16)
for y in [.72,1.02]: panel(8,0,.292,y,.055,.05,.052,.009)
a=face(0,.296,.72,.09); b=face(0,.296,1.02,.09)
tube(5,a,sub(b,a),[(.014,0),(.014,math.dist(a,b))],16)
for y in [.46,1.25]:
    for x in [-.19,.19]: bolt(0,x,y,.048)
panel(5,0,0,.48,.12,.025,.05,.006)
# RCS quad packs, recessed black bays, bronze nozzle lips and dark throats.
for angle in [.72,-.72,2.40,-2.40]:
    panel(5,angle,0,.545,.325,.325,.022,.027)
    panel(2,angle,0,.545,.293,.291,.034,.018)
    for x in [-.073,.073]:
        for y in [.473,.617]:
            # Aim the tapered nozzle mouths 15 degrees below the horizontal.
            center=face(angle,x,y,.020); axis=(math.sin(angle),-math.tan(math.radians(15)),math.cos(angle))
            tube(9,center,axis,[(.036,-.012),(.056,.048),(.054,.060),(.044,.061),(.026,.001)],24)
            tube(10,center,axis,[(.026,.002),(0,.002)],24)
    for x in [-.14,.14]:
        for y in [.412,.675]: bolt(angle,x,y,.042)
# Service panels, cooling louvers, fasteners and orange rescue markings.
for i in range(1,8):
    a=i*TAU/8
    panel(5,a,0,1.13,.16,.235,.009,.015)
    panel(1,a,0,1.13,.143,.218,.014,.012)
    for y in [1.055,1.205]: bolt(a,0,y,.019)
    if i%2==0:
        panel(2,a,0,.49,.235,.15,.018,.01)
        for j in range(6): panel(5,a,0,.435+j*.021,.20,.008,.026,.002)
    panel(5,a,.13,.8,.066,.045,.014,.006)
    panel(8,a,.13,.8,.026,.018,.020,.003)
for a in [1.35,-1.35]:
    polygon(8,[(-.025,.67),(.015,.67),(.015,.91),(-.075,1.13),(-.075,1.4),(-.12,1.4),(-.12,1.11),(-.025,.88)],a,.014)
    panel(0,a,-.095,1.29,.011,.2,.016,.001)
# Stencilled 01 using geometric strokes, legible in exported asset.
a=.37
for x in [-.06,.018]: panel(2,a,x,.99,.018,.17,.02,.001)
for y in [.914,1.066]: panel(2,a,-.021,y,.08,.018,.02,.001)
panel(2,a,.09,.99,.023,.17,.02,.001)
panel(2,a,.077,1.059,.05,.023,.02,.001)
# Docking collar has an actual central recess and locking dogs.
lathe(2,[(.30,2.215),(.335,2.23),(.335,2.29),(.28,2.31),(.23,2.31),(.23,2.24),(0,2.24)])
lathe(5,[(.33,2.275),(.336,2.30),(.326,2.325),(.248,2.325),(.235,2.30),(.235,2.265)])
lathe(9,[(.243,2.272),(.244,2.284),(.234,2.284)])
for i in range(12):
    a=i*TAU/12
    lathe(0 if i%3 else 5,[(.265,2.324),(.265,2.345),(.314,2.345),(.314,2.324)],4,a+.025,a+.22)
    tube(5,(.298*math.sin(a),2.327,.298*math.cos(a)),(0,1,0),[(.01,0),(.01,.015),(0,.015)],10)
# Offset antenna and brass ferrule.
c=(.23,2.29,-.1)
tube(2,c,(0,1,0),[(.048,0),(.043,.05),(.023,.075)],24)
tube(9,add(c,(0,.05,0)),(0,1,0),[(.022,0),(.015,.07)],20)
tube(5,add(c,(0,.1,0)),(.05,1,0),[(.01,0),(.006,.34),(0,.345)],16)

# One mesh primitive per material keeps the many details inexpensive to submit.
blob=bytearray(); views=[]; accessors=[]; primitives=[]
for mat,verts in sorted(mesh.items()):
    offset=len(blob)
    for v in verts: blob.extend(struct.pack('<8f',*v))
    views.append({'buffer':0,'byteOffset':offset,'byteLength':len(blob)-offset,'byteStride':32,'target':34962})
    attrs={}
    for semantic,off,size,typ in [('POSITION',0,3,'VEC3'),('NORMAL',12,3,'VEC3'),('TEXCOORD_0',24,2,'VEC2')]:
        acc={'bufferView':len(views)-1,'byteOffset':off,'componentType':5126,'count':len(verts),'type':typ}
        if semantic=='POSITION':
            acc['min']=[min(v[i] for v in verts) for i in range(3)]; acc['max']=[max(v[i] for v in verts) for i in range(3)]
        attrs[semantic]=len(accessors); accessors.append(acc)
    primitives.append({'attributes':attrs,'material':mat,'mode':4})
def color(h):
    return [((int(h[i:i+2],16)/255+.055)/1.055)**2.4 if int(h[i:i+2],16)/255>.04045 else int(h[i:i+2],16)/255/12.92 for i in [1,3,5]]+[1]
doc={'asset':{'version':'2.0','generator':'Aphelion Explorer-1 procedural authoring tool'},'scene':0,'scenes':[{'nodes':[0]}],'nodes':[{'name':'Explorer_1_Exterior','mesh':0}], 'meshes':[{'name':'Explorer_1','primitives':primitives}], 'materials':[{'name':n,'pbrMetallicRoughness':{'baseColorFactor':color(c),'metallicFactor':m,'roughnessFactor':r}} for n,c,m,r in materials], 'buffers':[{'byteLength':len(blob)}], 'bufferViews':views,'accessors':accessors}
js=json.dumps(doc,separators=(',',':')).encode(); js+=b' '*((-len(js))%4); blob+=b'\0'*((-len(blob))%4)
data=struct.pack('<III',0x46546c67,2,12+8+len(js)+8+len(blob))+struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(blob),0x004e4942)+blob
OUT.mkdir(parents=True,exist_ok=True); (OUT/'explorer_1.glb').write_bytes(data)
print(f'Explorer-1: {sum(len(v)//3 for v in mesh.values()):,} triangles, {len(primitives)} material surfaces, {len(data):,} bytes')
