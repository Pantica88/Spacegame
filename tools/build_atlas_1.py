#!/usr/bin/env python3
"""Build the slim Atlas-1 ring decoupler; dimensions match the game's attachment."""
import math
from pathlib import Path
import asset_geometry as g

g.radius = lambda y: .937
T = math.tau
# Open annulus, 20 cm deep; bevelled outer skins and exposed titanium flanges.
g.lathe(2,[(.705,-.10),(.918,-.10),(.942,-.083),(.942,.083),(.918,.10),(.705,.10),(.688,.081),(.688,-.081),(.705,-.10)],128)
for lo,hi in [(-.103,-.069),(.069,.103)]:
    g.lathe(5,[(.704,lo),(.926,lo),(.943,lo+.006),(.943,hi-.006),(.926,hi),(.704,hi),(.704,lo)],128)
# White replaceable shell segments separated by narrow dark joints.
for i in range(16):
    a=i*T/16+.004; b=(i+1)*T/16-.004
    g.lathe(0 if i%5 else 1,[(.945,-.063),(.948,-.053),(.948,.053),(.945,.063)],8,a,b)
    for y in [-.042,.042]:
        for aa in [a+.022,b-.022]: g.bolt(aa,0,y,.016)
# Upper and lower attach faces have 40 counterbored bolt seats each.
for side in [-1,1]:
    for i in range(40):
        a=i*T/40
        center=(.822*math.sin(a),side*.104,.822*math.cos(a))
        g.tube(2,center,(0,side,0),[(.023,0),(.023,.002),(0,.002)],16)
        g.tube(5,center,(0,side,0),[(.016,.002),(.016,.004),(.010,.004),(.010,.002)],12)
        g.tube(10,center,(0,side,0),[(.009,.0025),(0,.0025)],6)
    g.lathe(2,[(.715,side*.104),(.731,side*.104)],128)
# Yellow diagonal stripes line the inward-facing wall of the open ring.
for i in range(24):
    a=i*T/24
    corners=[]
    for aa,y in [(a,-.065),(a+.075,-.065),(a+.175,.065),(a+.10,.065)]:
        corners.append((.686*math.sin(aa),y,.686*math.cos(aa)))
    g.quad(8,*reversed(corners))
# Four compact clamp/ejection assemblies, kept within the existing 22 cm envelope.
for angle in [T/8+i*T/4 for i in range(4)]:
    g.panel(5,angle,0,0,.13,.198,.043,.018)
    g.panel(2,angle,0,0,.108,.18,.053,.014)
    g.panel(8,angle,0,-.005,.078,.145,.060,.009)
    g.panel(2,angle,0,0,.058,.125,.066,.006)
    for x in [-.046,.046]:
        center=g.face(angle,x,-.075,.066)
        g.tube(5,center,(0,1,0),[(.014,0),(.014,.15)],16)
        for y in [-.078,.064]:
            g.tube(9,g.face(angle,x,y,.066),(0,1,0),[(.019,0),(.019,.014)],16)
    g.panel(5,angle,0,.033,.049,.071,.076,.009)
    g.bolt(angle,0,.03,.08)
    # Small shoes straddle the top and bottom flange.
    for side in [-1,1]:
        g.lathe(5,[(.88,side*.098),(.88,side*.106),(.965,side*.106),(.965,side*.080)],6,angle-.065,angle+.065)
# Paired exterior stripes and small direction arrows.
for a in [0,T/4,T/2,3*T/4]:
    for x in [-.25,.25]:
        g.polygon(8,[(x-.034,-.05),(x+.006,-.05),(x+.06,.05),(x+.020,.05)],a,.018)
    g.polygon(8,[(-.017,.032),(.017,.032),(0,.004)],a+.23,.018)
# Rear umbilical plate, two metal connector sockets and warning bar.
a=math.pi
for mat,w,h,d in [(5,.22,.117,.026),(2,.19,.093,.038)]: g.panel(mat,a,0,0,w,h,d,.013)
for x in [-.049,.049]:
    center=g.face(a,x,-.007,.043); axis=(0,0,-1)
    g.tube(9,center,axis,[(.029,0),(.029,.012),(.021,.012),(.021,0)],20)
    g.tube(10,center,axis,[(.020,.002),(0,.002)],20)
    for dx,dy in [(-.007,0),(.007,0),(0,.008)]:
        g.tube(5,g.add(center,(dx,dy,0)),axis,[(.003,.005),(.003,.009),(0,.009)],8)
g.panel(11,a,0,.051,.17,.013,.04,.002)
# Upward-facing dark orientation triangle replaces the front name stencil.
g.polygon(2,[(-.033,-.025),(.033,-.025),(0,.033)],0,.020)
g.save_glb(Path(__file__).resolve().parents[1]/'assets/models/atlas_1/atlas_1.glb','Atlas_1_Decoupler')
