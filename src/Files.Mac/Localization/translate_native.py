#!/usr/bin/env python3
"""Generate missing native UI translations locally with the pinned M2M100 model."""
from pathlib import Path
import json,re,time,sys,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parent.parent

def resw(path): return {n.attrib['name']:n.findtext('value','') for n in ET.parse(path).getroot().findall('data')}
def normalize(s): return re.sub(r'[\s….:&_-]+',' ',s).strip().casefold()
PROTECTED=re.compile(r"[⌘⌥⌃⇧][^\s]*|%\d+\$@|\.MacFiles-Recovery|\b(?:MacFiles|macOS|Finder|Quick Look|Keychain|Spotlight|Windows|iCloud|File Provider|POSIX|ACL|FTP|FTPS|SFTP|SSH|TLS|ZIP|TAR|7z|MD5|SHA-1|SHA-256|SHA-512|UTF-8|UTF-16|JSON|SMB|AFP|WebDAV|APFS|NTFS|Git|UID|GID|NUL|Mach-O)\b")
def spans(value):
    pieces=[]; end=0
    for match in PROTECTED.finditer(value):
        pieces.append(value[end:match.start()]); pieces.append(match.group()); end=match.end()
    pieces.append(value[end:]); return pieces

def main():
    import argparse
    parser=argparse.ArgumentParser(); parser.add_argument('--partition',type=int,default=-1); args=parser.parse_args()
    import ctranslate2
    from transformers import M2M100Tokenizer
    from opencc import OpenCC
    source=ROOT.parent/'Files.App/Strings'
    english=resw(source/'en-US/Resources.resw')
    english_keys={normalize(v):k for k,v in english.items() if v and '{' not in v}
    catalog=json.loads((ROOT/'Localization/native-catalog.json').read_text())['strings']
    tokenizer=M2M100Tokenizer.from_pretrained(str(ROOT/'work/translation-model-source'),src_lang='en')
    translator=ctranslate2.Translator(str(ROOT/'work/translation-model-int8'),device='cpu',inter_threads=1,intra_threads=3)
    destination=ROOT/'Localization/translations'; destination.mkdir(exist_ok=True)
    cache={}; started=time.time(); total=0
    paths=sorted(source.glob('*/Resources.resw'),key=lambda p:(p.parent.name!='de-DE',p.parent.name))
    for path in paths:
        locale='en' if path.parent.name=='en-US' else path.parent.name
        lang={'nb':'no','fil':'tl'}.get(locale.split('-')[0],locale.split('-')[0])
        if args.partition >= 0 and sum(map(ord,lang)) % 2 != args.partition: continue
        target=destination/(locale+'.json')
        values=json.loads(target.read_text()) if target.exists() else {}
        upstream=resw(path); missing=[]
        for key in catalog:
            shortcut=re.match(r'^(.*?)( · [⌘⌥⌃⇧].*)$',key)
            if shortcut:
                original=english_keys.get(normalize(shortcut[1]))
                if original and upstream.get(original): values[key]={'text':upstream[original]+shortcut[2],'origin':'Files:'+original}
                elif key in values and shortcut[2] not in values[key]['text']: del values[key]
            alias={'Kind':'Type','Done':'Close','Trash':'Recycle Bin'}.get(key)
            original=english_keys.get(normalize(alias)) if alias else None
            if original and upstream.get(original): values[key]={'text':upstream[original],'origin':'Files:'+original}
            if key.startswith("Finder's") and key in values and values[key].get('origin','').startswith('M2M'):
                values[key]['text']=re.sub(r'Finder(?=\w)', 'Finder ', values[key]['text'])
            if key == 'System' and upstream.get('SystemTimeStyle'):
                values[key]={'text':upstream['SystemTimeStyle'],'origin':'Files:SystemTimeStyle'}
            if key in values and values[key].get('origin','').startswith('M2M') and PROTECTED.search(key) and values[key].get('strategy') != 2: del values[key]
            if key in values: continue
            original=english_keys.get(normalize(key))
            translation=upstream.get(original) if original else None
            if lang=='en': values[key]={'text':key,'origin':'native-English'}
            elif translation and translation!=english[original] and '%' not in key:
                values[key]={'text':translation,'origin':'Files:'+original}
            else: missing.append(key)
        if lang not in cache:
            cachepath=ROOT/'work'/('translation-cache-'+lang+'.json')
            cache[lang]=json.loads(cachepath.read_text()) if cachepath.exists() else {}
        memory=cache[lang]
        # Translate literal spans separately so positional format arguments cannot be lost or rewritten.
        segments=list(dict.fromkeys(part.strip() for key in missing for part in spans(key) if part.strip() and not PROTECTED.fullmatch(part) and re.search('[A-Za-z]',part) and part.strip() not in memory))
        for part in list(segments):
            original=english_keys.get(normalize(part))
            if original and upstream.get(original) and upstream[original] != english[original]:
                memory[part]=upstream[original]; segments.remove(part)
        print(locale, 'missing' ,len(missing),'new spans',len(segments),flush=True)
        for offset in range(0,len(segments),64):
            batch=segments[offset:offset+64]
            inputs=[tokenizer.convert_ids_to_tokens(tokenizer.encode(s)) for s in batch]
            results=translator.translate_batch(inputs,target_prefix=[[tokenizer.get_lang_token(lang)]]*len(inputs),beam_size=2,max_decoding_length=256,repetition_penalty=1.05)
            for original,result in zip(batch,results):
                tokens=result.hypotheses[0]
                translated=tokenizer.decode(tokenizer.convert_tokens_to_ids(tokens),skip_special_tokens=True).strip()
                memory[original]=translated or original
            (ROOT/'work'/('translation-cache-'+lang+'.json')).write_text(json.dumps(memory,ensure_ascii=False,indent=2)+'\n')
            total+=len(batch)
            print(locale,offset+len(batch),'/',len(segments),'total',total,'seconds',round(time.time()-started),flush=True)
        for key in missing:
            parts=[]
            for part in spans(key):
                if PROTECTED.fullmatch(part): parts.append(part); continue
                text=memory.get(part.strip(),part.strip())
                parts.append(part[:len(part)-len(part.lstrip())]+text+part[len(part.rstrip()):] if part.strip() else part)
            value=''.join(parts)
            if locale=='zh-Hant': value=OpenCC('s2t').convert(value)
            values[key]={'text':value,'origin':'M2M100-418M-local','strategy':2}
        target.write_text(json.dumps(values,ensure_ascii=False,indent=2,sort_keys=True)+'\n')
        print('Completed',locale,len(values),flush=True)
if __name__=='__main__': main()
