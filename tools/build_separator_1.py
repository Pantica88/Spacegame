#!/usr/bin/env python3
"""Build Separator-1 from the supplied reference using Explorer-1 geometry and PBR conventions."""
import json, math, struct, tempfile
from pathlib import Path
import asset_geometry as g

ROOT = Path(__file__).resolve().parents[1]
g.radius = lambda y: .65
parts = []
def finish(name):
    # Half-height separator; correct normals for the nonuniform authoring scale.
    for mat, vertices in g.mesh.items():
        g.mesh[mat] = [(v[0],v[1]*.5,v[2],*g.norm((v[3],v[4]*2,v[5])),v[6],v[7]) for v in vertices]
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp)/'part.glb'
        g.save_glb(path, name)
        raw = path.read_bytes(); size = struct.unpack_from('<I', raw, 12)[0]
        parts.append((name, json.loads(raw[20:20+size]), raw[28+size:]))
    g.mesh.clear()
# Chamfered solid plates, with geometry batched into inspectable assemblies.
def plate(mat,x,y,z,w,h,d,b=.012):
    b=min(b,w/5,h/5,d/3)
    outline=g.outline(x,y,w,h,b)
    inset=g.outline(x,y,w-2*b,h-2*b,b*.5)
    rings=[[(px,py,zz) for px,py in shape] for shape,zz in [(inset,z-d/2),(outline,z-d/2+b),(outline,z+d/2-b),(inset,z+d/2)]]
    for first,second in zip(rings,rings[1:]):
        for i in range(len(first)):
            j=(i+1)%len(first);g.quad(mat,first[i],first[j],second[j],second[i])
    for ring in [rings[0][::-1],rings[-1]]:
        center=(x,y,ring[0][2])
        for i in range(len(ring)):g.tri(mat,center,ring[i],ring[(i+1)%len(ring)])
def bolt(x,y,z,axis=(0,0,1),r=.018):
    g.tube(2,(x,y,z),axis,[(r*1.25,0),(r*1.25,.004)],16)
    g.tube(5,(x,y,z),axis,[(r,.004),(r,.011),(r*.5,.011),(r*.5,.006)],6)
    g.tube(10,(x,y,z),axis,[(r*.5,.006),(0,.006)],6)
# Centered origin, Y up, front faces +Z; 2.8 m long.
plate(2,0,0,-.065,.31,2.58,.13)
plate(5,-.19,0,.025,.085,2.51,.15)
plate(5,.19,0,.025,.085,2.51,.15)
for x in [-.195,.195]:plate(2,x,0,.109,.033,2.21,.018,.003)
plate(2,0,0,.02,.24,2.30,.04)
finish('Load bearing frame and recessed channel')
# Alternating black/yellow parallelograms clipped to the warning-strip bounds.
plate(10,0,0,.047,.145,2.29,.014,.003)
def clip(poly,axis,bound,greater):
    result=[]
    for a,b in zip(poly,poly[1:]+poly[:1]):
        ia=a[axis]>=bound if greater else a[axis]<=bound
        ib=b[axis]>=bound if greater else b[axis]<=bound
        if ia:result.append(a)
        if ia!=ib:
            t=(bound-a[axis])/(b[axis]-a[axis]);result.append(tuple(a[k]+t*(b[k]-a[k]) for k in range(2)))
    return result
for sign in [-1,1]:
    for i in range(-5,6):
        y=i*.25
        poly=[(-.070,y-.08),(.070,y+.045),(.070,y+.17),(-.070,y+.045)]
        poly=clip(clip(poly,1,-1.13,True),1,1.13,False)
        if len(poly)<3:continue
        verts=[(x,yy,.056 if sign==1 else -.132) for x,yy in poly]
        if sign<0:verts.reverse()
        for j in range(1,len(verts)-1):g.tri(11,verts[0],verts[j],verts[j+1])
finish('Yellow diagonal hazard markings')
# Two sliding rods and regularly spaced cross ties in the channel.
for x in [-.115,.115]:
    g.tube(5,(x,-1.27,.095),(0,1,0),[(0,0),(.016,0),(.016,2.54),(0,2.54)],24)
    for y in [-.93,-.52,0,.52,.93]:plate(2,x,y,.10,.052,.055,.052,.005)
for y in [-1.02,-.76,-.5,-.24,.24,.5,.76,1.02]:
    plate(5,0,y,-.145,.28,.026,.022,.004)
finish('Twin guide rods and locking ties')
for y in [-1.25,1.25]:
    plate(5,0,y,.04,.48,.30,.29,.025)
    plate(2,0,y,.199,.37,.21,.035,.009)
    plate(5,0,y,.226,.31,.17,.032,.012)
    plate(11,0,y+(-.115 if y<0 else .115),.188,.30,.027,.012,.004)
    for x in [-.185,.185]:
        plate(5,x,y,.21,.055,.235,.035,.006)
        bolt(x,y-.075,.229,r=.012);bolt(x,y+.075,.229,r=.012)
finish('Reinforced end clamp blocks')
# Mounting feet extend behind the frame to meet the rocket body.
for y in [-1.22,1.22]:
    for x in [-.20,.20]:
        plate(5,x,y,-.23,.19,.30,.40,.024)
        plate(2,x,y,-.438,.15,.245,.018,.005)
        for dy in [-.075,.075]:
            bolt(x,y+dy,-.451,(0,0,-1),.020)
            bolt(x+(.10 if x>0 else -.10),y+dy,-.25,(1 if x>0 else -1,0,0),.019)
finish('Paired radial mounting feet')
# Mirrored release mechanisms on BOTH lateral sides, with ivory indicator slots.
for sign in [-1,1]:
    x=sign*.265
    plate(2,x,0,.032,.095,.58,.17,.012)
    plate(5,x,0,.13,.115,.49,.15,.018)
    plate(2,x,0,.211,.065,.37,.018,.006)
    plate(0,x,0,.223,.020,.31,.010,.004)
    plate(11,x,-.19,.213,.045,.024,.009,.003)
    for y in [-.205,.205]:bolt(x,y,.21,r=.011)
    for y in [-.39,.39]:
        plate(5,sign*.225,y,.052,.047,.14,.08,.007)
        g.tube(5,(sign*.246,min(y,0),.063),(0,1,0),[(.011,0),(.011,abs(y))],16)
finish('Left and right release housings')
for x in [-.19,.19]:
    for y in [-1.05,-.78,-.39,.39,.78,1.05]:bolt(x,y,.112,r=.010)
for y in [-1.25,1.25]:
    for x in [-.09,.09]:bolt(x,y,.245,r=.017)
finish('Recessed fasteners')

# Merge part buffers with shared materials and distinct named nodes.
doc={'asset':{'version':'2.0','generator':'Aphelion separator authoring'},'scene':0,'scenes':[{'nodes':[0]}],'nodes':[{'name':'Separator_1','children':[]}],'meshes':[],'materials':parts[0][1]['materials'],'bufferViews':[],'accessors':[],'buffers':[]}
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
out=ROOT/'assets/models/separator_1/separator_1.glb'; out.parent.mkdir(parents=True,exist_ok=True)
out.write_bytes(struct.pack('<III',0x46546c67,2,28+len(js)+len(blob))+struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(blob),0x004e4942)+blob)
print(f'Saved {out}: {len(parts)} components, {len(blob):,} mesh bytes')
