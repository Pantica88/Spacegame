#!/usr/bin/env python3
"""Author packed and deployed Parachute-1 GLBs; standard library only, metres/Y up."""
import json
import math
import struct
import tempfile
from pathlib import Path
import asset_geometry as g

OUT = Path(__file__).resolve().parents[1] / 'assets/models/parachute_1'
g.materials += [('Ivory canopy cloth', '#d6d5ce', 0, .94),
                ('Ochre canopy cloth', '#dc943d', 0, .94),
                ('Stitching and cords', '#99988d', 0, .96)]
parts = []

def finish(name):
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / 'part.glb'
        g.save_glb(path, name)
        raw = path.read_bytes()
        size = struct.unpack_from('<I', raw, 12)[0]
        parts.append((name, json.loads(raw[20:20+size]), raw[28+size:]))
    g.mesh.clear()

def save(filename):
    doc = {'asset': {'version': '2.0', 'generator': 'Bluffton Parachute-1'},
           'scene': 0, 'scenes': [{'nodes': [0]}],
           'nodes': [{'name': filename.removesuffix('.glb'), 'children': []}],
           'meshes': [], 'materials': parts[0][1]['materials'],
           'bufferViews': [], 'accessors': []}
    for material in doc['materials'][12:14]:
        material['doubleSided'] = True
    blob = bytearray()
    triangles = 0
    for name, source, data in parts:
        vo, ao = len(doc['bufferViews']), len(doc['accessors'])
        for view in source['bufferViews']:
            view['byteOffset'] = view.get('byteOffset', 0) + len(blob)
        for accessor in source['accessors']:
            accessor['bufferView'] += vo
        for primitive in source['meshes'][0]['primitives']:
            triangles += source['accessors'][primitive['attributes']['POSITION']]['count'] // 3
            primitive['attributes'] = {k: v+ao for k, v in primitive['attributes'].items()}
        doc['nodes'][0]['children'].append(len(doc['nodes']))
        doc['nodes'].append({'name': name, 'mesh': len(doc['meshes'])})
        doc['meshes'] += source['meshes']
        doc['bufferViews'] += source['bufferViews']
        doc['accessors'] += source['accessors']
        blob += data
    doc['buffers'] = [{'byteLength': len(blob)}]
    js = json.dumps(doc, separators=(',', ':')).encode()
    js += b' ' * (-len(js) % 4)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / filename).write_bytes(struct.pack('<III', 0x46546c67, 2, 28+len(js)+len(blob)) +
        struct.pack('<II', len(js), 0x4e4f534a) + js + struct.pack('<II', len(blob), 0x004e4942) + blob)
    print(f'{filename}: {len(parts)} components, {triangles:,} triangles')
    parts.clear()

def line(mat, a, b, radius=.006, segments=8):
    g.tube(mat, a, g.sub(b, a), [(radius, 0), (radius, math.dist(a, b))], segments)

# Continue Explorer-1's straight ceramic taper, with a small rounded tip.
# At the game's 0.53 scale the base fits its 0.336 m docking collar.
BASE_RADIUS = .63
SLOPE = .61 / 1.92
TIP_RADIUS = .04
TIP_CENTER = (BASE_RADIUS - TIP_RADIUS * math.sqrt(1 + SLOPE**2)) / SLOPE
TIP_JOIN = TIP_CENTER + TIP_RADIUS * SLOPE / math.sqrt(1 + SLOPE**2)
HEIGHT = TIP_CENTER + TIP_RADIUS
CAP_SEAM = .85

def hull_radius(y):
    if y <= TIP_JOIN:
        return BASE_RADIUS - SLOPE * y
    return math.sqrt(max(0, TIP_RADIUS**2 - (y-TIP_CENTER)**2))

g.radius = hull_radius
# Hollow recovery well and separate ejectable cap; the seam stays open inside.
bands = [(.10,.24),(.245,.30),(.305,.847),(.853,1.37),(1.375,1.43),(1.435,HEIGHT-.003)]
for cap in [False, True]:
    lo, hi = (CAP_SEAM, HEIGHT) if cap else (.08, CAP_SEAM-.003)
    profile = [(hull_radius(y), y) for y in [lo+(hi-lo)*j/32 for j in range(33)]]
    g.lathe(2, profile)
    g.lathe(2, [(max(0,r-.022),y) for r,y in profile][::-1])
    g.lathe(5, [(hull_radius(lo)-.022,lo),(hull_radius(lo),lo)])
    if not cap:
        g.lathe(5, [(hull_radius(hi),hi),(hull_radius(hi)-.022,hi)])
    for sector in range(16):
        for lo, hi in bands:
            if (lo > CAP_SEAM) != cap: continue
            prof = [(hull_radius(y)+.003, y) for y in [lo+(hi-lo)*j/12 for j in range(13)]]
            g.lathe(8 if lo in [.245,1.375] else (1 if sector%7 == 0 else 0), prof, 6,
                    (sector-.5)*g.TAU/16+.003, (sector+.5)*g.TAU/16-.003)
            if hi < 1.5:
                for y in [lo+.012, hi-.012]:
                    g.bolt((sector-.4)*g.TAU/16, 0, y, .008)
    finish('Nose_cap' if cap else 'Lower_canister')
# Compact spool and eye sit below the new release seam.
g.lathe(2, [(0,.12),(hull_radius(.12)-.022,.12)])
g.lathe(5, [(0,.40),(.16,.40),(.16,.48),(.10,.48),(.10,.56),(.07,.56),(.07,.44)])
for i in range(8):
    a=i*g.TAU/8
    line(5,(.15*math.sin(a),.44,.15*math.cos(a)),(.52*math.sin(a),.16,.52*math.cos(a)),.018,10)
g.tube(5,(0,.64,0),(0,0,1),[(.08,-.02),(.08,.02),(.05,.02),(.05,-.02),(.08,-.02)],24)
finish('Deployment_well_and_spool')
# Low mounting ring follows the taper instead of forming a cylindrical neck.
g.lathe(5, [(0,0),(.625,0),(.63,.015),(hull_radius(.08),.08),(hull_radius(.10),.10),(.57,.10),(.57,.04)])
g.lathe(2, [(hull_radius(.06)+.002,.06),(hull_radius(.075)+.002,.075)])
for i in range(16):
    a=i*g.TAU/16
    r=hull_radius(.04)
    g.tube(2,(r*math.sin(a),.04,r*math.cos(a)),(math.sin(a),0,math.cos(a)),[(.016,0),(.016,.004)],12)
    g.tube(5,((r+.004)*math.sin(a),.04,(r+.004)*math.cos(a)),(math.sin(a),0,math.cos(a)),[(.011,0),(.011,.006),(0,.006)],6)
g.lathe(2, [(0,-.003),(.48,-.003)])
g.lathe(5, [(.23,-.006),(.23,-.025),(.34,-.025),(.34,-.006)])
finish('Mounting ring and underside socket')
# Four short release assemblies remain on the lower shell during deployment.
for a in [0,g.TAU/4,g.TAU/2,3*g.TAU/4]:
    for y,h in [(.38,.12),(.73,.17)]:
        g.panel(2,a,0,y,.12,h,.012,.012)
        g.panel(5,a,0,y,.085,h-.028,.024,.008)
        for yy in [y-h*.3,y+h*.3]:
            g.bolt(a,0,yy,.028)
    line(5,g.face(a,0,.44,.027),g.face(a,0,.66,.027),.009,12)
    line(5,g.face(a,-.04,.73,.033),g.face(a,.04,.73,.033),.012,12)
finish('Four release latches and actuator rods')
save('parachute_1.glb')

# Flight version: attachment at origin, same 8 m envelope as the existing chute.
# Twenty-four inflated gores, open apex vent, scalloped skirt, stitched panel seams.
def canopy(a, t):
    bulge = math.sin(a*24/2)**2
    radial = 4*math.sin(t)*(1+.025*bulge*math.sin(t))
    y = 5+2.1*math.cos(t)+.11*bulge*math.sin(t)-.10*bulge*math.sin(t)**8
    return (radial*math.sin(a),y,radial*math.cos(a))

start=.065
for gore in range(24):
    for ring in range(18):
        t=start+(math.pi/2-start)*ring/18
        tt=start+(math.pi/2-start)*(ring+1)/18
        for step in range(6):
            a=(gore+step/6)*g.TAU/24
            b=(gore+(step+1)/6)*g.TAU/24
            g.quad(12+(gore//2%2),canopy(a,t),canopy(a,tt),canopy(b,tt),canopy(b,t))
finish('Inflated ivory and ochre fabric gores')
for gore in range(24):
    a=gore*g.TAU/24
    for ring in range(18):
        t=start+(math.pi/2-start)*ring/18
        tt=start+(math.pi/2-start)*(ring+1)/18
        line(14,canopy(a,t),canopy(a,tt),.009,6)
for t in [start,.55,1.02,math.pi/2]:
    for i in range(144):
        line(14,canopy(i*g.TAU/144,t),canopy((i+1)*g.TAU/144,t),.008,6)
finish('Radial seams skirt hem and vent reinforcement')
for i in range(48):
    a=i*g.TAU/48
    line(14,(.055*math.sin(a),.28,.055*math.cos(a)),canopy(a,math.pi/2),.008,8)
for i in range(4):
    a=i*g.TAU/4
    line(14,(.15*math.sin(a),0,.15*math.cos(a)),(.055*math.sin(a),.28,.055*math.cos(a)),.016,10)
g.tube(5,(0,.23,0),(0,0,1),[(.065,-.014),(.065,.014),(.044,.014),(.044,-.014),(.065,-.014)],24)
finish('Forty eight suspension lines and harness')
save('parachute_1_deployed.glb')
