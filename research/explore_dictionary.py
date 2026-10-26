from pathlib import Path
import struct, subprocess
P=Path('/Library/Input Methods/SogouWBInput.app/Contents/MacOS/SogouWBInput')
b=P.read_bytes();magic,n=struct.unpack_from('>II',b)
if magic==0xcafebabe:
 for i in range(n):
  cpu,sub,off,size,align=struct.unpack_from('>IIIII',b,8+i*20)
  if cpu==0x100000c:b=b[off:off+size];break
n=struct.unpack_from('<I',b,16)[0]; p=32; seg=[]
for i in range(n):
 cmd,size=struct.unpack_from('<II',b,p)
 if cmd==0x19:
  name,vm,vs,fo,fs=struct.unpack_from('<16sQQQQ',b,p+8);seg.append((vm,vs,fo,fs))
 p+=size
def read(va,size):
 for vm,vs,fo,fs in seg:
  if vm<=va and va+size<=vm+fs:return b[fo+va-vm:fo+va-vm+size]
 raise ValueError(hex(va))
nms=subprocess.check_output(['nm','-arch','arm64',str(P)],text=True); syms={r.split()[-1]:int(r.split()[0],16) for r in nms.splitlines() if len(r.split())==3 and r.split()[0]!='U'}
def data(name,size):return read(syms[name],size)
if __name__=='__main__':
 for name in ['_G_HP_HAN_DATA_CJK','_G_HP_HAN_ITEM_CJK','_G_WB_ENCODE_DATA_CJK','_G_WB_WUBI_ENTRY_CJK','_G_WB_WUBI_DATA_CJK','_G_WB_WUBI_SHORT1_TABLE_CJK','_G_WB_WUBI_SHORT1_HIFREQ_CJK']:
  print(name,hex(syms[name]),data(name,64).hex(' '))
 dic=Path('/Library/Input Methods/SogouWBInput.app/Contents/Resources/wubi.dic').read_bytes()
 for idx in struct.unpack_from('<100H',dic,0x280):print(idx,read(syms['_G_HP_HAN_ITEM_CJK']+4*idx,4).hex(),read(syms['_G_HP_HAN_ITEM_CJK']+4*idx,2).decode('utf-16le'),end='; ')
 print()

def decode_dictionary():
 dic=Path('/Library/Input Methods/SogouWBInput.app/Contents/Resources/wubi.dic').read_bytes()
 nchar=struct.unpack_from('<H',data('_G_HP_HAN_DATA_CJK',2))[0]
 han=data('_G_HP_HAN_ITEM_CJK',nchar*4); entries=data('_G_WB_WUBI_ENTRY_CJK',nchar*4)
 keymap=bytes([1,2,3,0,4,5,6,0,7,8,9,0,10,11,12,0,13,14,15,0,16,17,18,19,20,21,22,0,23,24,25,0])
 def code(x):
  return ''.join(chr(96+keymap[(x>>p)&31]) for p in (15,10,5,0))[:((x>>20)&3)+1]
 def charcode(i):
  v=struct.unpack_from('<I',entries,4*i)[0]
  if v&0x8c000000:v=struct.unpack('<I',read(syms['_G_WB_WUBI_DATA_CJK']+4*(v&65535),4))[0]
  return code(v)
 groups={};rows=[]
 for length in range(1,9):
  count,_,idx,offset=struct.unpack_from('<IIII',dic,0x1a8+length*24)
  g=[]
  for j in range(count):
   ids=struct.unpack_from('<'+str(length)+'H',dic,0x280+offset+j*2*length)
   word=''.join(chr(struct.unpack_from('<H',han,4*i)[0]) for i in ids)
   cc=[charcode(i) for i in ids]
   c=cc[0] if length==1 else cc[0][:2]+cc[1][:2] if length==2 else cc[0][0]+cc[1][0]+cc[2][:2] if length==3 else cc[0][0]+cc[1][0]+cc[2][0]+cc[-1][0]
   r={'word':word,'code':c,'ids':ids,'length':length,'group_index':j};g.append(r)
  groups[length]=g
 for rank in range(0x1a9e3):
  val=struct.unpack_from('<I',dic,0x72340+rank*4)[0]; length=val>>24;j=val&0xffffff;r=groups[length][j].copy();r['rank']=rank;rows.append(r)
 return rows,groups,charcode,han,entries
