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

## 计划中(后续引入,届时在此补全署名)

- **JMdict / KANJIDIC2** —— © James William Breen & EDRDG,CC BY-SA 4.0 —— <https://www.edrdg.org/edrdg/licence.html>
- **例句** —— Tatoeba(<https://tatoeba.org>),CC BY 2.0 FR(目前例句为 LLM 原创,未取自 Tatoeba)
- **词频(可选)** —— wordfreq,CC BY-SA 4.0
