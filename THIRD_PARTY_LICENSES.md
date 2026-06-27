# 第三方数据与代码署名

## Google Mozc —— 罗马字映射表

`Sources/RomajiKana/Resources/romaji-hiragana.tsv` 取自 Google Mozc(Google 日本語入力开源版)
<https://github.com/google/mozc>,文件路径 `src/data/preedit/romanji-hiragana.tsv`,
按 **BSD-3-Clause** 许可使用。

```
Copyright 2010-2018, Google Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Google Inc. nor the names of its contributors may be
      used to endorse or promote products derived from this software without
      specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
```

设计上还参考了 **WanaKana**(<https://github.com/WaniKani/WanaKana>,MIT)的 trie / 促音生成思路。

## JLPT 词表读音/等级(已使用)

部分词条的**词形、假名读音与 JLPT 等级**取自 **Bluskyo/JLPT_Vocabulary**
(<https://github.com/Bluskyo/JLPT_Vocabulary>,MIT),其数据转换自 **Jonathan Waller's
JLPT Resources**(<https://www.tanos.co.uk/jlpt/>,**CC BY**)。释义(中/英)为本项目
原创 / LLM 起草并校验,非取自上述来源。按 CC BY 要求,应在 App「关于/致谢」页署名:
*"JLPT vocabulary readings & levels based on Jonathan Waller's JLPT Resources (tanos.co.uk), CC BY."*

## Tatoeba —— 用作灵感来源(部分句子衍生)

Practice 模式的「文章/句子」语料(`Sources/VocabKit/Resources/passages.json`,共 183 篇)以
**Tatoeba Project**(<https://tatoeba.org>,**CC BY 2.0 FR**)的日文纯假名句子库为**灵感与种子**
构建:Gemini 3.1 Pro 在 Tatoeba 句池(我们仅取纯假名子集 ~4500 条)中精选并改写、扩展为 183 篇
**学习者友好的中长段落**。每条的**英文/中文翻译均为本项目原创(LLM 起草 + 人工裁定)**,**主题
标签、难度评级**亦由我们添加。

实际上仅约 **9 篇**(占 5%)的日文与某条 Tatoeba 句子精确匹配;其余 **174 篇**是 LLM 原创的
单句或多句段落,Tatoeba 是间接灵感而非逐字来源。出于安全与透明,我们仍按 CC BY 要求在「关于/
致谢」页保留署名:
*"Practice sentences inspired by the Tatoeba Project (tatoeba.org), CC BY 2.0 FR."*

## EDRDG — JMdict / EDICT(动词变形,v1.6)

- **JMdict_e** —— © James William Breen & the Electronic Dictionary Research and
  Development Group (EDRDG),**CC BY-SA 4.0** —— <https://www.edrdg.org/jmdict/j_jmdict.html>
  / <https://www.edrdg.org/edrdg/licence.html>
- **用途**:在**构建/数据派生阶段**用 JMdict 的动词词类(v1 / v5x / vs / kuru)为词库派生
  每个动词的变形类标签 `vc`(`scripts/enrich_verb_classes.py --jmdict … --write`)。
- **只 ship 派生事实**:发布包内**仅含派生出来的类标签字符串**(如 `"godan_r"`),**不含
  JMdict 的任何词典文本/释义/例句**。署名在 app 内「关于/致谢」页常设展示(CC BY-SA 要求)。

## 计划中(后续引入,届时在此补全署名)

- **KANJIDIC2** —— © James William Breen & EDRDG,CC BY-SA 4.0 —— <https://www.edrdg.org/edrdg/licence.html>
- **词频(可选)** —— wordfreq,CC BY-SA 4.0
