#!/usr/bin/env python3
"""Replay the explicitly designed Nexo layout through Arcont's public editor.

This fixed design is editable canonical data, not a prompt/random map generator.
Repeated coordinates describe authored blocks, planting rows and road markings.
"""
import argparse
import json
import math
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAP_ID = 'urban_nexo_01'


def compose():
    lock = json.loads((ROOT/'assets/urban/sources.lock.json').read_text())
    models = {(p['pack'], Path(m['path']).stem): m for p in lock['packs'] for m in p['models']}
    objects, instances, geometry, landmarks = [], [], [], []

    def box(identity, position, size, material, collision=False, **extra):
        objects.append(dict(id=identity, type='box', position=position, size=size, material=material, collision=collision, **extra))

    def model(identity, pack, name, x, z, width, yaw=0, y=0.2, collider=True):
        m = models[pack, name]
        factor = width/max(m['size'][0], m['size'][2])
        cx, cz = (m['min'][0]+m['max'][0])/2, (m['min'][2]+m['max'][2])/2
        theta = math.radians(yaw)
        dx = (cx*math.cos(theta)+cz*math.sin(theta))*factor
        dz = (-cx*math.sin(theta)+cz*math.cos(theta))*factor
        instances.append(dict(id=identity, scene='res://'+m['path'], position=[round(x-dx,5), round(y-m['min'][1]*factor,5), round(z-dz,5)], rotation_degrees=[0,yaw,0], scale=[round(factor,6)]*3))
        sx, sy, sz = [round(v*factor,5) for v in m['size']]
        if yaw%180 == 90:
            sx, sz = sz, sx
        if collider:
            box(identity+'_collision', [x,y+sy/2,z], [sx,sy,sz], 'concrete', True, visible=False)
        return sy

    def tree(identity,x,z,height=8,name='tree_default'):
        m=models['nature',name]
        width=height*max(m['size'][0],m['size'][2])/m['size'][1]
        model(identity,'nature',name,x,z,width,collider=False)
        # Trunk-only approximation keeps pedestrian routes out of the canopy.
        box(identity+'_trunk',[x,1.7,z],[0.5,3,0.5],'wood',True,visible=False)

    box('ground',[0,-0.6,0],[512,1.2,512],'grass',True)
    streets = [-216,-144,-72,0,72,144,216]
    centres = [-180,-108,-36,36,108,180]
    for axis in ['x','z']:
        for c in streets:
            spans = [(-232,-66),(66,232)] if c == 0 else [(-232,232)]
            for segment,(lo,hi) in enumerate(spans):
                pos=[(lo+hi)/2,0.045,c] if axis=='x' else [c,0.045,(lo+hi)/2]
                size=[hi-lo,0.09,18] if axis=='x' else [18,0.09,hi-lo]
                box(f'road_{axis}_{c}_{segment}',pos,size,'asphalt')
                for offset in [-0.18,0.18]:
                    pos=[(lo+hi)/2,0.102,c+offset] if axis=='x' else [c+offset,0.102,(lo+hi)/2]
                    size=[hi-lo,0.02,0.13] if axis=='x' else [0.13,0.02,hi-lo]
                    box(f'centreline_{axis}_{c}_{segment}_{offset}',pos,size,'yellow')
            # Interrupted parking lane markings belong between intersections.
            for b in centres:
                if c==0 and abs(b)==36:
                    continue
                for sign in [-1,1]:
                    pos=[b,0.104,c+sign*6] if axis=='x' else [c+sign*6,0.104,b]
                    size=[40,0.02,0.12] if axis=='x' else [0.12,0.02,40]
                    box(f'parking_lane_{axis}_{c}_{b}_{sign}',pos,size,'white')

    # Thirty-two blocks surround a single pedestrian civic centre.
    commercial=['building-a','building-f','building-h','building-skyscraper-b','building-skyscraper-c','building-skyscraper-d','building-skyscraper-e']
    industrial=['building-a','building-c','building-g','building-j','building-p']
    houses=['building-type-a','building-type-c','building-type-e','building-type-g','building-type-i','building-type-k']
    block_index=0
    for x in centres:
        for z in centres:
            if abs(x)==36 and abs(z)==36:
                continue
            block_index+=1
            district='comercial' if x<0 and z<0 else 'industrial' if x>0 and z<0 else 'residencial' if x<0 else 'civico'
            ident=f'block_{block_index:02d}'
            box(ident+'_sidewalk',[x,0.1,z],[54,0.2,54],'concrete',True)
            if district=='comercial':
                box(ident+'_courtyard',[x,0.211,z],[7,0.02,50],'paving')
                for n,(dx,dz) in enumerate([(-14,-14),(-14,14),(14,-14),(14,14)]):
                    name=commercial[(block_index+n)%len(commercial)]
                    model(f'{ident}_office_{n}','commercial',name,x+dx,z+dz,22,yaw=90*(n%4))
            elif district=='industrial':
                name=industrial[block_index%len(industrial)]
                model(ident+'_factory','industrial',name,x-4,z-7,36,yaw=90 if block_index%2 else 0)
                for n in range(3):
                    model(f'{ident}_container_{n}','industrial','shipping-container-a' if n%2 else 'shipping-container-b',x-15+n*11,z+20,9,yaw=90)
                if block_index%3==0:
                    model(ident+'_water_tower','industrial','water-tower',x+18,z+9,8)
            elif district=='residencial':
                box(ident+'_lawn',[x,0.211,z],[44,0.02,44],'grass_light')
                for n,(dx,dz) in enumerate([(-13,-13),(-13,13),(13,-13),(13,13)]):
                    model(f'{ident}_home_{n}','suburban',houses[(block_index+n)%6],x+dx,z+dz,17,yaw=180 if dz<0 else 0)
                    box(f'{ident}_driveway_{n}',[x+dx,0.232,z+dz+(8 if dz>0 else -8)],[4,0.02,8],'concrete')
            elif (x,z) in [(108,108),(108,180),(180,108),(180,180)]:
                box(ident+'_park',[x,0.211,z],[46,0.02,46],'grass_light')
                box(ident+'_path_x',[x,0.235,z],[50,0.02,5],'paving')
                box(ident+'_path_z',[x,0.237,z],[5,0.02,50],'paving')
                for n,(dx,dz) in enumerate([(-16,-16),(-16,16),(16,-16),(16,16)]):
                    tree(f'{ident}_park_tree_{n}',x+dx,z+dz,10+(n%2)*2,'tree_plateau')
                for n,dx in enumerate([-9,9]):
                    box(f'{ident}_bench_{n}',[x+dx,0.8,z+5],[3,0.5,0.8],'wood',True)
            else:
                for n,dx in enumerate([-14,14]):
                    model(f'{ident}_civic_{n}','commercial','building-e' if n==0 else 'building-c',x+dx,z,23,yaw=90)
                box(ident+'_garden',[x,0.22,z+19],[42,0.04,8],'grass_light')
            # Street planting leaves the central six-metre alley clear.
            for n,(dx,dz) in enumerate([(-24,-22),(-24,22),(24,-22),(24,22)]):
                if district!='industrial':
                    tree(f'{ident}_tree_{n}',x+dx,z+dz,6+(block_index%3))
            # Parked cars are static props with explicit physical proxies.
            if z!=-36:
                model(ident+'_parked_car','cars','delivery' if district=='industrial' else 'taxi' if district=='comercial' else 'sedan',x,z-30.5,5.1,yaw=90,y=0.09)
            # Lamp geometry; only a few plaza fixtures emit light to keep budget finite.
            for n,dx in enumerate([-25,25]):
                box(f'{ident}_lamp_{n}',[x+dx,3.3,z-25],[0.18,6.2,0.18],'steel')
                box(f'{ident}_lamp_head_{n}',[x+dx,6.4,z-24],[0.7,0.2,2.2],'steel')
            if x in [-108,108] and z in [-108,108]:
                for stripe in range(8):
                    box(f'{ident}_crosswalk_{stripe}',[x+stripe*1.1-4,0.12,z-36],[0.55,0.02,16],'white')

    box('civic_plaza',[0,0.1,0],[132,0.2,132],'plaza_pavers',True)
    box('plaza_axis_x',[0,0.211,0],[132,0.02,10],'concrete')
    box('plaza_axis_z',[0,0.212,0],[10,0.02,132],'concrete')
    objects.append(dict(id='fountain_base',type='cylinder',position=[0,0.45,0],size=[23,0.5,23],material='concrete',collision=True))
    objects.append(dict(id='fountain_water',type='cylinder',position=[0,0.74,0],size=[21,0.1,21],material='water'))
    box('monument_plinth',[0,1.8,0],[5,2.5,5],'steel',True)
    objects.append(dict(id='nexo_spire',type='prism',position=[0,14,0],size=[4,26,4],material='copper',collision=True,rotation_degrees=[0,35,0]))
    objects.append(dict(id='nexo_ring',type='torus',position=[0,17,0],size=[13,1,13],material='copper',rotation_degrees=[75,0,0]))
    for n,(x,z) in enumerate([(-47,-47),(-47,47),(47,-47),(47,47)]):
        box(f'plaza_garden_{n}',[x,0.25,z],[24,0.1,24],'grass_light')
        for k,(dx,dz) in enumerate([(-7,-7),(-7,7),(7,-7),(7,7)]):
            tree(f'plaza_palm_{n}_{k}',x+dx,z+dz,9,'tree_palmTall')
        for k,dx in enumerate([-7,7]):
            box(f'plaza_seat_{n}_{k}',[x+dx,0.85,z-14],[4,0.5,1],'wood',True)
    for n,(x,z,yaw) in enumerate([(-46,0,90),(46,0,270),(0,-46,180),(0,46,0)]):
        # Four small shops frame the plaza while leaving entrances at the corners.
        model(f'plaza_cafe_{n}','commercial','building-c',x,z,16,yaw=yaw)

    # Walkable eight-metre viaduct with correctly wound collision ramps.
    box('viaduct_deck',[0,7.6,216],[360,0.8,10],'concrete',True)
    box('viaduct_surface',[0,8.02,216],[360,0.04,8],'asphalt')
    for z in [211,221]:
        box(f'viaduct_rail_{z}',[0,8.6,z],[360,1.2,0.3],'steel',True)
    for x in [-180,-108,-36,36,108,180]:
        box(f'viaduct_pier_{x}',[x,3.5,216],[2.5,7,2.5],'concrete',True)
    for name,x0,x1,h0,h1 in [('west',-244,-180,0.09,8),('east',180,244,8,0.09)]:
        vertices=[[x0,h0,211],[x1,h1,211],[x1,h1,221],[x0,h0,221]]
        geometry.append(dict(id='viaduct_ramp_'+name,vertices=vertices,indices=[0,1,2,0,2,3],material='asphalt',collision=True))
        angle=-math.degrees(math.atan2(h1-h0,x1-x0))
        length=math.hypot(x1-x0,h1-h0)
        for z in [211,221]:
            box(f'{name}_ramp_rail_{z}',[(x0+x1)/2,(h0+h1)/2+0.6,z],[length,1.2,0.3],'steel',True,rotation_degrees=[0,0,-angle])
    for n,z in enumerate(range(-240,241,30)):
        for side in [-1,1]:
            tree(f'outer_tree_{n}_{side}',side*242,z,10,'tree_simple')
    for axis in ['x','z']:
        for side in [-1,1]:
            pos=[side*255,2,0] if axis=='x' else [0,2,side*255]
            size=[1,6,512] if axis=='x' else [512,6,1]
            box(f'boundary_{axis}_{side}',pos,size,'grass',True,visible=False)

    cameras=[
        dict(name='city_overview',position=[400,320,400],target=[0,-35,0],projection='perspective',fov=54),
        dict(name='plaza',position=[64,34,83],target=[-10,8,-15],projection='perspective',fov=62),
        dict(name='downtown_street',position=[-72,2.1,-132],target=[-72,10,-45],projection='perspective',fov=74),
        dict(name='industrial',position=[178,38,-42],target=[108,4,-130],projection='perspective',fov=65),
        dict(name='residential',position=[-68,22,171],target=[-135,4,127],projection='perspective',fov=66),
        dict(name='park',position=[210,20,154],target=[110,2,108],projection='perspective',fov=64),
        dict(name='viaduct',position=[-167,10.1,216],target=[40,8,216],projection='perspective',fov=74),
        dict(name='plan',position=[0,600,0.01],target=[0,0,0],projection='orthogonal',size=540),
    ]
    checkpoints=[dict(id='plaza',label='Plaza Nexo',position=[25,0.3,25]),dict(id='comercial',label='Distrito comercial',position=[-72,0.3,-108]),dict(id='industrial',label='Zona industrial',position=[144,0.3,-108]),dict(id='residencial',label='Barrio residencial',position=[-144,0.3,108]),dict(id='parque',label='Parque civico',position=[108,0.3,108]),dict(id='viaducto',label='Viaducto sur',position=[0,8.1,216])]
    return dict(version=1,id=MAP_ID,display_name='Distrito Nexo',purpose='environment',bounds=dict(width=512,depth=512),bases=[],objectives=[],routes=[],regions=[],
        urban_design=dict(area_m2=262144,street_width=18,block_spacing=72,blocks=32,districts=['comercial','industrial','residencial','civico'],asset_sources='res://assets/urban/sources.lock.json',spawn=[25,0.35,25],checkpoints=checkpoints,building_interiors=False),evidence_cameras=cameras,
        authoring=dict(materials=[dict(id=k,albedo=v,roughness=0.85) for k,v in {'asphalt':'29333d','concrete':'b7b5aa','paving':'d6c9ad','grass':'527b57','grass_light':'739563','white':'ece6cf','yellow':'e8b957','steel':'344753','wood':'906342','copper':'c88441','water':'3cabb9'}.items()]+[dict(id='plaza_pavers',albedo='ffffff',roughness=0.95,albedo_texture='res://assets/urban/plaza_pavers.svg',uv_scale=[66,66,66])],objects=objects,instances=instances,geometry=geometry,lights=[dict(id='afternoon_sun',type='directional',color='ffe4c1',energy=0.7,rotation_degrees=[-48,-32,0],shadows=True)],environment=dict(background_color='819db6',ambient_color='b4c7da',ambient_energy=0.22,fog_enabled=True,fog_color='b3cbd9',fog_density=0.0003),navigation=dict(mode='world',agent_radius=0.45,agent_height=1.8,agent_max_climb=0.3,agent_max_slope=40,cell_size=0.5,cell_height=0.2)))


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--arcont',default=os.environ.get('ARCONT_ROOT'))
    args=parser.parse_args()
    if not args.arcont:
        parser.error('--arcont or ARCONT_ROOT is required')
    calls=[]
    def control(operation,**params):
        request=dict(protocol_version=1,operation=operation,**params)
        run=subprocess.run([sys.executable,str(Path(args.arcont)/'tools/map_forge_control.py'),'--project',str(ROOT)],input=json.dumps(request),text=True,capture_output=True,timeout=240)
        result=json.loads(run.stdout)
        assert result.get('ok'),result
        calls.append(dict(operation=operation,revision=result.get('revision'),committed=result.get('committed',False)))
        return result
    control('capabilities')
    listed=control('list')
    state=dict(map=compose(),physical=None)
    if any(m['map_id']==MAP_ID for m in listed['maps']):
        old=control('inspect',map_id=MAP_ID)
        control('replace',map_id=MAP_ID,if_revision=old['revision'],state=state,dry_run=False)
    else:
        control('create',map_id=MAP_ID,state=state,dry_run=False)
    final=control('inspect',map_id=MAP_ID)
    control('validate',map_id=MAP_ID)
    evidence=ROOT/'.mapforge/urban-authoring.json'
    evidence.parent.mkdir(exist_ok=True)
    evidence.write_text(json.dumps(dict(ok=True,calls=calls,revision=final['revision']),indent=2)+'\n')
    print('URBAN_ARCONT_AUTHORING_OK',final['revision'],len(state['map']['authoring']['instances']),'asset instances')


if __name__=='__main__':
    main()
