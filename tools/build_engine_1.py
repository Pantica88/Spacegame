#!/usr/bin/env python3
"""Reference engine, Explorer-1 PBR palette; metres, +Y up, nozzle exit at Y=0."""
import json, math, struct, tempfile
from pathlib import Path
import asset_geometry as g

ROOT = Path(__file__).resolve().parents[1]
parts = []
def finish(name):
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp)/'part.glb'
        g.save_glb(path, name)
        raw = path.read_bytes(); size = struct.unpack_from('<I', raw, 12)[0]
        parts.append((name, json.loads(raw[20:20+size]), raw[28+size:]))
    g.mesh.clear()
def ring(mat,r,y,h=.025,t=.02):
    g.lathe(mat,[(r-t,y),(r,y),(r,y+h),(r-t,y+h),(r-t,y)],96)
def point(a,r,y): return (r*math.sin(a),y,r*math.cos(a))
def rod(mat,a,b,r):
    length=math.dist(a,b)
    g.tube(mat,a,g.sub(b,a),[(0,0),(r*.8,0),(r,.008),(r,length-.008),(r*.8,length),(0,length)],16)
def pipe(a,coords,r=.043):
    # Round polyline corners with quadratic Bezier bends; continuous swept tube.
    coords=[point(a,x,y) for x,y in coords]; path=[coords[0]]
    for prev,c,nxt in zip(coords,coords[1:],coords[2:]):
        entry=g.add(c,g.mul(g.sub(prev,c),.28)); end=g.add(c,g.mul(g.sub(nxt,c),.28))
        path.append(entry)
        for k in range(1,9):
            t=k/8
            path.append(g.add(g.add(g.mul(entry,(1-t)**2),g.mul(c,2*t*(1-t))),g.mul(end,t*t)))
    path.append(coords[-1]); rings=[]
    normal=(math.cos(a),0,-math.sin(a))
    for i,p in enumerate(path):
        tangent=g.norm(g.sub(path[min(i+1,len(path)-1)],path[max(0,i-1)]))
        side=g.norm(g.cross(tangent,normal))
        rings.append([g.add(p,g.add(g.mul(normal,r*math.cos(j*math.tau/16)),g.mul(side,r*math.sin(j*math.tau/16)))) for j in range(16)])
    for first,second in zip(rings,rings[1:]):
        for j in range(16): g.quad(5,first[j],first[(j+1)%16],second[(j+1)%16],second[j])
def beam(a,outline,width):
    tangent=(math.cos(a),0,-math.sin(a))
    sides=[[g.add(point(a,r,y),g.mul(tangent,w)) for r,y in outline] for w in [-width/2,width/2]]
    for face in [sides[0][::-1],sides[1]]:
        for i in range(1,len(face)-1): g.tri(0,face[0],face[i],face[i+1])
    for i in range(len(outline)):
        j=(i+1)%len(outline); g.quad(0,sides[0][i],sides[0][j],sides[1][j],sides[1][i])

# Broad segmented attachment drum and dark flush lid.
g.lathe(2,[(0,2.26),(.92,2.26),(.94,2.29),(.94,2.65),(.9,2.69),(0,2.69)],128)
for i in range(16):
    a=i*math.tau/16+.004; b=(i+1)*math.tau/16-.004
    g.lathe(0,[(.941,2.30),(.949,2.31),(.949,2.60),(.941,2.61)],8,a,b)
    g.lathe(8,[(.951,2.37),(.951,2.46)],8,a,b)
ring(5,.96,2.28,.032); ring(5,.96,2.62,.032)
g.lathe(5,[(.78,2.654),(.78,2.675),(.73,2.69),(.73,2.667)],96)
g.lathe(2,[(.728,2.665),(0,2.665)],96)
finish('Segmented attachment collar')

# Hollow curved bell, rolled lip, interior liner and narrow throat.
profile=[(.70,0),(.71,.025),(.68,.13),(.635,.29),(.58,.47),(.52,.65),(.455,.83),(.37,1.02),(.285,1.14),(.26,1.22)]
g.lathe(5,profile,128)
g.lathe(3,[(r-.022,y+.008) for r,y in profile][::-1],128)
ring(5,.718,0,.028,.04)
for r,y in profile[2:-2]: ring(5,r+.006,y,.012,.012)
ring(5,.456,.82,.025)
g.lathe(2,[(.26,1.20),(.26,1.29),(.20,1.29),(.20,1.18),(.11,1.04)],96)
g.lathe(10,[(.11,1.04),(.105,1.35),(0,1.35)],64)
finish('Hollow ribbed nozzle bell')

# Stepped combustion chamber with segmented ceramic jacket.
g.lathe(5,[(0,1.13),(.27,1.13),(.31,1.20),(.31,1.32),(.265,1.37),(.265,2.21),(.33,2.24),(.33,2.29),(0,2.29)],96)
g.radius=lambda y:.285
for i in range(12):
    a=i*math.tau/12+.006; b=(i+1)*math.tau/12-.006
    g.lathe(0 if i%4 else 1,[(.28,1.43),(.294,1.45),(.294,1.96),(.28,1.98)],8,a,b)
for y in [1.39,1.70,1.98,2.17]: ring(2,.312,y,.047)
ring(8,.297,1.92,.04,.012)
for y in [1.36,1.44,2.04,2.20]: ring(5,.305,y,.016)
for a in [0,math.pi]:
    g.panel(5,a,0,1.70,.22,.40,.015,.017)
    g.panel(0,a,0,1.70,.20,.38,.023,.012)
    for x in [-.077,.077]:
        for y in [1.55,1.85]: g.bolt(a,x,y,.029)
finish('Combustion chamber and jacket')

# Four tapered suspension struts and lower gimbal clevises.
for a in [math.pi/4+i*math.tau/4 for i in range(4)]:
    beam(a,[(.78,2.29),(.91,2.29),(.68,1.83),(.58,1.83)],.14)
    beam(a,[(.63,1.04),(.88,1.12),(.88,1.24),(.64,1.18),(.39,1.34),(.36,1.25)],.13)
finish('Ivory suspension frame')
for a in [math.pi/4+i*math.tau/4 for i in range(4)]:
    upper=point(a,.64,1.82); lower=point(a,.85,1.20)
    delta=g.sub(lower,upper); length=math.dist(upper,lower)
    g.tube(5,upper,delta,[(0,0),(.044,0),(.044,length),(0,length)],24)
    g.tube(0,upper,delta,[(.063,.13),(.077,.15),(.077,.49),(.063,.51)],24)
    for z in [.14,.46]: g.tube(8,upper,delta,[(.079,z),(.079,z+.027)],24)
    for p in [upper,lower]:
        tangent=(math.cos(a),0,-math.sin(a))
        rod(5,g.add(p,g.mul(tangent,-.11)),g.add(p,g.mul(tangent,.11)),.081)
        rod(2,g.add(p,g.mul(tangent,-.115)),g.add(p,g.mul(tangent,.115)),.047)
finish('Four gimbal actuators')

for a in [.15,math.pi+.15]:
    pipe(a,[(.29,2.18),(.47,2.18),(.50,2.03),(.50,1.43),(.43,1.26),(.29,1.28)],.055)
    for y in [1.47,1.89]:
        g.tube(2,point(a,.5,y),(0,1,0),[(.067,0),(.067,.055)],24)
        g.tube(8,point(a,.5,y+.01),(0,1,0),[(.069,0),(.069,.032)],24)
for a in [1.45,3.8,5.0]:
    pipe(a,[(.55,2.28),(.55,2.08),(.38,1.98),(.38,1.35),(.46,1.17),(.56,1.25),(.56,1.59)],.022)
finish('Curved feed pipes and return lines')
for a in [-.8,2.2]:
    c=point(a,.46,1.44)
    g.tube(5,c,(0,1,0),[(0,0),(.065,0),(.092,.06),(.092,.34),(.07,.39),(0,.40)],32)
    g.tube(0,c,(0,1,0),[(.094,.09),(.094,.30)],32)
    g.tube(8,c,(0,1,0),[(.096,.25),(.096,.29)],32)
    pipe(a,[(.46,1.44),(.46,1.34),(.30,1.34)],.022)
    pipe(a,[(.46,1.84),(.46,2.02),(.35,2.13)],.018)
finish('Auxiliary pumps and reservoirs')

g.radius=lambda y:.945
for i in range(8):
    a=i*math.tau/8
    g.panel(5,a,0,2.63,.16,.16,.022,.016)
    g.panel(2,a,0,2.64,.12,.135,.037,.009)
    g.panel(5,a,0,2.65,.065,.075,.043,.006)
for i in range(32):
    a=i*math.tau/32
    for y in [2.33,2.56]: g.bolt(a,0,y,.01)
    g.tube(5,point(a,.85,2.654),(0,1,0),[(.011,0),(.011,.006),(0,.006)],8)
g.radius=lambda y:.285
for i in range(12):
    for y in [1.48,1.88]: g.bolt((i+.5)*math.tau/12,0,y,.019)
finish('Latches and fasteners')

# Merge part buffers with shared materials and distinct named nodes.
doc={'asset':{'version':'2.0','generator':'Aphelion engine authoring'},'scene':0,'scenes':[{'nodes':[0]}],'nodes':[{'name':'Engine_1','children':[]}],'meshes':[],'materials':parts[0][1]['materials'],'bufferViews':[],'accessors':[],'buffers':[]}
blob=bytearray()
for name,d,b in parts:
    vo=len(doc['bufferViews']); ao=len(doc['accessors'])
    for v in d['bufferViews']: v['byteOffset']=v.get('byteOffset',0)+len(blob)
    for a in d['accessors']: a['bufferView']+=vo
    for p in d['meshes'][0]['primitives']: p['attributes']={k:v+ao for k,v in p['attributes'].items()}
    doc['nodes'][0]['children'].append(len(doc['nodes']))
    doc['nodes'].append({'name':name,'mesh':len(doc['meshes'])})
    doc['meshes']+=d['meshes']; doc['bufferViews']+=d['bufferViews']; doc['accessors']+=d['accessors']; blob+=b
    blob+=b'\0'*((-len(blob))%4)
doc['buffers']=[{'byteLength':len(blob)}]
js=json.dumps(doc,separators=(',',':')).encode(); js+=b' '*((-len(js))%4)
out=ROOT/'assets/models/engine_1/engine_1.glb'; out.parent.mkdir(parents=True,exist_ok=True)
out.write_bytes(struct.pack('<III',0x46546c67,2,28+len(js)+len(blob))+struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(blob),0x004e4942)+blob)
print(f'Saved {out}: {len(parts)} components, {len(blob):,} mesh bytes')
