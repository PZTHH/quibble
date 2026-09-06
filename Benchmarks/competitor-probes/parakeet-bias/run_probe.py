"""Sequential, network-denied end-to-end ASR comparison; no cleanup or aliases."""
import argparse, json, os, pathlib, subprocess, time
root=pathlib.Path(__file__).resolve().parents[3]
p=argparse.ArgumentParser();p.add_argument('--fixture',default='Benchmarks/vocabulary-name-audio.json');p.add_argument('--audio',default='.build/name-audio');p.add_argument('--graph',default='.build/parakeet-bias-graph.json');p.add_argument('--prefix',default='parakeet-bias');p.add_argument('--alphas',default='baseline,0,0.5,1,2');p.add_argument('--engine',choices=['parakeet','cohere-4bit'],default='parakeet');a=p.parse_args()
fixture=json.loads((root/a.fixture).read_text());out=root/'Benchmarks/results'/a.prefix;out.mkdir(parents=True,exist_ok=True)
exe=root/'DerivedData/Build/Products/Release/Quibble.app/Contents/MacOS/Quibble'
rows=[]
bias_key='QUIBBLE_COHERE_BIAS_' if a.engine=='cohere-4bit' else 'QUIBBLE_PARAKEET_BIAS_'
for alpha in a.alphas.split(','):
    for case in fixture['cases']:
        result=out/f'{alpha}-{case["name"]}.json'
        env=os.environ.copy()
        env.pop(bias_key+'GRAPH',None);env.pop(bias_key+'ALPHA',None)
        if alpha!='baseline':
            env[bias_key+'GRAPH']=str(root/a.graph);env[bias_key+'ALPHA']=alpha
        cmd=['sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(exe),'--benchmark',str(root/'Models'),str(root/a.audio/(case['name']+'.aiff')),str(result),'--'+a.engine,'--runs','2']
        start=time.monotonic();r=subprocess.run(cmd,env=env,text=True,capture_output=True)
        (out/f'{alpha}-{case["name"]}.log').write_text(r.stdout+r.stderr)
        if r.returncode: raise RuntimeError(f'{case["name"]} exited {r.returncode}: {r.stderr[-1000:]}')
        data=json.loads(result.read_text());responses=[run['text'] for run in data['runs']]
        rows.append(dict(alpha=alpha,case=case['name'],expected=case['expected'],responses=responses,wallSeconds=time.monotonic()-start))
        (out/'summary.json').write_text(json.dumps(rows,indent=2))
        print(alpha,case['name'],'=>',responses,flush=True)
