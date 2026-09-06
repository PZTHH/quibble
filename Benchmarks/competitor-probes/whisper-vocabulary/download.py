import pathlib,json,urllib.request,hashlib,concurrent.futures,sys
root=pathlib.Path(__file__).resolve().parents[3];here=pathlib.Path(__file__).parent
large='--large' in sys.argv
folder=root/('Models/whisper-large-vocabulary-4bit' if large else 'Models/whisper-turbo-vocabulary-4bit');folder.mkdir(exist_ok=True)
w=json.loads((here/('large-weights-source.json' if large else 'weights-source.json')).read_text());t=json.loads((here/'tokenizer-source.json').read_text())
items=[(w,f) for f in ['README.md','config.json','model.safetensors','multilingual.tiktoken']]+[(t,f) for f in ['generation_config.json','tokenizer.json','tokenizer_config.json','special_tokens_map.json','merges.txt','vocab.json','normalizer.json','added_tokens.json']]
def get(item):
 source,name=item;record=next(x for x in source['siblings'] if x['rfilename']==name);path=folder/name
 if path.exists():
  assert path.stat().st_size==record['size'];return
 tmp=path.with_suffix(path.suffix+'.part')
 with urllib.request.urlopen('https://huggingface.co/'+source['id']+'/resolve/'+source['sha']+'/'+name,timeout=120) as response, tmp.open('wb') as out:
  sha=hashlib.sha256()
  while chunk:=response.read(1024*1024):out.write(chunk);sha.update(chunk)
 assert tmp.stat().st_size==record['size']
 if record.get('lfs'):assert sha.hexdigest()==record['lfs']['sha256']
 tmp.rename(path);print(name,record['size'],flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:list(pool.map(get,items))
(folder/'probe-receipt.json').write_text(json.dumps({'sources':[w['id'],t['id']],'revisions':[w['sha'],t['sha']]},indent=2))
