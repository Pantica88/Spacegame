#!/usr/bin/env python3
"""Build the reference fuel tank using Explorer-1 geometry and PBR conventions."""
import json, math, struct, tempfile
from pathlib import Path
import asset_geometry as g

ROOT = Path(__file__).resolve().parents[1]
g.radius = lambda y: .91
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
# 1.82 m diameter, 4.70 m tall. Centered origin, vertical +Y axis.
g.lathe(2,[(0,-2.22),(.902,-2.22),(.902,2.22),(0,2.22)],128)
finish('Pressure vessel')
for i in range(16):
    a=i*math.tau/16+.002; b=(i+1)*math.tau/16-.002
    for lo,hi in [(-2.20,-1.58),(-1.574,-.20),(-.194,-.15),(-.144,1.54),(1.546,2.20)]:
        g.lathe(0 if i%5 else 1,[(.903,lo),(.912,lo+.012),(.912,hi-.012),(.903,hi)],8,a,b)
# Raised longitudinal joining strips on the front and back of the jacket.
for a in [0, math.pi]:
    g.panel(5,a,0,0,.028,4.39,.006,.003)
    g.panel(0,a,0,0,.017,4.38,.014,.002)
finish('Segmented ivory shell')
for side in [-1,1]:
    lo,hi = sorted([side*1.78,side*2.04])
    ring(8,.917,lo,hi,.014)
    for y in [lo-.009,hi+.009]: ring(5,.916,y-.006,y+.006,.014)
finish('Amber identification bands')
for side in [-1,1]:
    ring(5,.927,side*2.22-.035,side*2.22+.035)
    ring(0,.917,side*2.15-.055,side*2.15+.055)
    ring(5,.862,side*2.30-.04,side*2.30+.04)
    ring(2,.84,side*2.34-.009,side*2.34+.009)
finish('Machined end collars')
g.lathe(2,[(0,2.31),(.82,2.31),(.82,2.345),(.78,2.35),(0,2.35)],128)
ring(5,.80,2.346,2.358,.018)
# Upward-facing inset cover and a narrow engraved perimeter.
g.lathe(2,[(.775,2.349),(.775,2.354),(.64,2.354),(.64,2.348),(0,2.348)],128)
ring(5,.646,2.348,2.354,.009)
finish('Recessed top lid')
# Underside has an actual open connector bore with a recessed dark interior.
g.lathe(2,[(.23,-2.22),(.23,-2.32),(.82,-2.32),(.82,-2.22),(.23,-2.22)],128)
g.lathe(5,[(.23,-2.29),(.23,-2.37),(.44,-2.37),(.46,-2.35),(.46,-2.32),(.23,-2.29)],96)
g.lathe(10,[(0,-2.18),(.23,-2.18),(.23,-2.36)],64)
for i in range(4):
    a=i*math.tau/4
    g.lathe(5,[(.44,-2.32),(.44,-2.345),(.81,-2.345),(.81,-2.32)],4,a-.044,a+.044)
    g.tube(2,(.69*math.sin(a),-2.346,.69*math.cos(a)),(0,-1,0),[(.018,0),(.018,.004),(0,.004)],12)
finish('Bottom manifold and radial ribs')
for a in [math.pi/2,3*math.pi/2]:
    g.tube(5,g.face(a,0,-2.09,.042),(0,1,0),[(0,0),(.022,0),(.031,.028),(.031,4.15),(.022,4.18),(0,4.18)],24)
finish('Twin service rails')
for a in [i*math.tau/4 for i in range(4)]:
    for y in [-1.59,1.59]:
        g.panel(5,a,0,y,.135,.39,.047,.017)
        g.panel(2,a,0,y,.113,.35,.065,.011)
        g.panel(5,a,0,y,.11,.024,.069,.004)
        for dy in [-.13,.13]: g.bolt(a,0,y+dy,.071)
    for y in [-2.25,2.25]:
        g.panel(5,a,0,y,.16,.17,.052,.012)
        g.panel(2,a,0,y,.122,.127,.064,.01)
        g.panel(5,a,0,y,.075,.074,.073,.008)
finish('Side clamps and end latches')
for side in [-1,1]:
    for i in range(32):
        a=i*math.tau/32
        center=(.878*math.sin(a),side*2.261,.878*math.cos(a))
        g.tube(2,center,(0,side,0),[(.018,0),(.018,.003),(0,.003)],12)
        g.tube(5,center,(0,side,0),[(.012,.003),(.012,.007),(0,.007)],6)
    for i in range(8):
        a=i*math.tau/8
        g.tube(5,(.385*math.sin(a),-2.372,.385*math.cos(a)),(0,-1,0),[(.021,0),(.021,.006),(0,.006)],8)
for i in range(16):
    for y in [-2.12,2.12]: g.bolt((i+.5)*math.tau/16,0,y,.011)
# Top cover screws, and inset rectangular sockets around both rim walls.
for i in range(12):
    a=i*math.tau/12
    g.tube(5,(.73*math.sin(a),2.355,.73*math.cos(a)),(0,1,0),[(.013,0),(.013,.004),(0,.004)],8)
for i in range(32):
    for y in [-2.22,2.22]:
        g.panel(2,i*math.tau/32,0,y,.028,.022,.019,.004)
finish('Recessed bolts and fasteners')
# Merge part buffers with shared materials and distinct named nodes.
doc={'asset':{'version':'2.0','generator':'Aphelion canister authoring'},'scene':0,'scenes':[{'nodes':[0]}],'nodes':[{'name':'Canister_1','children':[]}],'meshes':[],'materials':parts[0][1]['materials'],'bufferViews':[],'accessors':[],'buffers':[]}
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
out=ROOT/'assets/models/canister_1/canister_1.glb'; out.parent.mkdir(parents=True,exist_ok=True)
out.write_bytes(struct.pack('<III',0x46546c67,2,28+len(js)+len(blob))+struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(blob),0x004e4942)+blob)
print(f'Saved {out}: {len(parts)} components, {len(blob):,} mesh bytes')
