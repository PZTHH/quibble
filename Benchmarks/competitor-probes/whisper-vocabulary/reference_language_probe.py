import json,pathlib,sys,time
from mlx_lm import load,generate
from mlx_lm.sample_utils import make_sampler
root=pathlib.Path(__file__).resolve().parents[3]
model_dir=sys.argv[1];output=pathlib.Path(sys.argv[2])
model,tokenizer=load(model_dir)
prompt=(root/'Benchmarks/vocabulary-role-prompt.txt').read_text().split('\n---USER---\n')[0]
fixtures=json.loads((root/'Benchmarks/vocabulary-role-fixtures.json').read_text());rows=[]
for case in fixtures:
 text=tokenizer.apply_chat_template([{'role':'system','content':prompt},{'role':'user','content':case['text']}],tokenize=False,add_generation_prompt=True,enable_thinking=False)
 started=time.monotonic();response=generate(model,tokenizer,prompt=text,max_tokens=32,sampler=make_sampler(temp=0),verbose=False)
 rows.append(dict(text=case['text'],expected=case['expected'],response=response,prompt=text,ids=tokenizer.encode(text,add_special_tokens=False),seconds=time.monotonic()-started))
 output.write_text(json.dumps(rows,indent=2));print(case['text'],response,flush=True)
