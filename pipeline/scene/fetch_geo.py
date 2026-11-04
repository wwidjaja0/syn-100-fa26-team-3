"""Download the Natural Earth layers the microfiche is drawn from and keep a compact copy.

python3 fetch_geo.py  ->  data/world_geo.json

Natural Earth (naturalearthdata.com) is public domain. Cities 1:110m label the world sheet; towns
1:50m label the zoomed detail maps. Coordinates are rounded to 0.01 degrees,
finer than even the zoomed maps need, which keeps the committed file small. Run this only
to change which layers or cities are used; make_fiche.py reads data/world_geo.json.
"""
import json, urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
BASE = 'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/'
LAYERS = {
    'land': 'ne_50m_land',
    'lakes': 'ne_50m_lakes',
    'borders': 'ne_50m_admin_0_boundary_lines_land',
    'states': 'ne_50m_admin_1_states_provinces_lines',
    'rivers': 'ne_50m_rivers_lake_centerlines',
    'cities': 'ne_110m_populated_places_simple',
    'towns': 'ne_50m_populated_places_simple',
}


def get(name):
    with urllib.request.urlopen(BASE + name + '.geojson') as r:
        return json.load(r)


def rnd(pts):
    out, last = [], None
    for lon, lat, *_ in pts:
        p = [round(lon, 2), round(lat, 2)]
        if p != last:
            out.append(p)
            last = p
    return out


def rings(fc, outer_only=False):
    for f in fc['features']:
        g = f['geometry']
        if g is None:
            continue
        polys = [g['coordinates']] if g['type'] == 'Polygon' else g['coordinates']
        for poly in polys:
            for ring in (poly[:1] if outer_only else poly):
                yield rnd(ring)


def lines(fc):
    for f in fc['features']:
        g = f['geometry']
        if g is None:
            continue
        parts = [g['coordinates']] if g['type'] == 'LineString' else g['coordinates']
        for part in parts:
            yield rnd(part)


if __name__ == '__main__':
    data = {k: get(v) for k, v in LAYERS.items()}
    out = {
        '_source': 'Natural Earth 1:50m (cities 1:110m), public domain. Regenerate with fetch_geo.py.',
        'land': list(rings(data['land'])),            # outer rings and holes; make_fiche fills by even-odd
        'lakes': list(rings(data['lakes'], outer_only=True)),
        'borders': list(lines(data['borders'])),
        'states': list(lines(data['states'])),
        # [scalerank, line]: the world sheet draws the big ones, the zoomed detail maps all of them
        'rivers': [[f['properties'].get('scalerank') or 9, l] for f in data['rivers']['features']
                   for l in lines({'features': [f]})],
        'cities': sorted(([p['name'].upper(), round(p['latitude'], 2), round(p['longitude'], 2), p['scalerank'],
                           int(p.get('adm0cap') or 0)]
                          for p in (f['properties'] for f in data['cities']['features'])), key=lambda c: c[3]),
        # the zoomed detail maps label these too: [name, lat, lon, scalerank]
        'towns': sorted(([p['name'].upper(), round(p['latitude'], 2), round(p['longitude'], 2), p['scalerank']]
                         for p in (f['properties'] for f in data['towns']['features'])), key=lambda c: c[3]),
    }
    (HERE / 'data').mkdir(exist_ok=True)
    (HERE / 'data' / 'world_geo.json').write_text(json.dumps(out, separators=(',', ':')))
    print({k: len(v) for k, v in out.items() if isinstance(v, list)})
