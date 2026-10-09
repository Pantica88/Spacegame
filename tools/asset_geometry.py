#!/usr/bin/env python3
"""Dependency-free mesh primitives and glTF writer for locally authored assets."""
import json, math, struct
from pathlib import Path
from collections import defaultdict

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

def save_glb(path, name):
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
    doc={'asset':{'version':'2.0','generator':'Aphelion procedural authoring tool'},'scene':0,'scenes':[{'nodes':[0]}],'nodes':[{'name':name,'mesh':0}], 'meshes':[{'name':name,'primitives':primitives}], 'materials':[{'name':n,'pbrMetallicRoughness':{'baseColorFactor':color(c),'metallicFactor':m,'roughnessFactor':r}} for n,c,m,r in materials], 'buffers':[{'byteLength':len(blob)}], 'bufferViews':views,'accessors':accessors}
    js=json.dumps(doc,separators=(',',':')).encode(); js+=b' '*((-len(js))%4); blob+=b'\0'*((-len(blob))%4)
    data=struct.pack('<III',0x46546c67,2,12+8+len(js)+8+len(blob))+struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(blob),0x004e4942)+blob
    path.parent.mkdir(parents=True,exist_ok=True); path.write_bytes(data)
    print(f'{name}: {sum(len(v)//3 for v in mesh.values()):,} triangles, {len(primitives)} material surfaces, {len(data):,} bytes')
