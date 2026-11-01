#!/usr/bin/env python3
"""Extract native UI vocabulary and interpolation templates without file/user data."""
from pathlib import Path
import re, json
ROOT=Path(__file__).resolve().parent.parent

def literals(text):
    i=0
    while i<len(text):
        if text.startswith('//',i):
            end=text.find('\n',i); i=len(text) if end<0 else end+1; continue
        if text.startswith('/*',i):
            end=text.find('*/',i+2); i=len(text) if end<0 else end+2; continue
        if text[i]!='"': i+=1; continue
        start=i; i+=1; parts=[]; count=0
        while i<len(text) and text[i]!='"':
            if text.startswith('\\(',i):
                count+=1; parts.append('%'+str(count)+'$@'); i+=2; depth=1
                while i<len(text) and depth:
                    if text[i]=='"':
                        i+=1
                        while i<len(text) and text[i]!='"': i+=2 if text[i]=='\\' else 1
                    elif text[i]=='(': depth+=1
                    elif text[i]==')': depth-=1
                    i+=1
            elif text[i]=='\\' and i+1<len(text):
                parts.append({'n':'\n','r':'\r','t':'\t','"':'"','\\':'\\'}.get(text[i+1], '\\'+text[i+1])); i+=2
            else: parts.append(text[i]); i+=1
        i+=1
        yield start,i,''.join(parts),count

TECHNICAL={'MacFiles','Finder','Quick Look','Keychain','Spotlight','Git','SFTP','FTP','FTPS','SSH','ZIP','TAR','TAR.GZ','TAR.BZ2','JSON','MD5','SHA-1','SHA-256','SHA-512','POSIX','ACL','UTF-8','UTF-16','7z','AppKit','SwiftUI'}

def human(value,context):
    if value.startswith(('POSIX file "', 'MacFiles could not write diagnostics:')): return False
    if not re.search('[A-Za-z]',value) or value in TECHNICAL: return False
    if value.startswith(('/','.','<','^','[','--','http:','https:','smb:','ftp:')): return False
    if re.match(r'^(cd|ls|put|get|chmod|rename|mkdir|rm|rmdir|ln|user =|type=|total |SITE |RNFR |RNTO |MKD |DELE )\b',value): return False
    if re.fullmatch(r'[A-Z][a-z]+',value): return True
    if re.search(r'\b(?:help|accessibilityLabel):\s*$',context): return True
    if re.search(r'(Text|Button|Label|TextField|SecureField|Toggle|Picker|TableColumn|CommandFailure|ArchiveFailure|\.help|L10n.text)\(\s*$',context): return True
    return bool(re.search(r'[A-Za-z]{2} [A-Za-z]{2}',value) and (value[0].isupper() or value.startswith('%')))

def extract():
    keys={}; templates=set()
    for path in sorted((ROOT/'Sources').glob('**/*.swift')):
        if path.name=='NativeLocalization.swift': continue
        source=path.read_text()
        for start,end,value,count in literals(source):
            if human(value,source[max(0,start-70):start]):
                keys.setdefault(value,[]).append(str(path.relative_to(ROOT)))
                if count: templates.add(value)
    (ROOT/'Localization/native-catalog.json').write_text(json.dumps({'strings':{key:{'source':key,'files':sorted(set(files))} for key,files in sorted(keys.items())}},ensure_ascii=False,indent=2)+'\n')
    (ROOT/'Sources/FilesApp/Resources/NativeTemplates.json').write_text(json.dumps(sorted(templates,key=len,reverse=True),ensure_ascii=False,indent=2)+'\n')
    print(f'Extracted {len(keys)} native strings, {len(templates)} interpolation templates')
if __name__=='__main__': extract()
