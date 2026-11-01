#!/usr/bin/env python3
"""Validate native catalog completeness, placeholders and packaged .strings syntax."""
from pathlib import Path
import collections,json,re,subprocess,sys,plistlib
ROOT=Path(__file__).resolve().parent.parent
catalog=json.loads((ROOT/'Localization/native-catalog.json').read_text())['strings']
placeholder=re.compile(r'%\d+\$@')
line=re.compile(r'^("(?:[^"\\]|\\.)*") = ("(?:[^"\\]|\\.)*");$')
errors=[]; summary={}
for folder in sorted((ROOT/'Sources/FilesApp/Resources').glob('*.lproj')):
    locale=folder.stem; path=ROOT/'Localization/translations'/(locale+'.json')
    if not path.exists(): errors.append(locale+': native catalog missing'); continue
    values=json.loads(path.read_text()); overrides=ROOT/'Localization/overrides'/(locale+'.json')
    if overrides.exists(): values.update({k:{'text':v,'origin':'reviewed-override'} for k,v in json.loads(overrides.read_text()).items()})
    origins=collections.Counter()
    for key in catalog:
        if key not in values: errors.append(locale+': missing '+key); continue
        entry=values[key]; text=entry['text']; origins[entry['origin'].split(':')[0]]+=1
        if re.findall(r'[⌘⌥⌃⇧][^\s]*',key)!=re.findall(r'[⌘⌥⌃⇧][^\s]*',text): errors.append(locale+': invalid shortcut label '+key)
        if not text.strip(): errors.append(locale+': empty '+key)
        if collections.Counter(placeholder.findall(key))!=collections.Counter(placeholder.findall(text)): errors.append(locale+': invalid placeholders '+key)
    resource=folder/'Localizable.strings'; parsed={}
    for raw in resource.read_text().splitlines():
        match=line.fullmatch(raw)
        if match: parsed[json.loads(match[1])]=json.loads(match[2])
    for key in catalog:
        if key not in parsed: errors.append(locale+': key absent from resource '+key)
        elif key in values and parsed[key]!=values[key]['text']: errors.append(locale+': stale resource '+key)
    result=subprocess.run(['/usr/bin/plutil','-lint',str(resource)],capture_output=True,text=True)
    if result.returncode: errors.append(locale+': invalid strings file '+result.stdout+result.stderr)
    dictionary=folder/'Localizable.stringsdict'
    try:
        plural=plistlib.loads(dictionary.read_bytes())
        for key in ['NativeItemCount','NativeSelectedCount']:
            entry=plural[key]
            assert entry['NSStringLocalizedFormatKey']=='%#@count@'
            rule=entry['count']
            assert rule['NSStringFormatSpecTypeKey']=='NSStringPluralRuleType'
            assert rule['NSStringFormatValueTypeKey']=='ld'
            assert rule['other'].strip()
            for category,value in rule.items():
                if category.startswith('NSString'): continue
                assert category in ['zero','one','two','few','many','other']
                assert value.strip() and not re.search(r'%(?!ld|%)|[{}]',value)
    except Exception as error: errors.append(locale+': invalid plural dictionary '+str(error))
    summary[locale]={'nativeKeys':sum(k in values for k in catalog),'origins':dict(origins)}
report={'catalogKeys':len(catalog),'locales':len(summary),'complete':not errors,'errors':errors,'coverage':summary}
out=ROOT/'work/localization-audit.json';out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:report[k] for k in ['catalogKeys','locales','complete']}))
for error in errors[:25]: print(error)
if errors:sys.exit(1)
