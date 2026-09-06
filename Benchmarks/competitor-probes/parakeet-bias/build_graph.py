"""Benchmark-only graph export. Executes the pinned NeMo ContextGraph unmodified.
Shims optional visualization/type imports only; no NeMo installation required.
"""
import argparse, importlib.util, json, pathlib, sys, types
import sentencepiece as spm

for name in ['nemo.collections.common.tokenizers.tokenizer_spec', 'nemo.core.utils.optional_libs']:
    sys.modules[name] = types.ModuleType(name)
sys.modules['nemo.collections.common.tokenizers.tokenizer_spec'].VarBPERepresentation = object
optional = sys.modules['nemo.core.utils.optional_libs']
optional.GRAPHVIZ_AVAILABLE = False
optional.graphviz_required = lambda f: f
source = pathlib.Path(__file__).resolve().parent.parent / 'nemo/context_graph_universal.py'
spec = importlib.util.spec_from_file_location('nemo_probe_graph', source)
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)


def table(graph, size, unknown=0.0, eos=None):
    nodes = {}; queue = [graph.root]
    for node in queue:
        if node.id in nodes: continue
        nodes[node.id] = node; queue.extend(node.next.values())
    rows, transitions = [], []
    for index in range(len(nodes)):
        node = nodes[index]; scores, nexts = [], []
        for token in range(size):
            cur, score = node, 0.0
            while token not in cur.next and cur.id != 0:
                # Nonuniform NeMo BoostingTreeStorage backoff semantics.
                score += 0.0 if cur.is_end else cur.fail.node_score - cur.node_score
                cur = cur.fail
            if token in cur.next:
                nxt = cur.next[token]; score += nxt.node_score - cur.node_score
            else:
                nxt = graph.root; score += unknown
            scores.append(float(score)); nexts.append(nxt.id)
        if eos is not None:
            scores[eos] = max(scores) + (1.0 if node.is_end else 0.0)
            nexts[eos] = 0
        rows.append(scores); transitions.append(nexts)
    return rows, transitions


def check():
    import math
    g = module.ContextGraph(context_score=1.0, depth_scaling=2.0)
    g.build([[1, 2], [2, 3]])
    scores, nxt = table(g, 5)
    a = nxt[0][1]; ab = nxt[a][2]
    assert scores[0][1] == 1.0
    assert abs(scores[a][2] - 2.69314718056) < 1e-9
    assert scores[a][4] == -1.0, 'Abandoned partial phrase must refund its boost'
    assert abs(scores[ab][3] - 2.69314718056) < 1e-9, 'Suffix can start an overlapping phrase'
    g = module.ContextGraph(context_score=1.0, depth_scaling=2.0); g.build([[1, 2]])
    scores, nxt = table(g, 5)
    assert scores[nxt[nxt[0][1]][2]][4] == 0.0, 'Completed phrase retains its boost'
    print('Graph checks passed: progression, refund, completion, overlap')


if __name__ == '__main__':
    check()
    p = argparse.ArgumentParser(); p.add_argument('model'); p.add_argument('fixture'); p.add_argument('output'); p.add_argument('--unknown', type=float, default=0.0); p.add_argument('--cohere', action='store_true')
    a = p.parse_args(); model = pathlib.Path(a.model)
    tokenizer = spm.SentencePieceProcessor(model_file=str(model / 'tokenizer.model'))
    vocabulary = [tokenizer.id_to_piece(i) for i in range(tokenizer.vocab_size())] if a.cohere else json.loads((model / 'config.json').read_text())['joint']['vocabulary']
    assert len(vocabulary) == tokenizer.vocab_size()
    assert all(piece == tokenizer.id_to_piece(i) for i, piece in enumerate(vocabulary)), 'Token IDs must match the ASR weights'
    fixture = json.loads(pathlib.Path(a.fixture).read_text()); words = fixture['words']
    phrases = list(dict.fromkeys(w for word in words for w in [word, word.lower()]))
    token_ids = [tokenizer.encode(word) for word in phrases]
    assert all(tokenizer.unk_id() not in ids for ids in token_ids)
    graph = module.ContextGraph(context_score=1.0, depth_scaling=1.0 if a.cohere else 2.0)
    graph.build(token_ids, phrases=phrases)
    scores, nexts = table(graph, len(vocabulary), a.unknown, eos=3 if a.cohere else None)
    result = dict(words=words, phrases=phrases, tokens=token_ids, rows=scores, transitions=nexts, unknown=a.unknown)
    pathlib.Path(a.output).write_text(json.dumps(result, separators=(',', ':')))
    print(f'{len(words)} words, {len(scores)} states, {len(vocabulary)} tokens, {len(scores)*len(vocabulary)*8} dense bytes (probe only)')
