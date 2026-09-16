#!/usr/bin/env python3
import json, math, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def load(path): return json.loads(path.read_text(encoding='utf-8'))
def vec3(v): return isinstance(v,list) and len(v)>=3 and all(isinstance(x,(int,float)) and math.isfinite(x) for x in v[:3])
def positive(v): return vec3(v) and all(float(x)>0 for x in v[:3])
def validate(map_path, profile_path):
    m,p=load(map_path),load(profile_path); errors=[]; warnings=[]
    if p.get('schema_version')!=1: errors.append('unsupported physical schema_version')
    if p.get('map_id')!=m.get('id'): errors.append('physical map_id does not match canonical map')
    routes={r.get('id'):r for r in m.get('routes',[]) if isinstance(r,dict)}
    formation=p.get('formation',{}); footprint=max(float(formation.get('unit_diameter',.9))+float(formation.get('spacing',.25)),.1); min_cols=int(formation.get('minimum_columns',3))
    for rid,r in routes.items():
        width=float(r.get('width',0)); required=float(r.get('formation_width',width)); cols=max(1,int(width//footprint))
        if width<required: errors.append(f'route {rid} narrower than formation_width')
        if cols<min_cols: errors.append(f'route {rid} has only {cols} formation columns')
    blockers=p.get('terrain_blockers',[])
    if not blockers: errors.append('no tactical terrain blockers')
    ids=set()
    for b in blockers:
        bid=b.get('id','')
        if not bid or bid in ids: errors.append(f'invalid/duplicate blocker id {bid!r}')
        ids.add(bid)
        if not vec3(b.get('center')) or not positive(b.get('size')): errors.append(f'blocker {bid} has invalid geometry')
        if b.get('navigation_role') not in {'tactical_boundary','blocking_cliff','pass_wall'}: errors.append(f'blocker {bid} has non-tactical navigation_role')
    passes=p.get('passes',[])
    if len(passes)<2: errors.append('at least two explicit passes required')
    for q in passes:
        if q.get('connects_route') not in routes: errors.append(f"pass {q.get('id')} references unknown route")
        if float(q.get('width',0))<=0: errors.append(f"pass {q.get('id')} width must be positive")
        if float(q.get('max_slope_degrees',90))>45: warnings.append(f"pass {q.get('id')} slope exceeds 45 degrees")
    budget=p.get('performance_budget',{})
    for key in ('target_fps','frame_budget_ms','max_active_units','max_visible_scatter_instances'):
        if float(budget.get(key,0))<=0: errors.append(f'performance_budget.{key} must be positive')
    if not budget.get('require_measured_device_evidence'): errors.append('measured device evidence must remain required')
    return errors,warnings
def main():
    profiles=sorted((ROOT/'maps'/'physical').glob('*.json'))
    if not profiles: print('ERROR: no physical profiles',file=sys.stderr); return 1
    failed=0
    for profile in profiles:
        p=load(profile); map_path=ROOT/'maps'/f"{p.get('map_id','')}.json"
        if not map_path.is_file(): print(f'FAIL {profile}: canonical map missing'); failed+=1; continue
        errors,warnings=validate(map_path,profile); print(('PASS' if not errors else 'FAIL'),profile.relative_to(ROOT))
        for e in errors: print('  ERROR:',e)
        for w in warnings: print('  WARN:',w)
        failed+=bool(errors)
    print(f'Physical-world validation: {len(profiles)-failed}/{len(profiles)} passed')
    return 1 if failed else 0
if __name__=='__main__': raise SystemExit(main())
