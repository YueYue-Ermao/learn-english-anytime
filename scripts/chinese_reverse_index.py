#!/usr/bin/env python3
"""Shared helpers for building a compact Chinese-to-English ECDICT index."""

from __future__ import annotations

import re
from collections.abc import Iterator


TERM_SPLITTER = re.compile(r"[\\n\n,，;；、/|]+")
BRACKETED_LABEL = re.compile(r"\[[^\]]*\]")
PARENTHETICAL = re.compile(r"[（(][^）)]*[）)]")
PART_OF_SPEECH = re.compile(
    r"^(?:(?:n|v|vt|vi|adj|adv|a|ad|prep|pron|conj|int|num|aux|abbr|pl)\.\s*)+",
    re.IGNORECASE,
)
HAN_TERM = re.compile(r"^[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]{1,8}$")
STOP_TERMS = {
    "的",
    "地",
    "得",
    "了",
    "着",
    "和",
    "与",
    "或",
    "在",
    "是",
    "为",
    "把",
    "被",
    "及",
    "之",
}

# High-confidence workplace mappings correct cases where ECDICT's English-first
# glosses are valid but not the most useful answer for a Chinese-first lookup.
CURATED_MAPPINGS: dict[str, tuple[str, ...]] = {
    "项目": ("project", "initiative"),
    "产品": ("product",),
    "产品经理": ("product manager",),
    "经理": ("manager",),
    "面试": ("interview",),
    "简历": ("résumé", "CV"),
    "需求": ("requirement", "need"),
    "用户": ("user",),
    "客户": ("customer", "client"),
    "目标": ("goal", "objective"),
    "优先": ("prioritize", "priority", "first"),
    "优先级": ("priority",),
    "负责": ("own",),
    "推进": ("drive", "advance"),
    "协调": ("coordinate",),
    "沟通": ("communicate", "communication"),
    "合作": ("collaborate", "collaboration"),
    "交付": ("deliver", "delivery"),
    "上线": ("launch", "release"),
    "迭代": ("iterate", "iteration"),
    "评估": ("assess", "evaluate"),
    "方案": ("solution", "approach"),
    "影响": ("impact",),
    "结果": ("result", "outcome"),
    "数据": ("data",),
    "指标": ("metric",),
    "增长": ("growth",),
    "转化": ("conversion",),
    "留存": ("retention",),
    "成本": ("cost",),
    "收益": ("benefit", "revenue"),
    "风险": ("risk",),
    "机会": ("opportunity",),
    "问题": ("issue", "problem"),
    "挑战": ("challenge",),
    "决策": ("decision",),
    "团队": ("team",),
    "经验": ("experience",),
    "能力": ("capability", "ability"),
    "优势": ("strength", "advantage"),
    "缺点": ("weakness",),
    "职责": ("responsibility",),
    "公司": ("company",),
    "市场": ("market",),
    "战略": ("strategy",),
    "执行": ("execution", "execute"),
    "反馈": ("feedback",),
    "改进": ("improve", "improvement"),
    "规划": ("planning", "plan", "roadmap"),
    "路线图": ("roadmap",),
    "场景": ("scenario", "context"),
    "背景": ("background", "context"),
    "资源": ("resource",),
    "进度": ("progress",),
    "质量": ("quality",),
    "效率": ("efficiency",),
    "价值": ("value",),
    "取舍": ("trade-off",),
    "权衡": ("trade-off", "balance"),
    "对齐": ("align", "alignment"),
    "共识": ("consensus",),
    "复盘": ("retrospective", "review"),
    "会议": ("meeting",),
    "汇报": ("report", "presentation"),
    "晋升": ("promotion",),
    "薪资": ("salary", "compensation"),
    "薪酬": ("compensation",),
    "远程": ("remote",),
    "加班": ("overtime",),
    "截止日期": ("deadline",),
    "里程碑": ("milestone",),
    "优化": ("optimize", "improve"),
    "验证": ("validate", "verify"),
    "假设": ("hypothesis", "assumption"),
    "调研": ("research",),
    "洞察": ("insight",),
    "趋势": ("trend",),
    "流程": ("process", "workflow"),
    "功能": ("feature", "function"),
    "技术": ("technology",),
    "开发": ("development", "develop"),
    "测试": ("test",),
    "设计": ("design",),
    "运营": ("operations",),
    "销售": ("sales",),
    "可行性": ("feasibility",),
    "依赖": ("dependency",),
    "瓶颈": ("bottleneck",),
    "建议": ("suggestion", "recommendation"),
}


def chinese_terms(translation: str) -> list[str]:
    """Extract exact, compact Han terms rather than arbitrary substrings."""
    terms: list[str] = []
    seen: set[str] = set()
    for raw_value in TERM_SPLITTER.split(translation):
        value = BRACKETED_LABEL.sub("", raw_value).strip()
        value = PART_OF_SPEECH.sub("", value).strip()
        value = PARENTHETICAL.sub("", value).strip()
        value = value.strip(" .:：-—_+*'\"“”‘’!?！？")
        if not HAN_TERM.fullmatch(value) or value in STOP_TERMS or value in seen:
            continue
        seen.add(value)
        terms.append(value)
    return terms


def is_reverse_candidate(
    word: str,
    translation: str,
    collins: int,
    oxford: int,
    bnc: int,
    frequency: int,
) -> bool:
    return (
        bool(translation)
        and " " not in word
        and len(word) <= 40
        and (collins > 0 or oxford > 0 or bnc > 0 or frequency > 0)
    )


def reverse_rank(
    collins: int,
    oxford: int,
    bnc: int,
    frequency: int,
    term_position: int,
) -> int:
    rank = collins * 1_000_000 + oxford * 500_000
    if bnc > 0:
        rank += max(0, 100_000 - bnc) * 3
    if frequency > 0:
        rank += max(0, 100_000 - frequency) * 2
    rank += max(0, 10_000 - term_position * 250)
    return rank


def reverse_rows(
    word: str,
    translation: str,
    collins: int,
    oxford: int,
    bnc: int,
    frequency: int,
) -> Iterator[tuple[str, str, int]]:
    if not is_reverse_candidate(
        word,
        translation,
        collins,
        oxford,
        bnc,
        frequency,
    ):
        return
    for position, term in enumerate(chinese_terms(translation)):
        yield (
            term,
            word,
            reverse_rank(collins, oxford, bnc, frequency, position),
        )


def curated_rows() -> Iterator[tuple[str, str, int]]:
    for term, words in CURATED_MAPPINGS.items():
        for position, word in enumerate(words):
            yield term, word, 100_000_000 - position


SCHEMA = """
CREATE TABLE zh_lookup (
    term TEXT NOT NULL,
    word TEXT NOT NULL COLLATE NOCASE,
    rank INTEGER NOT NULL,
    PRIMARY KEY (term, word)
) WITHOUT ROWID;
CREATE INDEX zh_lookup_term_rank_idx ON zh_lookup(term, rank DESC);
"""


INSERT_SQL = """
INSERT INTO zh_lookup (term, word, rank)
VALUES (?, ?, ?)
ON CONFLICT(term, word) DO UPDATE SET rank = max(rank, excluded.rank)
"""
