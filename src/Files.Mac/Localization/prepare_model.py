#!/usr/bin/env python3
"""Download and convert the pinned development-only translation model."""
from pathlib import Path
import json
from huggingface_hub import snapshot_download
from ctranslate2.converters import TransformersConverter
root=Path(__file__).resolve().parent.parent
provenance=json.loads((root/'Localization/model-provenance.json').read_text())
source=snapshot_download(provenance['repository'],revision=provenance['revision'],local_dir=root/'work/translation-model-source',allow_patterns=['config.json','pytorch_model.bin','vocab.json','sentencepiece.bpe.model','tokenizer_config.json','special_tokens_map.json','README.md'])
TransformersConverter(source).convert(str(root/'work/translation-model-int8'),quantization='int8',force=True)
