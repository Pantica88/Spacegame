#!/usr/bin/env python3
"""Gyro-1 reaction wheel: Atlas-sized 20 cm stack ring, authored from concept art."""
import math
from pathlib import Path
import asset_geometry as g

g.radius = lambda y: .937
g.materials[8] = ('Safety orange', '#ff850c', .35, .38)
T = math.tau
# Dark flywheel enclosure and white segmented outer casing.
g.lathe(2,[(0,-.08),(.918,-.08),(.942,-.06),(.942,.06),(.918,.08),(0,.08)],128)
for side in [-1,1]:
    g.lathe(5,[(.70,side*.08),(.70,side*.10),(.926,side*.10),(.943,side*.083),(.943,side*.069)],128)
    g.lathe(8,[(.815,side*.101),(.79,side*.101)] if side > 0 else [(.79,side*.101),(.815,side*.101)],128)
    # Recessed black rotor, central hub, orange concentric race and eight spokes.
    g.tube(10,(0,side*.08,0),(0,side,0),[(0,0),(.70,0),(.70,.004),(0,.004)],96)
    g.tube(5,(0,side*.08,0),(0,side,0),[(.28,0),(.34,.01),(.34,.02),(.28,.025),(.15,.025),(.15,0)],96)
    g.tube(8,(0,side*.08,0),(0,side,0),[(.28,.026),(.25,.026)],96)
    g.tube(2,(0,side*.08,0),(0,side,0),[(0,.02),(.14,.02),(.14,.026),(0,.026)],64)
    g.tube(9,(0,side*.08,0),(0,side,0),[(.035,.027),(.047,.027)],24)
    for i in range(8):
        a=i*T/8
        profile = [(.38,side*.085),(.38,side*.098),(.74,side*.098),(.74,side*.085)]
        g.lathe(5,list(reversed(profile)) if side > 0 else profile,4,a-.045,a+.045)
        for r in [.42,.70]:
            g.tube(9,(r*math.sin(a),side*.10,r*math.cos(a)),(0,side,0),[(.014,0),(.014,.003),(0,.003)],8)
for i in range(16):
    a=i*T/16+.012; b=(i+1)*T/16-.012
    g.lathe(0 if i%4 else 1,[(.942,-.062),(.948,-.05),(.948,.05),(.942,.062)],8,a,b)
    for y in [-.038,.038]:
        for aa in [a+.028,b-.028]: g.bolt(aa,0,y,.014)
# Four black control boxes with bright orange directional indicators.
for a in [i*T/4 for i in range(4)]:
    g.panel(5,a,0,0,.22,.18,.029,.014)
    g.panel(2,a,0,0,.185,.15,.042,.01)
    g.panel(10,a,0,0,.12,.115,.048,.008)
    g.polygon(8,[(0,-.03),(.043,.039),(-.043,.039)],a,.051)
    g.panel(8,a,0,-.046,.045,.01,.051,.002)
    for x in [-.078,.078]:
        for y in [-.055,.055]: g.bolt(a,x,y,.05)
    for x in [-.14,.14]: g.panel(8,a,x,0,.016,.13,.024,.003)
g.save_glb(Path(__file__).resolve().parents[1]/'assets/models/gyro_1/gyro_1.glb','Gyro_1_ReactionWheel')
