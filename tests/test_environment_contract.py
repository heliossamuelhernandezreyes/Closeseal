import copy
import json
import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from validate_maps import validate

class EnvironmentContractTests(unittest.TestCase):
    def setUp(self):
        self.data=json.loads((Path(__file__).resolve().parents[1]/'maps/environment_alpine_lab.json').read_text())
    def errors(self):
        return validate(self.data,Path('test.json'))[0]
    def test_environment_accepts_empty_gameplay(self):
        self.assertEqual(self.errors(),[])
    def test_competitive_still_requires_bases(self):
        self.data['purpose']='competitive'
        self.assertTrue(self.errors())
    def test_bad_grid_never_accepted(self):
        self.data['authoring']['heightfields'][0]['heights']=[0]
        self.assertTrue(self.errors())
    def test_invalid_cell_paint_and_holes(self):
        field=self.data['authoring']['heightfields'][0]
        for key,value in [('paint',['missing']*256),('holes',[1]*256),('spacing',[-2,2])]:
            original=copy.deepcopy(field.get(key))
            field[key]=value
            self.assertTrue(self.errors())
            if original is None:field.pop(key)
            else:field[key]=original
    def test_parent_cycle_rejected(self):
        self.data['authoring']['objects'][0]['parent']='lake'
        self.assertTrue(self.errors())
    def test_unknown_primitive_rejected(self):
        self.data['authoring']['objects'][0]['type']='whatever'
        self.assertTrue(self.errors())
    def test_material_inputs_rejected(self):
        material=self.data['authoring']['materials'][0]
        for key,value in [('roughness',2),('albedo','bad color'),('albedo_texture','res://../secret.png')]:
            original=material.get(key)
            material[key]=value
            self.assertTrue(self.errors())
            if original is None:material.pop(key)
            else:material[key]=original
    def test_bad_geometry_uv_rejected(self):
        self.data['authoring']['geometry']=[{'id':'mesh','vertices':[[0,0,0],[1,0,0],[0,0,1]],'indices':[0,1,2],'uvs':[[0,0]]}]
        self.assertTrue(self.errors())
    def test_invalid_navigation_dimensions_rejected(self):
        self.data['authoring']['navigation']={'mode':'world','agent_height':-1}
        self.assertTrue(self.errors())
    def test_authoring_null_rejected(self):
        self.data['authoring']=None
        self.assertTrue(self.errors())
