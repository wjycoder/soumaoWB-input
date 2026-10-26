#!/usr/bin/env python3
"""Read-only research export for the installed Sogou Wubi 1.0 dictionary.

No executable code is copied or run. explore_dictionary parses the Mach-O arm64
slice's static tables using nm symbol addresses. Output order derives from the
packaged dictionary's unigram array, not an observed live candidate list.
"""
from pathlib import Path
import collections
import hashlib
import json
import struct
from explore_dictionary import decode_dictionary, data, P

out=Path(__file__).parent
rows, groups, charcode, han, entries = decode_dictionary()
records={}
def add(code,word,rank,kind):
    assert 1 <= len(code) <= 4 and all('a' <= c <= 'y' for c in code), (code, word)
    key=(code,word)
    if key not in records or rank<records[key]['rank']:
        records[key]={'code':code,'word':word,'rank':rank,'kind':kind}
for row in rows: add(row['code'],row['word'],row['rank'],'full')
full_count=len(records)
# Preserve unigram ranks on flag-declared short spellings.
for row in rows:
    if row['length']!=1: continue
    value=struct.unpack_from('<I',entries,row['ids'][0]*4)[0]
    for length,flag in [(2,1<<29),(3,1<<28)]:
        if value & flag and len(row['code'])>length:
            add(row['code'][:length],row['word'],row['rank'],'short-flag')
    if value & (1<<30) and not value & (1<<31):
        add(row['code'][0],row['word'],row['rank'],'short-flag')
# The first and second level shortcut tables take precedence over ordinary
# prefix matches. Negative ranks retain that explicit preference in exports.
short_counts={}
for length, count, name in [(1,25,'_G_WB_WUBI_SHORT1_TABLE_CJK'),(2,625,'_G_WB_WUBI_SHORT2_TABLE_CJK')]:
    values=struct.unpack('<'+'H'*count,data(name,count*2)); valid=0
    for i,index in enumerate(values):
        if index==0xffff:continue
        code=chr(97+i) if length==1 else chr(97+i//25)+chr(97+i%25)
        word=chr(struct.unpack_from('<H',han,index*4)[0])
        add(code,word,-1,'short-table');valid+=1
    short_counts[length]=valid
ordered=sorted(records.values(),key=lambda r:(r['code'],r['rank'],r['word']))
with (out/'sogou-wubi-decoded.tsv').open('w') as f:
    f.write('code\tword\trank\tkind\n')
    for row in ordered:f.write('{code}\t{word}\t{rank}\t{kind}\n'.format(**row))
summary={'dictionary_sha256':hashlib.sha256(Path('/Library/Input Methods/SogouWBInput.app/Contents/Resources/wubi.dic').read_bytes()).hexdigest(),
'binary_sha256':hashlib.sha256(P.read_bytes()).hexdigest(),
'raw_records':len(rows),'unique_words':len({r['word'] for r in rows}),
'full_code_word_pairs':full_count,'exported_code_word_pairs':len(records),
'groups':{k:len(v) for k,v in groups.items()},'short_table_counts':short_counts,
'samples':{c:[r for r in ordered if r['code']==c][:8] for c in ['a','q','r','wg','wq','trn','aaaa','khlg','kwwl','ltif']}}
(out/'dictionary-summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(summary,ensure_ascii=False,indent=2))
