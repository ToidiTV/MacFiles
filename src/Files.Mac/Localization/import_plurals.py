#!/usr/bin/env python3
"""Convert Files ICU item-count variants into native Apple strings dictionaries."""
from pathlib import Path
import re,plistlib,json,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parent.parent

def read(path): return {n.attrib['name']:n.findtext('value','') for n in ET.parse(path).getroot().findall('data')}
def variants(value,index=0):
    match=re.search(r'\{'+str(index)+r',\s*plural,\s*',value)
    if not match:return {}
    position=match.end(); result={}
    while position<len(value):
        match=re.match(r'\s*(zero|one|two|few|many|other)\s*\{',value[position:])
        if not match:break
        category=match[1];position+=match.end();start=position;depth=1
        while position<len(value) and depth:
            if value[position]=='{':depth+=1
            elif value[position]=='}':depth-=1
            position+=1
        result[category]=value[start:position-1]
    return result

def entry(forms):
    result={'NSStringFormatSpecTypeKey':'NSStringPluralRuleType','NSStringFormatValueTypeKey':'ld'}
    for key,value in forms.items():
        value=value.replace('%','%%').replace('#','%ld').replace('{0}','%ld').replace("''", "'")
        if '{' in value or '}' in value:continue
        result[key]=value
    if not result.get('other','').strip():raise ValueError('Missing plural fallback')
    for key in list(result):
        if not str(result[key]).strip():result[key]=result['other']
    return {'NSStringLocalizedFormatKey':'%#@count@','count':result}

def build():
    source=ROOT.parent/'Files.App/Strings';english=read(source/'en-US/Resources.resw')
    overrides=json.loads((ROOT/'Localization/plural-overrides.json').read_text())
    for path in source.glob('*/Resources.resw'):
        translated=read(path);locale='en' if path.parent.name=='en-US' else path.parent.name
        item=variants(translated.get('DetailsArchiveItems',''))
        if not item:
            item={cat:'# '+word for cat,word in variants(translated.get('Items',english['Items'])).items()}
        selected=variants(translated.get('SelectedItems',english['SelectedItems']))
        if not selected:selected=variants(english['SelectedItems'])
        target=ROOT/'Sources/FilesApp/Resources'/(locale+'.lproj')/'Localizable.stringsdict'
        values={'NativeItemCount':entry(item),'NativeSelectedCount':entry(selected)}
        for key,forms in overrides.get(locale,{}).items():
            values[key]={'NSStringLocalizedFormatKey':'%#@count@','count':{'NSStringFormatSpecTypeKey':'NSStringPluralRuleType','NSStringFormatValueTypeKey':'ld',**forms}}
        target.write_bytes(plistlib.dumps(values,sort_keys=True))
    print('Imported native plural rules for 49 locales')
if __name__=='__main__':build()
