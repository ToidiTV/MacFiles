#!/usr/bin/env python3
"""Route native UI text through the same catalog as SwiftUI resources."""
from pathlib import Path
import re
from extract_native import literals
ROOT=Path(__file__).resolve().parent.parent
CALLS=r'(?:Text|Button|Label|TextField|SecureField|Toggle|Picker|TableColumn|Section|Menu|CommandMenu|\.help|\.accessibilityLabel)'
for path in (ROOT/'Sources/FilesApp').glob('**/*.swift'):
    if path.name=='SettingsService.swift': continue
    source=path.read_text(); changes=[]
    for start,end,value,count in literals(source):
        context=source[max(0,start-100):start]
        if re.search(CALLS+r'\(\s*$',context) and value:
            changes.append((start,end,'L10n.text('+source[start:end]+')'))
        elif re.search(r'\.(?:messageText|informativeText|prompt|title)\s*=\s*$',context):
            changes.append((start,end,'L10n.text('+source[start:end]+')'))
        elif re.search(r'addButton\(withTitle:\s*$',context):
            changes.append((start,end,'L10n.text('+source[start:end]+')'))
    for start,end,value in reversed(changes): source=source[:start]+value+source[end:]
    for expression in ['$0.rawValue','mode.rawValue','field.rawValue','action.title','request.kind.rawValue','message','error','model.statusMessage','session.message']:
        source=source.replace('Text('+expression+')','Text(L10n.text('+expression+'))')
    path.write_text(source)
p=ROOT/'Sources/FilesApp/Services/SettingsService.swift'
s=p.read_text().replace('NSLocalizedString(key, bundle: .module, comment: "")','NativeLocalization.text(key)')
if 'NativeLocalization.configure(bundle: .module)' not in s:
    s=s.replace('    private init() {','    private init() {\n        NativeLocalization.configure(bundle: .module)')
p.write_text(s)
for name in ['ProcessService.swift','ArchiveService.swift','MacStorageService.swift']:
    p=ROOT/'Sources/FilesStorage'/name;s=p.read_text()
    if 'import FilesShared' not in s:s=s.replace('import Foundation','import Foundation\nimport FilesShared',1)
    s=s.replace('public var errorDescription: String? { message }','public var errorDescription: String? { NativeLocalization.text(message) }')
    if name=='MacStorageService.swift':
        # LocalizedError return literals are user-facing; enum case identities are unchanged.
        a=s.index('    public var errorDescription:');b=s.index('\n}\n',a)
        part=s[a:b];part=re.sub(r'return ("(?:[^"\\]|\\.)*")',r'return NativeLocalization.text(\1)',part);s=s[:a]+part+s[b:]
    p.write_text(s)
