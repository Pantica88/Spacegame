#!/usr/bin/env python3
"""Sparrow reference engine: compact graphite bell, exposed plumbing, Kestrel mount."""
import json
import math
import struct
import tempfile
from pathlib import Path
import asset_geometry as g

OUT = Path(__file__).resolve().parents[1] / 'assets/models/sparrow_1'
g.materials += [
    ('Graphite nozzle composite', '#303437', .28, .56),
    ('Dark chamber alloy', '#252b2e', .72, .38),
    ('Brushed nickel hardware', '#a6aaa8', .85, .30),
    ('Copper cooling liner', '#b77339', .80, .35),
    ('Blue oxidizer pipe', '#326582', .65, .30),
    ('Braided hose', '#171e22', .28, .78),
]
parts = []


def finish(name):
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / 'part.glb'
        g.save_glb(path, name)
        raw = path.read_bytes()
        size = struct.unpack_from('<I', raw, 12)[0]
        parts.append((name, json.loads(raw[20:20+size]), raw[28+size:]))
    g.mesh.clear()


def point(a, r, y):
    return (r*math.sin(a), y, r*math.cos(a))


def ring(mat, r, y, h=.02, t=.015):
    g.lathe(mat, [(r-t,y),(r,y),(r,y+h),(r-t,y+h),(r-t,y)])


def rod(mat, a, b, r):
    g.tube(mat, a, g.sub(b,a), [(0,0),(r,0),(r,math.dist(a,b)),(0,math.dist(a,b))], 12)


def pipe(mat, a, coords, r=.025):
    """Continuous pipe with rounded elbows, in a radial plane."""
    coords = [point(a,x,y) for x,y in coords]
    path = [coords[0]]
    for prev, c, nxt in zip(coords, coords[1:], coords[2:]):
        entry = g.add(c, g.mul(g.sub(prev,c), .25))
        end = g.add(c, g.mul(g.sub(nxt,c), .25))
        path.append(entry)
        for k in range(1,9):
            t = k/8
            path.append(g.add(g.add(g.mul(entry,(1-t)**2),g.mul(c,2*t*(1-t))),g.mul(end,t*t)))
    path.append(coords[-1])
    normal = (math.cos(a),0,-math.sin(a))
    rings = []
    for i,p in enumerate(path):
        tangent = g.norm(g.sub(path[min(i+1,len(path)-1)],path[max(0,i-1)]))
        side = g.norm(g.cross(tangent,normal))
        rings.append([g.add(p,g.add(g.mul(normal,r*math.cos(j*g.TAU/12)),g.mul(side,r*math.sin(j*g.TAU/12)))) for j in range(12)])
    for first,second in zip(rings,rings[1:]):
        for j in range(12):
            g.quad(mat,first[j],first[(j+1)%12],second[(j+1)%12],second[j])
    return path


# Same 0.96 m outer mounting radius and 0.85 m bolt circle as Kestrel.
# The compact engine hangs from a shallow adapter rather than a large feed skirt.
g.lathe(13, [(0,1.81),(.90,1.81),(.94,1.83),(.94,1.98),(.90,2.0),(0,2.0)], 128)
for i in range(16):
    a=i*g.TAU/16+.004; b=(i+1)*g.TAU/16-.004
    g.lathe(0 if i%4 else 1,[(.942,1.85),(.949,1.86),(.949,1.955)],8,a,b)
    g.lathe(8,[(.951,1.87),(.951,1.90)],8,a,b)
ring(14,.96,1.825,.025)
ring(14,.96,1.965,.02)
g.lathe(14,[(.78,1.982),(.78,1.993),(.73,2.0),(.73,1.982)])
for i in range(32):
    a=i*g.TAU/32
    g.tube(14,point(a,.85,1.986),(0,1,0),[(.011,0),(.011,.01),(0,.01)],8)
finish('Standard diameter mounting adapter')

# Smooth, thin-wall graphite bell with copper inner wall and rolled bronze lip.
bell=[(.48,0),(.478,.025),(.46,.14),(.431,.28),(.391,.42),(.343,.55),(.285,.68),(.224,.79),(.18,.84),(.17,.88)]
g.lathe(12,bell,128)
g.lathe(15,[(r-.018,y) for r,y in bell][::-1],128)
ring(15,.486,0,.019,.028)
ring(14,.188,.837,.034,.021)
ring(8,.185,.859,.018,.012)
g.lathe(13,[(.17,.87),(.17,.93),(.13,.93),(.13,.88)],96)
g.lathe(10,[(.152,.88),(.105,1.03),(0,1.03)],96)
finish('Graphite bell and copper liner')

# Narrow modular chamber and valve stack, with machined clamp bands.
g.lathe(13,[(0,.90),(.175,.90),(.20,.95),(.20,1.26),(.185,1.31),(.185,1.40),(.225,1.43),(.225,1.70),(.21,1.75),(0,1.75)])
for y,r in [(.94,.213),(1.04,.211),(1.28,.21),(1.41,.238),(1.62,.243),(1.71,.238)]:
    ring(14,r,y,.026)
    ring(13,r+.002,y+.01,.006,.009)
for y in [1.09+j*.019 for j in range(9)]:
    ring(5,.202,y,.004,.006)
g.radius=lambda y:.201 if y<1.4 else .226
for a in [0,math.pi]:
    g.panel(14,a,0,1.15,.16,.21,.006,.025)
    g.panel(13,a,0,1.15,.144,.192,.011,.018)
    for x in [-.054,.054]:
        for y in [1.08,1.22]: g.bolt(a,x,y,.014)
for i in range(8):
    a=i*g.TAU/8
    for y in [.97,1.30,1.45,1.65]: g.bolt(a,0,y,.024)
finish('Combustion chamber and avionics stack')

# Open load path and four compact gimbal pivots under the standard adapter.
for i in range(4):
    a=(i+.5)*g.TAU/4
    rod(14,point(a,.70,1.815),point(a,.245,1.65),.033)
    rod(13,point(a,.70,1.805),point(a,.27,1.48),.025)
    tangent=(math.cos(a),0,-math.sin(a))
    p=point(a,.247,1.61)
    g.tube(14,g.add(p,g.mul(tangent,-.055)),tangent,[(0,0),(.048,0),(.048,.11),(0,.11)],24)
    rod(5,point(a,.25,1.59),point(a,.22,1.30),.018)
finish('Adapter supports and gimbal pivots')

# Reference-inspired oxidizer loop and fuel return, with silver couplings.
for a,mat,coords,r in [
    (-.9,16,[(.21,1.64),(.35,1.64),(.38,1.54),(.38,1.16),(.31,1.06),(.20,1.06)],.036),
    (1.25,15,[(.22,1.58),(.31,1.58),(.32,1.43),(.32,1.02),(.27,.95),(.19,.95)],.026),
    (2.7,14,[(.22,1.52),(.30,1.47),(.30,1.07),(.23,1.01)],.023),
]:
    pipe(mat,a,coords,r)
    rr=.38 if mat==16 else (.32 if mat==15 else .30)
    for y in [1.19,1.44]:
        g.tube(14,point(a,rr,y),(0,1,0),[(r+.009,0),(r+.009,.044)],24)
        g.tube(13,point(a,rr,y+.015),(0,1,0),[(r+.010,0),(r+.010,.008)],24)
finish('Oxidizer and fuel plumbing')

# Flexible ribbed harness on the rear, two valve cans, fastened clamp bridges.
a=-2.5
path=pipe(17,a,[(.21,1.65),(.32,1.65),(.35,1.48),(.35,1.15),(.27,1.04),(.20,1.04)],.032)
for first,second in zip(path,path[1:]):
    length=math.dist(first,second)
    for j in range(max(1,int(length/.012))):
        center=g.add(first,g.mul(g.sub(second,first),j/max(1,int(length/.012))))
        g.tube(5,center,g.sub(second,first),[(.033,0),(.033,.003)],12)
for a in [.4,math.pi+.4]:
    c=point(a,.285,1.44)
    g.tube(13,c,(0,1,0),[(0,0),(.052,0),(.061,.02),(.061,.15),(.046,.18),(0,.18)],32)
    for y in [0,.13]: g.tube(14,g.add(c,(0,y,0)),(0,1,0),[(.063,0),(.063,.022)],24)
    pipe(14,a,[(.285,1.45),(.285,1.37),(.20,1.37)],.017)
g.radius=lambda y:.226
for a in [i*g.TAU/4 for i in range(4)]:
    g.panel(14,a,0,1.60,.054,.23,.014,.009)
    for y in [1.50,1.69]: g.bolt(a,0,y,.027)
finish('Valves braided hose and clamp hardware')

# Small geometric Sparrow chevron, kept separate for inspection.
def nozzle_radius(y):
    for (r,lo),(rr,hi) in zip(bell,bell[1:]):
        if lo<=y<=hi: return r+(rr-r)*(y-lo)/(hi-lo)
    return .48
g.radius=nozzle_radius
g.polygon(14,[(-.087,.33),(-.059,.33),(0,.43),(0,.478)],0,.014)
g.polygon(14,[(0,.43),(.059,.33),(.087,.33),(0,.478)],0,.014)
g.polygon(8,[(-.018,.337),(.018,.337),(0,.368)],0,.014)
g.panel(14,0,0,.26,.095,.012,.008,.002)
finish('Sparrow nozzle insignia')

# Shared materials and individually inspectable components in a single GLB.
doc={'asset':{'version':'2.0','generator':'Aphelion Sparrow authoring'},'scene':0,'scenes':[{'nodes':[0]}],
     'nodes':[{'name':'Sparrow_1','children':[]}],'meshes':[],'materials':parts[0][1]['materials'],
     'bufferViews':[],'accessors':[]}
blob=bytearray()
triangles=0
for name,d,b in parts:
    vo=len(doc['bufferViews']); ao=len(doc['accessors'])
    for v in d['bufferViews']: v['byteOffset']=v.get('byteOffset',0)+len(blob)
    for accessor in d['accessors']: accessor['bufferView']+=vo
    for primitive in d['meshes'][0]['primitives']:
        triangles+=d['accessors'][primitive['attributes']['POSITION']]['count']//3
        primitive['attributes']={k:v+ao for k,v in primitive['attributes'].items()}
    doc['nodes'][0]['children'].append(len(doc['nodes']))
    doc['nodes'].append({'name':name,'mesh':len(doc['meshes'])})
    doc['meshes']+=d['meshes']; doc['bufferViews']+=d['bufferViews']; doc['accessors']+=d['accessors']; blob+=b
doc['buffers']=[{'byteLength':len(blob)}]
js=json.dumps(doc,separators=(',',':')).encode(); js+=b' '*(-len(js)%4)
OUT.mkdir(parents=True,exist_ok=True)
(OUT/'sparrow_1.glb').write_bytes(struct.pack('<III',0x46546c67,2,28+len(js)+len(blob))+
    struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(blob),0x004e4942)+blob)
print(f'Sparrow-1: {len(parts)} components, {triangles:,} triangles')
