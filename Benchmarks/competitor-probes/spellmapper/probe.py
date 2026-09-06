"""Isolated SpellMapper CPU probe; no NeMo import, retrieval, or production use.

Weights: bene-ges/spellmapper_asr_customization_en at
10fd0674ab417c2337f236308005c6a598fd4a1e (CC BY 4.0).
Forward/pooling follows NVIDIA-NeMo/Speech at
265bd739c77c86ac423942d650eed6fc232e4fc6 (Apache 2.0).
"""
import argparse
import gc
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import statistics
import tarfile
import time

os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
import torch
from transformers import BertConfig, BertModel, BertTokenizer
from bert_example import BertExampleBuilder
from postprocess import apply_replacements_to_text

torch.set_num_threads(2)
torch.set_num_interop_threads(1)
THRESHOLDS = [0.5, 0.7, 0.8, 0.9, 0.95, 0.99]
# Fixed before either evaluation. These fill the checkpoint's ten candidate slots.
# No replacement is ever allowed from dummy slots.
DUMMIES = ["basket", "harbor", "velvet", "pencil", "orbit", "meadow", "copper", "window", "lantern", "bicycle"]


class SpellMapper(torch.nn.Module):
    def __init__(self, config):
        super().__init__()
        config._attn_implementation = "eager"
        self.bert = BertModel(config)
        self.classifier = torch.nn.Linear(1536, 11)

    def forward(self, f):
        char = self.bert(input_ids=f["input_ids"], attention_mask=f["input_mask"], token_type_ids=f["segment_ids"]).last_hidden_state
        sub = self.bert(input_ids=f["input_ids_for_subwords"], attention_mask=f["input_mask_for_subwords"], token_type_ids=f["segment_ids_for_subwords"]).last_hidden_state
        index = f["character_pos_to_subword_pos"].unsqueeze(-1).expand(-1, -1, sub.shape[-1])
        return self.classifier(torch.cat((char, torch.gather(sub, 1, index)), dim=2))


def load_model(directory):
    started = time.perf_counter()
    archive = directory / "training_10m_5ep.nemo"
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == "0295a34a5522257bdae22c714ca990c5e5a5eb444e82597944785fcfae93516d"
    with tarfile.open(archive, "r:") as tar:
        for member in tar:
            path = Path(member.name)
            assert not path.is_absolute() and ".." not in path.parts
            assert not member.issym() and not member.islnk()
        state = torch.load(tar.extractfile("./model_weights.ckpt"), map_location="cpu", weights_only=True)
    config = BertConfig.from_json_file(next(directory.glob("*encoder_config.json")))
    model = SpellMapper(config)
    bert_state = {k.removeprefix("bert_model."): v for k, v in state.items() if k.startswith("bert_model.") and k != "bert_model.embeddings.position_ids"}
    model.bert.load_state_dict(bert_state, strict=True)
    model.classifier.load_state_dict({"weight": state["logits.mlp.layer0.weight"], "bias": state["logits.mlp.layer0.bias"]}, strict=True)
    ignored = [k for k in state if not k.startswith("bert_model.") and not k.startswith("logits.mlp.layer0.")]
    del state, bert_state
    gc.collect()
    model.eval()
    tokenizer = BertTokenizer(vocab_file=str(next(directory.glob("*vocab.txt"))), do_lower_case=True, model_max_length=512)
    builder = BertExampleBuilder({str(i): i for i in range(11)}, {"PLAIN": 0, "CUSTOM": 1}, tokenizer, 512)
    return model, builder, {"load_seconds": time.perf_counter() - started, "parameters": sum(p.numel() for p in model.parameters()), "parameter_bytes": sum(p.numel() * p.element_size() for p in model.parameters()), "ignored_training_buffers": ignored}


def make_features(builder, text, words):
    assert 0 < len(words) <= 10
    candidates = list(words)
    candidates.extend(w for w in DUMMIES if w.lower() not in {x.lower() for x in candidates})
    candidates = candidates[:10]
    spaced = lambda s: " ".join(s.lower().replace(" ", "_"))
    example = builder.build_bert_example(spaced(text), ";".join(map(spaced, candidates)), target="0", span_info="", infer=True)
    if example is None:
        raise ValueError("Input exceeds checkpoint's 512 character-token budget")
    keys = ["input_ids", "input_mask", "segment_ids", "input_ids_for_subwords", "input_mask_for_subwords", "segment_ids_for_subwords", "character_pos_to_subword_pos"]
    features = {k: torch.tensor([example.features[k]], dtype=torch.long) for k in keys}
    assert len(example.features["input_ids"]) >= len(text) + 2
    return features, candidates


def get_probabilities(logits, text, words):
    # Direct small-dictionary experiment: score every 1–3 word span for every
    # real candidate. This intentionally removes retrieval-recall limitations.
    # It is NOT the original n-gram retrieval + DP-filtered pipeline.
    tokens = list(re.finditer(r"[^\W_]+(?:['’\-][^\W_]+)*", text, flags=re.UNICODE))
    spans = []
    for i, first in enumerate(tokens):
        for n in range(1, min(3, len(tokens) - i) + 1):
            final = tokens[i + n - 1]
            between = text[first.start():final.end()]
            if re.search(r"[.,;:!?]", between):
                continue
            start, end = first.start(), final.end()
            probs = torch.softmax(logits[0, start + 1:end + 1].mean(dim=0), dim=-1)
            for j, word in enumerate(words):
                p = float(probs[j + 1])
                penalty = min(1.0, (end - start) / len(word))
                spans.append({"start": start, "end": end, "heard": text[start:end], "preferred": word, "probability": p, "length_penalized_probability": p * penalty})
    return sorted(spans, key=lambda s: s["probability"], reverse=True)


def evaluate(model, builder, fixtures):
    results = []
    for fixture in fixtures:
        start = time.perf_counter()
        f, candidates = make_features(builder, fixture["text"], fixture["words"])
        tokenization_seconds = time.perf_counter() - start
        infer_start = time.perf_counter()
        with torch.inference_mode():
            logits = model(f)
        inference_seconds = time.perf_counter() - infer_start
        spans = get_probabilities(logits, fixture["text"], fixture["words"])
        outputs = {}
        for threshold in THRESHOLDS:
            replacements = [(s["start"], s["end"], s["preferred"], s["probability"]) for s in spans]
            output = apply_replacements_to_text(fixture["text"], replacements, min_prob=threshold)
            outputs[str(threshold)] = {"text": output, "matched": output == fixture["expected"], "false_correction": fixture["text"] == fixture["expected"] and output != fixture["text"]}
        results.append({**fixture, "candidates": candidates, "negative": fixture["text"] == fixture["expected"], "tokenization_seconds": tokenization_seconds, "inference_seconds": inference_seconds, "total_seconds": time.perf_counter() - start, "character_tokens": f["input_ids"].shape[1], "subword_tokens": f["input_ids_for_subwords"].shape[1], "outputs": outputs, "span_probabilities": spans, "character_probabilities": torch.softmax(logits[0, 1:len(fixture["text"]) + 1], -1).tolist()})
    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("models", type=Path)
    parser.add_argument("fixtures", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    model, builder, metadata = load_model(args.models)
    fixtures = json.loads(args.fixtures.read_text())
    results = evaluate(model, builder, fixtures)
    summary = {}
    for threshold in THRESHOLDS:
        key = str(threshold)
        summary[key] = {"exact": sum(r["outputs"][key]["matched"] for r in results), "total": len(results), "positive_exact": sum(r["outputs"][key]["matched"] for r in results if not r["negative"]), "positives": sum(not r["negative"] for r in results), "negative_changes": sum(r["outputs"][key]["false_correction"] for r in results), "negatives": sum(r["negative"] for r in results)}
    metadata.update({"torch": torch.__version__, "threads": 2, "primary_threshold": 0.9, "thresholds_fixed_before_evaluation": THRESHOLDS, "inference_median_seconds": statistics.median(r["inference_seconds"] for r in results), "peak_process_rss_bytes_macos": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss})
    args.output.write_text(json.dumps({"metadata": metadata, "summary": summary, "results": results}, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"metadata": metadata, "summary": summary}, indent=2))


if __name__ == "__main__":
    main()
