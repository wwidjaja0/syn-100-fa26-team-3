"""Building blocks for the procedural props in generate_assets.py.

Model collects named, flat-coloured parts (boxes, cylinders, cones, rods, rings, frames) into one
trimesh scene and exports it as a GLB. Coordinates are metres, Z up, the front faces -Y.
Every part becomes its own named node with its own material, called mat_<part>_<n>; the Blender
scene builders and the Godot game find parts and materials by these names.

PAL is the prop palette: pick part colours from it by name, e.g. m.box('lid', ..., 'steel').
"""
from pathlib import Path
import math, re, json
import numpy as np
import trimesh
from trimesh.transformations import rotation_matrix

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'assets'
OUT.mkdir(exist_ok=True)

PAL = {
 'walnut': '#74442e', 'walnut_light':'#945b39', 'wood':'#aa7349', 'wood_light':'#bd8a58',
 'wood_edge':'#533426', 'wood_dark':'#65412f','wood_darkest':'#39291f','wood_pale':'#d1a36d',
 'oak':'#bb8659','oak_alt':'#a87649','wood_gap':'#66412e',
 'steel':'#4f585b', 'steel_light':'#879195', 'steel_dark':'#323a3f',
 'graphite':'#313b3e', 'charcoal':'#262e30', 'metal':'#6c7679', 'silver':'#b2b4ad',
 'brass':'#bd9856', 'brass_shadow':'#816740',
 'screen':'#77b3b0','screen_dark':'#28525a','screen_glow':'#b7e3b9',
 'olive':'#617664', 'olive_light':'#91a18a', 'olive_dark':'#415549',
 'canvas':'#c2ac82','canvas_light':'#dbc59a','canvas_dark':'#968669',
 'cream':'#c9bba0','cream_shadow':'#b5a78a','off_white':'#e2d7be',
 'glass':'#c2d8cf','aqua':'#82b5b4', 'navy':'#354c5e',
 'red':'#a85144', 'red_light':'#c77761', 'yellow':'#e4c171',
 'orange':'#d69c54','black':'#232b30','forest':'#465b50',
}

def rgba(color):
    if isinstance(color, (list,tuple,np.ndarray)):
        return list(color)
    h=PAL.get(color, color).lstrip('#')
    return [int(h[i:i+2],16) for i in (0,2,4)] + [255]

class Model:
    def __init__(self,title):
        self.title=title
        self.scene=trimesh.Scene()
        self.seq=0
    def add(self, mesh, name, color, metallic=0.0):
        self.seq += 1
        mesh.visual=trimesh.visual.TextureVisuals(material=trimesh.visual.material.PBRMaterial(
            name=f'mat_{name}_{self.seq}', baseColorFactor=rgba(color), metallicFactor=metallic, roughnessFactor=.86))
        slug=re.sub(r'[^a-zA-Z0-9_]+','_',name).strip('_')
        self.scene.add_geometry(mesh,geom_name=f'{slug}_{self.seq:04}', node_name=f'{slug}_{self.seq:04}')
    def box(self, name, xyz, size, color, yaw=0, metallic=0):
        mesh=trimesh.creation.box(extents=size)
        if yaw: mesh.apply_transform(rotation_matrix(yaw,[0,0,1]))
        mesh.apply_translation(xyz)
        self.add(mesh,name,color,metallic)
    def cyl(self, name, xyz, r, length, color, axis='z', sections=12, metallic=0):
        mesh=trimesh.creation.cylinder(radius=r,height=length,sections=sections)
        if axis=='x': mesh.apply_transform(rotation_matrix(math.pi/2,[0,1,0]))
        if axis=='y': mesh.apply_transform(rotation_matrix(math.pi/2,[1,0,0]))
        mesh.apply_translation(xyz)
        self.add(mesh,name,color,metallic)
    def cone(self,name,xyz,r1,r2,length,color,axis='z',sections=12):
        # custom truncated cone (radius bottom and radius top)
        verts=[]
        for z,r in [(-length/2,r1),(length/2,r2)]:
            for i in range(sections):
                t=i*2*math.pi/sections
                verts.append([r*math.cos(t),r*math.sin(t),z])
        verts+= [[0,0,-length/2],[0,0,length/2]]
        faces=[]
        for i in range(sections):
            j=(i+1)%sections
            faces.extend([(i,j,sections+j),(i,sections+j,sections+i),
                         (2*sections,j,i),(2*sections+1,sections+i,sections+j)])
        mesh=trimesh.Trimesh(vertices=verts,faces=faces,process=False)
        if axis=='x': mesh.apply_transform(rotation_matrix(math.pi/2,[0,1,0]))
        if axis=='y': mesh.apply_transform(rotation_matrix(math.pi/2,[1,0,0]))
        mesh.apply_translation(xyz)
        self.add(mesh,name,color)
    def sphere(self,name,xyz,scale,color,sub=1):
        mesh=trimesh.creation.icosphere(subdivisions=sub,radius=1)
        mesh.apply_scale(scale)
        mesh.apply_translation(xyz)
        self.add(mesh,name,color)
    def rod(self,name,a,b,r,color,sections=8):
        a,b=np.asarray(a,float),np.asarray(b,float)
        d=b-a
        le=np.linalg.norm(d)
        if le<1e-6: return
        mesh=trimesh.creation.cylinder(radius=r,height=le,sections=sections)
        mesh.apply_transform(trimesh.geometry.align_vectors([0,0,1],d/le))
        mesh.apply_translation((a+b)/2)
        self.add(mesh,name,color)
    def ring(self,name,xyz,r_outer,r_inner,height,color,axis='z',sections=24):
        mesh=trimesh.creation.annulus(r_min=r_inner,r_max=r_outer,height=height,sections=sections)
        if axis=='y': mesh.apply_transform(rotation_matrix(math.pi/2,[1,0,0]))
        if axis=='x': mesh.apply_transform(rotation_matrix(math.pi/2,[0,1,0]))
        mesh.apply_translation(xyz)
        self.add(mesh,name,color)
    def frame(self,name,w,h,center,thick,depth,color):
        cx,cy,cz=center
        self.box(name+'_left',[cx-w/2+thick/2,cy,cz],[thick,depth,h],color)
        self.box(name+'_right',[cx+w/2-thick/2,cy,cz],[thick,depth,h],color)
        self.box(name+'_top',[cx,cy,cz+h/2-thick/2],[w-2*thick,depth,thick],color)
        self.box(name+'_bottom',[cx,cy,cz-h/2+thick/2],[w-2*thick,depth,thick],color)
    def export(self,filename):
        target=OUT/f'{filename}.glb'
        data=self.scene.export(file_type='glb')
        target.write_bytes(data)
        print(f'{filename}: {self.seq} parts, {len(data):,} bytes')
        return target
