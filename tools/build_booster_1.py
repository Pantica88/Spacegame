#!/usr/bin/env python3
"""Build Booster-1 from the supplied reference using Explorer-1 geometry and PBR conventions."""
import json, math, struct, tempfile
from pathlib import Path
import asset_geometry as g

ROOT = Path(__file__).resolve().parents[1]
g.radius = lambda y: .65
parts = []
def finish(name):
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp)/'part.glb'
        g.save_glb(path, name)
        raw = path.read_bytes(); size = struct.unpack_from('<I', raw, 12)[0]
        parts.append((name, json.loads(raw[20:20+size]), raw[28+size:]))
    g.mesh.clear()
def ring(mat, radius, lo, hi, thickness=.035):
    g.lathe(mat, [(radius-thickness,lo),(radius-.007,lo),(radius,lo+.007),(radius,hi-.007),(radius-.007,hi),(radius-thickness,hi),(radius-thickness,lo)],128)
# Body spans Y=.24 to 5.20; nozzle exits at zero. Slim 4:1 reference silhouette.
g.lathe(2,[(0,.25),(.643,.25),(.643,5.18),(0,5.18)],128)
finish('Continuous motor casing')
for i in range(16):
    a=i*math.tau/16+.0015; b=(i+1)*math.tau/16-.0015
    for lo,hi in [(.29,1.12),(1.125,1.59),(1.595,2.64),(2.645,3.78),(3.785,5.13)]:
        g.lathe(1 if i%7==4 else 0,[(.644,lo),(.652,lo+.006),(.652,hi-.006),(.644,hi)],8,a,b)
for a in [0,math.pi]:
    g.panel(5,a,0,2.71,.021,4.83,.006,.002)
    g.panel(0,a,0,2.71,.013,4.83,.011,.002)
finish('Segmented ivory jacket')
for lo,hi in [(.50,.69),(2.06,2.25),(4.64,4.85)]:
    ring(8,.657,lo,hi,.013)
    for y in [lo-.008,hi+.003]: ring(5,.656,y,y+.009,.012)
finish('Three amber identification bands')
for y in [.25,5.15]:
    ring(5,.673,y,y+.05)
    ring(0,.66,y+.05,y+.09)
# Closed ivory top, recessed within its metal rim, with concentric seams.
g.lathe(0,[(.63,5.23),(.62,5.255),(0,5.255)],128)
ring(5,.635,5.235,5.265,.018)
ring(1,.43,5.255,5.257,.004)
for i in range(12):
    a=i*math.tau/12
    g.lathe(1,[(.44,5.257),(.61,5.257)],1,a-.001,a+.001)
finish('End collars and sealed top cover')
for a in [math.pi/2,3*math.pi/2]:
    g.panel(2,a,0,2.75,.115,4.94,.006,.005)
    g.tube(5,g.face(a,0,.22,.055),(0,1,0),[(0,0),(.024,0),(.032,.028),(.032,4.94),(.024,4.97),(0,4.97)],24)
    for i in range(30):
        g.panel(5,a,0,.32+i*.159,.108,.015,.011,.002)
finish('Twin service rails and cable channels')
for a in [i*math.tau/4 for i in range(4)]:
    for y in [.82,2.04,4.48]:
        g.panel(5,a,0,y,.14,.23,.043,.012)
        g.panel(2,a,0,y,.112,.20,.063,.009)
        for x in [-.039,.039]:
            for dy in [-.075,.075]: g.bolt(a,x,y+dy,.066)
    for y in [.28,5.19]:
        g.panel(5,a,0,y,.15,.16,.039,.01)
        g.panel(2,a,0,y,.105,.11,.055,.008)
finish('Rail clamps and end latches')
# Dark underside and diagonal support ribs behind the four bell mouths.
g.lathe(2,[(0,.26),(.624,.26),(.624,.30),(0,.30)],96)
ring(5,.63,.245,.275,.026)
for i in range(4):
    a=math.pi/4+i*math.tau/4
    g.lathe(5,[(.08,.26),(.08,.235),(.60,.235),(.60,.26)],4,a-.035,a+.035)
g.lathe(5,[(0,.235),(.065,.235),(.065,.27),(0,.27)],32)
finish('Recessed aft plate and support ribs')
for i in range(4):
    a=i*math.tau/4
    center=(.345*math.sin(a),0,.345*math.cos(a))
    profile=[(.225,0),(.231,.014),(.212,.065),(.176,.135),(.141,.205),(.137,.27)]
    g.tube(5,center,(0,1,0),profile,64)
    g.tube(3,center,(0,1,0),[(r-.014,y) for r,y in profile][::-1],64)
    g.tube(5,center,(0,1,0),[(.211,0),(.231,0),(.231,.014)],64)
    g.tube(10,center,(0,1,0),[(.123,.27),(0,.27)],48)
    for y,r in [(.03,.226),(.14,.176),(.22,.143)]:
        g.tube(5,center,(0,1,0),[(r,y),(r,y+.012)],64)
finish('Four hollow exhaust nozzles')
for i in range(24):
    a=i*math.tau/24
    for y in [.32,5.10]: g.bolt(a,0,y,.006)
    g.tube(5,(.602*math.sin(a),5.258,.602*math.cos(a)),(0,1,0),[(.009,0),(.009,.003),(0,.003)],8)
finish('Jacket and top cover fasteners')

# Merge part buffers with shared materials and distinct named nodes.
doc={'asset':{'version':'2.0','generator':'Aphelion booster authoring'},'scene':0,'scenes':[{'nodes':[0]}],'nodes':[{'name':'Booster_1','children':[]}],'meshes':[],'materials':parts[0][1]['materials'],'bufferViews':[],'accessors':[],'buffers':[]}
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
out=ROOT/'assets/models/booster_1/booster_1.glb'; out.parent.mkdir(parents=True,exist_ok=True)
out.write_bytes(struct.pack('<III',0x46546c67,2,28+len(js)+len(blob))+struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(blob),0x004e4942)+blob)
print(f'Saved {out}: {len(parts)} components, {len(blob):,} mesh bytes')
