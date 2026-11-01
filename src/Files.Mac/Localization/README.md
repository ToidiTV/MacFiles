# Native interface translations

The macOS interface uses the checked-out Files Community translations first. `native-catalog.json` inventories native labels, explanations, errors and interpolation templates. Each of the 49 locale catalogs records the origin of each translation. Locale-specific corrections in `overrides/` take precedence when building resources.

Missing text is translated locally with Meta's MIT-licensed `facebook/m2m100_418M`, pinned to the revision in `model-provenance.json`. The model is a development tool: no model, Python environment, network translator, user filenames or file contents are shipped or sent to a service. Technical terms and numbered placeholders are protected. Traditional Chinese uses OpenCC's simplified-to-traditional conversion. Regional Spanish and Portuguese reuse the model's base-language output where upstream translations are unavailable.

Machine-generated entries are not represented as professional, fluent-speaker review. German and Arabic overrides correct key file-management terminology. The audit checks all catalog keys, non-empty values, placeholder multisets Apple strings-file syntax and native plural dictionaries. Item and selection counts reuse the original Files plural variants, with missing/empty forms supplied in `plural-overrides.json`; right-to-left locales set both SwiftUI and AppKit layout direction. Runtime tests cover literal interpolation arguments and all 49 language resources. External command output and metadata values retain the language supplied by the system or tool.

To rebuild resources after changing code or a translation:

```sh
python3 Localization/extract_native.py
# Add translations for newly extracted keys in Localization/translations/.
python3 import_localizations.py
python3 Localization/audit_native.py
swift test --filter LocalizationTests
```

`translate_native.py` can regenerate missing machine translations with the locally prepared pinned model. Its development dependencies are ctranslate2 4.8.4, transformers 4.57.6, sentencepiece 0.2.2 and opencc-python-reimplemented 0.1.7. Translation files are checked in; rebuilding MacFiles itself does not require these packages or the model.
