#!/usr/bin/env python3
"""Author reusable, material-batched launch facility GLBs and their Godot scene.
Metres, Y up. Deck datum is zero; painted surfaces have explicit clearance.
Run from any directory with Python 3; no third-party dependencies.
"""
import math
from pathlib import Path
import asset_geometry as g

OUT = Path(__file__).resolve().parents[1] / 'assets/models/launch_site'
g.materials = [
    ('Concrete', '#8d9998', 0, .95), ('Concrete joints', '#536462', 0, .95),
    ('Graphite', '#243335', .3, .75), ('Service teal', '#326b70', .5, .55),
    ('Ivory', '#dddcd0', .15, .65), ('Steel', '#819294', .75, .4),
    ('Glass', '#254a60', .55, .2), ('Safety amber', '#efb34b', .1, .65),
    ('Lamp lens', '#c5eee4', .1, .2)]
assets = []

def box(mat, p, size):
    x,y,z=p; a,b,c=(v/2 for v in size)
    v=[(x+dx*a,y+dy*b,z+dz*c) for dx,dy,dz in
       [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
    for face in [(0,3,2,1),(4,5,6,7),(0,4,7,3),(1,2,6,5),(3,7,6,2),(0,1,5,4)]:
        g.quad(mat,*(v[i] for i in face))

def beam(mat, a, b, r=.09):
    axis=g.sub(b,a); length=math.sqrt(sum(v*v for v in axis))
    g.tube(mat,a,axis,[(0,0),(r,0),(r,length),(0,length)],8)

def cylinder(mat, p, r, height):
    g.tube(mat,p,(0,1,0),[(0,0),(r,0),(r,height),(0,height)],32)

def save(name):
    g.save_glb(OUT / (name+'.glb'), name)
    assets.append(name)
    g.mesh.clear()

# One contiguous slab: no overlapping pad discs. A 24 m clear ignition zone.
box(0,(0,-1.4925,0),(120,3.015,120))
for x in range(-50,60,10):
    box(1,(x,.019,0),(.025,.006,120))
    box(1,(0,.019,x),(120,.006,.025))
# Thin markings, not a second deck. Center remains on the physics datum.
for i in range(96):
    a=i*math.tau/96; b=(i+1)*math.tau/96
    g.quad(7,(18*math.sin(a),.03,18*math.cos(a)),(18*math.sin(b),.03,18*math.cos(b)),
           (18.3*math.sin(b),.03,18.3*math.cos(b)),(18.3*math.sin(a),.03,18.3*math.cos(a)))
for x in [-59,59]:
    box(7,(x,.03,0),(.25,.015,118))
    box(7,(0,.03,x),(118,.015,.25))
# Refractory launch center and flush exhaust channels.
box(2,(0,.024,0),(24,.012,24))
for x in [-14,14]:
    box(2,(x,.027,-30),(2,.018,34))
    for z in range(-46,-13,1): box(5,(x,.045,z),(2,.02,.10))
for x in [-11.5,11.5]:
    for z in range(-11,12,2): box(7,(x,.038,z),(.6,.015,1))
save('launch_foundation')

# Offset tower: four legs, diagonal bracing, ladder and guarded galleries.
box(0,(0,.25,0),(9,.5,9))
for x in [-3,3]:
    for z in [-3,3]: box(3,(x,19,z),(.36,38,.36))
for y in range(3,38,6):
    box(5,(0,y,0),(7,.22,7))
    for z in [-3,3]:
        beam(3,(-3,y,z),(3,y+6,z),.12)
        beam(3,(3,y,z),(-3,y+6,z),.12)
    for x in [-3,3]: beam(3,(x,y,-3),(x,y+6,3),.12)
    for z in [-3.4,3.4]:
        beam(7,(-3.4,y+1.1,z),(3.4,y+1.1,z),.045)
        for x in [-3.4,0,3.4]: beam(7,(x,y,z),(x,y+1.1,z),.045)
for y in range(76): beam(5,(-.5,y*.5,3.65),(.5,y*.5,3.65),.04)
for x in [-.6,.6]: beam(5,(x,0,3.65),(x,38,3.65),.06)
box(4,(0,38.3,0),(8,.6,8))
beam(5,(0,38.6,0),(0,44,0),.08)
cylinder(7,(0,44,0),.18,.35)
# Parked service booms do not cross the launch envelope.
for y in [15,27]:
    box(3,(5,y,0),(4,.4,1.6))
    beam(5,(3,y+3,0),(7,y,0),.06)
save('service_tower')

# Control bunker with roof equipment, doors, window frames, and sunshades.
box(0,(0,.25,0),(20,.5,14))
box(4,(0,3,0),(18,5.5,12))
box(3,(0,5.9,0),(19,.4,13))
for x in [-6,-3,0,3,6]:
    box(2,(x,3.7,6.02),(2.5,1.6,.12))
    box(6,(x,3.7,6.1),(2.25,1.35,.06))
box(3,(0,4.8,6.7),(17,.15,1.6))
box(2,(7,1.6,-6.02),(1.5,2.7,.12))
for x in [-4,3]:
    box(5,(x,6.6,0),(3,1,2))
    for z in [-.7,-.35,0,.35,.7]: box(2,(x,7.11,z),(2.6,.04,.12))
save('control_building')

# Bunded utility tank, domed cap, bands, valve and external pipework.
box(0,(0,.2,0),(9,.4,9))
for x in [-4,4]:
    box(0,(x,.8,0),(.25,1.2,8))
    box(0,(0,.8,x),(8,1.2,.25))
cylinder(4,(0,.4,0),2.6,8)
g.tube(4,(0,8.4,0),(0,1,0),[(2.6,0),(2.4,.6),(1.6,1.1),(0,1.3)],32)
for y in [1,4,7.8]: cylinder(3,(0,y,0),2.66,.18)
beam(5,(2.9,.5,0),(2.9,8,0),.12)
beam(5,(2.9,1,0),(4.3,1,0),.12)
cylinder(7,(3.5,1,0),.3,.08)
save('utility_tank')

box(0,(0,.15,0),(1.8,.3,1.8))
beam(5,(0,.3,0),(0,10,0),.13)
box(3,(0,10,0),(2.8,.3,.7))
for x in [-.9,0,.9]: box(8,(x,9.85,.25),(.7,.2,.7))
save('floodlight')

# Road terminates inside the graded footprint, with a marked gate approach.
box(2,(0,-.12,0),(12,.27,60))
for x in [-5.5,5.5]: box(4,(x,.035,0),(.15,.015,60))
for z in range(-27,30,6): box(7,(0,.035,z),(.15,.015,3))
save('access_road')

box(0,(0,.2,0),(5,.4,5))
cylinder(5,(0,.4,0),.5,4)
g.tube(4,(0,5,0),(0,.8,.6),[(0,-.5),(.8,-.4),(1.8,0),(2.5,.7),(2.55,.8),(1.8,.1),(.8,-.3),(0,-.4)],48)
beam(5,(0,5,0),(0,7,1.5),.05)
save('tracking_dish')

box(0,(0,.4,0),(6,.8,1))
for x in range(-2,3): box(7,(x,.82,0),(.5,.04,.8))
save('blast_barrier')

placements=[('launch_foundation',(0,0,0)),('service_tower',(-32,0,-25)),
 ('control_building',(39,0,32)),('access_road',(0,0,90)),('tracking_dish',(39,0,-36))]
placements += [('utility_tank',(-44,0,z)) for z in [8,20,32]]
placements += [('floodlight',(x,0,z)) for x in [-54,54] for z in [-52,0,52]]
placements += [('blast_barrier',(x,0,-52)) for x in range(-18,19,6)]
lines=['[gd_scene load_steps=%d format=3]'%(len(assets)+1),'']
for i,name in enumerate(assets): lines += ['[ext_resource type="PackedScene" path="res://assets/models/launch_site/%s.glb" id="%d"]'%(name,i+1)]
lines += ['','[node name="LaunchComplex" type="Node3D"]']
for index,(name,p) in enumerate(placements):
    lines += ['','[node name="%s_%d" parent="." instance=ExtResource("%d")]'%(name,index,assets.index(name)+1),
              'position = Vector3(%s)'%(', '.join(str(v) for v in p))]
(OUT/'launch_complex.tscn').write_text('\n'.join(lines)+'\n')
