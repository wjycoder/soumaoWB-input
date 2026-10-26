#!/usr/bin/env python3
"""Offline read-only extraction of the installed Sogou Wubi dictionary format.

Reads static dictionary and Mach-O data tables; never executes or copies target
machine code. Uses macOS nm solely for symbol lookup. TSV rank is the stored
unigram position, except explicit short-table entries use -1 for precedence.
The application must implement its own input handling, preferences and storage.
"""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import struct
import subprocess

KEY_MAP = (1,2,3,0,4,5,6,0,7,8,9,0,10,11,12,0,13,14,15,0,16,17,18,19,20,21,22,0,23,24,25,0)


def unpack(fmt, blob, offset=0):
    size=struct.calcsize(fmt)
    if offset < 0 or offset+size > len(blob):
        raise ValueError('Invalid source data range')
    return struct.unpack_from(fmt,blob,offset)


class StaticTables:
    def __init__(self,path):
        self.path=Path(path)
        original=self.path.read_bytes()
        self.sha256=hashlib.sha256(original).hexdigest()
        blob=original
        magic=unpack('>I',blob)[0]
        if magic==0xcafebabe:
            count=unpack('>I',blob,4)[0]
            if count>64: raise ValueError('Invalid universal architecture count')
            for i in range(count):
                cpu,sub,offset,size,align=unpack('>IIIII',blob,8+20*i)
                if cpu==0x100000c:
                    if offset+size>len(blob):raise ValueError('Invalid arm64 slice')
                    blob=blob[offset:offset+size]
                    break
            else:raise ValueError('No arm64 slice')
        if unpack('<I',blob)[0]!=0xfeedfacf or unpack('<I',blob,4)[0]!=0x100000c:
            raise ValueError('Expected an arm64 Mach-O slice')
        self.blob=blob
        count=unpack('<I',blob,16)[0]
        if count>65536:raise ValueError('Invalid Mach-O command count')
        pos=32
        self.segments=[]
        for i in range(count):
            cmd,size=unpack('<II',blob,pos)
            if size<8 or pos+size>len(blob):raise ValueError('Invalid Mach-O command')
            if cmd==0x19:
                name,vm,vm_size,file_offset,file_size=unpack('<16sQQQQ',blob,pos+8)
                if file_offset+file_size>len(blob):raise ValueError('Invalid Mach-O segment')
                self.segments.append((vm,file_offset,file_size))
            pos+=size
        symbols=subprocess.run(['/usr/bin/nm','-arch','arm64',str(self.path)],check=True,capture_output=True,text=True).stdout
        self.symbols={}
        for line in symbols.splitlines():
            parts=line.split()
            if len(parts)==3:
                try:self.symbols[parts[2]]=int(parts[0],16)
                except ValueError:pass

    def read(self,symbol,size,offset=0):
        if symbol not in self.symbols:raise ValueError('Missing static symbol: '+symbol)
        va=self.symbols[symbol]+offset
        for vm,file_offset,file_size in self.segments:
            if vm<=va and va+size<=vm+file_size:
                start=file_offset+va-vm
                return self.blob[start:start+size]
        raise ValueError('Static table extends beyond a file-backed segment: '+symbol)


def extract(dictionary,binary):
    dictionary=Path(dictionary)
    blob=dictionary.read_bytes()
    if blob[:4]!=b'QQ\x01\x02':raise ValueError('Unsupported dictionary signature')
    count=unpack('<I',blob,0x98)[0]
    max_length,width=unpack('<HH',blob,0x94)
    if max_length!=8 or width!=2:raise ValueError('Unsupported dictionary record format')
    body=0x1a8
    phrase_start=body+unpack('<I',blob,0xf8)[0]
    rank_start=body+unpack('<I',blob,0x118)[0]
    if phrase_start!=body+24*(max_length+1):raise ValueError('Unsupported group layout')
    if rank_start+count*4!=len(blob):raise ValueError('Invalid unigram array size')
    tables=StaticTables(binary)
    char_count=unpack('<H',tables.read('_G_HP_HAN_DATA_CJK',2))[0]
    chars=tables.read('_G_HP_HAN_ITEM_CJK',char_count*4)
    entries=tables.read('_G_WB_WUBI_ENTRY_CJK',char_count*4)
    def unicode(index):
        if index>=char_count:raise ValueError('Invalid character index')
        value=unpack('<H',chars,index*4)[0]
        if not value or 0xd800<=value<=0xdfff:raise ValueError('Invalid BMP character')
        return chr(value)
    def full_code(index):
        value=unpack('<I',entries,index*4)[0]
        if value&0x8c000000:
            value=unpack('<I',tables.read('_G_WB_WUBI_DATA_CJK',4,4*(value&0xffff)))[0]
        length=((value>>20)&3)+1
        return ''.join(chr(96+KEY_MAP[(value>>shift)&31]) for shift in (15,10,5,0))[:length]
    groups={}
    expected_offset=0
    expected_index=0
    for length in range(1,max_length+1):
        group_count,duplicate_count,index,offset=unpack('<IIII',blob,body+24*length)
        if group_count!=duplicate_count or index!=expected_index or offset!=expected_offset:
            raise ValueError('Inconsistent dictionary group header')
        group=[]
        for j in range(group_count):
            ids=unpack('<'+'H'*length,blob,phrase_start+offset+j*2*length)
            word=''.join(unicode(i) for i in ids)
            codes=[full_code(i) for i in ids]
            if length==1:code=codes[0]
            elif length==2:code=codes[0][:2]+codes[1][:2]
            elif length==3:code=codes[0][0]+codes[1][0]+codes[2][:2]
            else:code=codes[0][0]+codes[1][0]+codes[2][0]+codes[-1][0]
            group.append((word,code,ids))
        groups[length]=group
        expected_index+=group_count
        expected_offset+=group_count*length*2
    if expected_index!=count or phrase_start+expected_offset!=rank_start:
        raise ValueError('Dictionary content does not cover the expected range')
    records={}
    def add(code,word,rank,kind):
        if not 1<=len(code)<=4 or any(not 'a'<=c<='y' for c in code):
            raise ValueError('Invalid derived code: '+repr((code,word)))
        key=(code,word)
        if key not in records or rank<records[key][2]:records[key]=(code,word,rank,kind)
    visited=set()
    single=[]
    words=set()
    for rank in range(count):
        value=unpack('<I',blob,rank_start+4*rank)[0]
        length,index=value>>24,value&0xffffff
        if length not in groups or index>=len(groups[length]) or (length,index) in visited:
            raise ValueError('Invalid or duplicate unigram reference')
        visited.add((length,index))
        word,code,ids=groups[length][index]
        words.add(word)
        add(code,word,rank,'full')
        if length==1:single.append((word,code,ids[0],rank))
    full_count=len(records)
    for word,code,index,rank in single:
        value=unpack('<I',entries,index*4)[0]
        for length,flag in ((2,1<<29),(3,1<<28)):
            if value&flag and len(code)>length:add(code[:length],word,rank,'short-flag')
        if value&(1<<30) and not value&(1<<31):add(code[0],word,rank,'short-flag')
    short_counts={}
    for length,size,name in ((1,25,'_G_WB_WUBI_SHORT1_TABLE_CJK'),(2,625,'_G_WB_WUBI_SHORT2_TABLE_CJK')):
        values=unpack('<'+'H'*size,tables.read(name,2*size))
        short_counts[length]=0
        for i,index in enumerate(values):
            if index==0xffff:continue
            code=chr(97+i) if length==1 else chr(97+i//25)+chr(97+i%25)
            add(code,unicode(index),-1,'short-table')
            short_counts[length]+=1
    ordered=sorted(records.values(),key=lambda r:(r[0],r[2],r[1]))
    summary={'dictionary_sha256':hashlib.sha256(blob).hexdigest(),'binary_sha256':tables.sha256,
             'raw_records':count,'unique_words':len(words),'full_code_word_pairs':full_count,
             'exported_code_word_pairs':len(ordered),'groups':{k:len(v) for k,v in groups.items()},
             'short_table_counts':short_counts,'validation':'All group ranges contiguous; every unigram referenced exactly once; EOF exact; all derived codes valid.'}
    return ordered,summary


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dictionary',type=Path,default=Path('/Library/Input Methods/SogouWBInput.app/Contents/Resources/wubi.dic'))
    parser.add_argument('--binary',type=Path,default=Path('/Library/Input Methods/SogouWBInput.app/Contents/MacOS/SogouWBInput'))
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--summary',type=Path)
    args=parser.parse_args()
    rows,summary=extract(args.dictionary,args.binary)
    with args.output.open('w',encoding='utf-8') as f:
        f.write('code\tword\trank\tkind\n')
        for code,word,rank,kind in rows:f.write(f'{code}\t{word}\t{rank}\t{kind}\n')
    result=json.dumps(summary,ensure_ascii=False,indent=2)+'\n'
    if args.summary:args.summary.write_text(result,encoding='utf-8')
    print(result,end='')

if __name__=='__main__':main()
