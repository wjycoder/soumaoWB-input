# 搜狗五笔本地词库静态研究

研究对象：`/Library/Input Methods/SogouWBInput.app/Contents/Resources/wubi.dic` 以及同 app 的 `Contents/MacOS/SogouWBInput` arm64 slice。没有启动/修改目标程序，没有复制任何机器代码至新程序。此报告仅使用本地静态分析证据，未产生 REA Evidence ID；本地证据标识为 `DICT-01` 至 `DICT-05`。

## 已回答

- `wubi.dic` 可完整解码，但单独该文件不足以将内部字索引转换成 Unicode 或五笔编码；必须读取主程序的静态汉字及五笔表。
- 原始词记录 109,027 条，去除同词不同拼音索引重复后 107,809 个唯一词/全码配对。单字记录 21,501 条，对应 20,283 个不同汉字。
- 使用该版本显式的简码表与简码标志后，研究导出共 112,014 个不同编码/词配对。一级简码表有效 25 个，二级简码表有效 616 个。
- 可保留文件内的全局 unigram 记录顺序作为基础排名，不必使用搜狗可执行代码。实际运行时排序还可能受简码优先、匹配种类、用户学习等因素影响，未声称与搜狗当前界面逐项完全一致。

## DICT-01：源文件身份

| 文件 | SHA-256 |
|---|---|
| wubi.dic，903,884 bytes | `84076d8204d2bfbe8024de5337b746b8d140bb280b3973dedec40bd884000f11` |
| SogouWBInput universal Mach-O | `680320ddc970225d228639138f257e73818f095f5c91260c246e412d9d751815` |

头部 magic 为 `51 51 01 02`；offset `0x30` UTF-16LE 名称为“五笔分类词库”；日期字段为 `2013-9-2`。这不是对整个程序发行日期的推断。

## DICT-02：wubi.dic 布局

所有下述整数为 little-endian。

- `0x98` u32：总记录数 `0x1a9e3` = 109,027。
- `0x96` u16：每个内部汉字索引宽度，值为 2。
- 词长分组表从 `0x1a8` 开始，每组 24 bytes，组 0 为空，组 1–8 对应词长。
- 每组已解读字段：`+0` u32 count；`+4` u32 同值 count；`+8` u32 累计起始记录索引；`+12` u32 该组词内容相对 `0x280` 的偏移。其余字段没有完整解释，导出不需要。
- 词内容池从 `0x280` 开始，每条长为 `2 * 词长`，内容是 u16 汉字内部索引数组。
- unigram 顺序数组从 `0x72340` 开始，共 109,027 个 u32。高 8 bit 为词长，低 24 bit 为该词长组内的记录索引。序号 0 作为最高基础顺序。
- 最后一个顺序记录末尾正好到文件 EOF，没有忽略的末尾区域。

| 词长 | 记录数 |
|---|---:|
| 1 | 21,501 |
| 2 | 64,266 |
| 3 | 11,203 |
| 4 | 10,951 |
| 5 | 699 |
| 6 | 237 |
| 7 | 155 |
| 8 | 15 |

## DICT-03：Mach-O 静态表

研究脚本解析 fat header 选 arm64，然后解析 `LC_SEGMENT_64` 将 VA 映射为文件偏移；使用 `nm -arch arm64` 获取以下符号。地址只适用于上述 SHA-256 的版本，不应硬编码到通用导入器。

| 符号 | arm64 VA | 内容 |
|---|---|---|
| `_G_HP_HAN_ITEM_CJK` | `0x1000c0e14` | 25,577 个 4-byte 元素；前 u16 为 Unicode BMP 字符，后 u16 为拼音 ID |
| `_G_WB_WUBI_ENTRY_CJK` | `0x1000db24c` | 同汉字索引的 u32 五笔 entry |
| `_G_WB_WUBI_DATA_CJK` | `0x1000f41f0` | 间接五笔编码数据 |
| `_G_WB_WUBI_SHORT1_TABLE_CJK` | `0x1000f6a50` | a–y 索引的 u16 汉字 ID，末有 sentinel |
| `_G_WB_WUBI_SHORT2_TABLE_CJK` | `0x1000f6a84` | aa–yy 索引的 u16 汉字 ID；`0xffff` 为空；末有 sentinel |

Unicode 映射由 `_HPHan_GetHanCodes` 汇编直接支持：内部索引乘 4，然后读 u16。

完整单字码由 `_WBEncode_MakeCode` 与 `_WBEncode_MakeEncodeString` 支持：

1. 读取 `entry = WUBI_ENTRY[index]`。
2. 若 `entry & 0x8c000000 != 0`，取 `WUBI_DATA[entry & 0xffff]` 为 primary code；否则 entry 即 primary code。
3. 编码长度为 `((primary >> 20) & 3) + 1`。
4. 从 bits 15、10、5、0 依次取 5 bit，经以下表映射到 a=1，...，y=25，然后按长度截断：
   `[1,2,3,0,4,5,6,0,7,8,9,0,10,11,12,0,13,14,15,0,16,17,18,19,20,21,22,0,23,24,25,0]`。

词组编码由 `_WBEncode_MakeCode` 及 `_WB_PHRASE_WORD_POS` / `_WB_PHRASE_CODE_LEN` 的规则支持：二字词取每字前二码，三字词取前两字第一码及末字前二码，四字及以上取第一、第二、第三、最后一字的第一码。

简码由 `_WBEncode_MatchHan` 与 `_WBDictCand_GetNewItemFromShortTable` 支持：entry bit 29 / bit 28 标记二码 / 三码简码；bit 30 且没有 bit 31 时标记普通一码简码；bit 31 代表不同于 primary 首码的特殊一码，研究导出通过一级简码表处理。一级/二级表作为显式指定的优先候选，导出 `rank=-1`。这项负数约定是研究导出设计，非原文件字段。

## DICT-04：样例与顺序

- `a → 工`，`q → 我`，`r → 的`，`wq → 你`。
- `aaaa` 全码序：工、劳斯莱斯、花花草草、恭恭敬敬、工工；原始 unigram rank 分别为 2685、27385、31928、65982、69199。
- `khlg`：中国、跑车、跳车、跨国、贵国。
- `kwwl`：中华人民共和国、中体倍力。
- `ltif → 输入法`，`trwu → 我们`，`wqvb → 你好`。

## DICT-05：验证及交付

已运行检查：

- 109,027 个 unigram 引用全部合法且恰好覆盖每个词长组的每条记录一次。
- 每组词内容结束位置与下一组开始位置一致；最后一组结束于 `0x72340`。
- 顺序数组结束位置等于 EOF。
- 112,014 条导出编码均为 1–4 位 a–y，无无效字符或空码。
- Unicode/全码重复已按最高基础排名合并。
- 原 app 和原词库保持只读。

文件：

- `explore_dictionary.py`：Mach-O 映射、字表/词库解码的可重复研究脚本。
- `export_sogou_wubi_research.py`：导出及合法编码检查。
- `sogou-wubi-decoded.tsv`：112,014 条编码、词、基础排名、来源种类。
- `dictionary-summary.json`：源 SHA、计数与样例。
- `sogou-arm64.asm`：`otool -arch arm64 -tvV` 静态输出，仅作研究依据，不应打进新 app。

## 未决及边界

- 没有通过目标 app 的实时候选窗口验证所有编码的完整排序；导出的排序是文件内基础顺序，加显式简码优先。需要新 app 测试时区分完整编码与前缀补全，并明确其排序设计。
- 未导出当前用户的私人学习词库、云词库或自造词；本次对象是随安装包附带的 wubi.dic。
- 主程序还包括拼音、联想等其他资源，未纳入五笔字词重建任务。
- 某些间接 entry 后有额外数据，未声称解释其所有位；上述 primary-code 路径由实际单字匹配/造码函数支持。没有声称还原目标整个引擎。
- 当前解析器绑定本机安装版格式与符号存在性，适合本次一次性构建。若提供面向任意搜狗版本的运行时导入功能，需要加版本检测、大小边界、损坏数据拒绝逻辑。

## 构建用独立解析器（补充）

新增 `parse_sogou_wubi.py`，仅依赖 Python 标准库及 macOS 自带 `/usr/bin/nm`，不依赖探索脚本、不联网、不执行目标文件。示例：

```sh
python3 research/parse_sogou_wubi.py --output research/sogou-wubi-decoded.tsv --summary research/dictionary-summary.json
```

可用 `--dictionary` 和 `--binary` 指定来源。脚本验证 Mach-O 文件范围、词库签名/组布局、字符索引、UTF-16 BMP 合法性、所有顺序引用和输出编码；失败直接拒绝导出。新增自包含解析器输出与最初研究导出进行了逐字节 `cmp`，完全一致（112,014 配对）。所有提取工作在构建时完成；新 app 可以只携带 TSV，因此不依赖用户机器继续安装搜狗，也不需要任何网络或搜狗可执行代码。
