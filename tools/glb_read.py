import struct,json,math
def mmul(a,b):  # column-major 4x4
    return [sum(a[k*4+r]*b[c*4+k] for k in range(4)) for c in range(4) for r in range(4)]
def ident(): return [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
def load(path):
    d=open(path,'rb').read()
    l=struct.unpack('<I',d[12:16])[0]; j=json.loads(d[20:20+l])
    off=20+l+8; bin_=d[off:off+struct.unpack('<I',d[20+l:24+l])[0]]
    return j,bin_
def positions(j,b,acc):
    a=j['accessors'][acc]; bv=j['bufferViews'][a['bufferView']]
    o=bv.get('byteOffset',0)+a.get('byteOffset',0); st=bv.get('byteStride',12)
    return [struct.unpack_from('<3f',b,o+i*st) for i in range(a['count'])]
def groups(j,b):
    """{name: {'verts':[world xyz], 'mats':set}} per top-level child of scene root node"""
    out={}
    def walk(n,m,top):
        nd=j['nodes'][n]
        loc=nd.get('matrix',ident()); m=mmul(m,loc)
        if 'mesh' in nd:
            g=out.setdefault(top,{'verts':[]})
            for p in j['meshes'][nd['mesh']]['primitives']:
                for v in positions(j,b,p['attributes']['POSITION']):
                    g['verts'].append(tuple(m[0+r]*v[0]+m[4+r]*v[1]+m[8+r]*v[2]+m[12+r] for r in range(3)))
        for c in nd.get('children',[]): walk(c,m,top if top else j['nodes'][c]['name'])
    # root 3 is GLTF_SceneRootNode
    root=0; m=ident()
    for n in (0,1,2):
        m=mmul(m,j['nodes'][n].get('matrix',ident()))
    for c in j['nodes'][2]['children']:
        walk(c,m,j['nodes'][c]['name'])
    return out
if False:
    j,b=load('/root/.claude/uploads/3165e2a3-3a67-5ac9-9226-c47a774fe8d5/c9447d84-low-poly_hk_mp7_a1.glb')
    for k,g in groups(j,b).items():
        v=g['verts']; mn=[min(p[i] for p in v) for i in range(3)]; mx=[max(p[i] for p in v) for i in range(3)]
        print('%-40s n=%6d min=%s max=%s'%(k,len(v),[round(x,2) for x in mn],[round(x,2) for x in mx]))
