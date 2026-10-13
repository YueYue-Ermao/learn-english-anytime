#!/usr/bin/env python3
"""Build an offline synonym table from the Princeton WordNet database files."""

from __future__ import annotations

import argparse
import re
import sqlite3
from pathlib import Path


DATA_FILES = ("noun", "verb", "adj", "adv")
ADJECTIVE_MARKER = re.compile(r"\((?:a|p|ip)\)$")


def display_word(raw_word: str) -> str:
    """Convert WordNet's storage form into readable text."""
    return ADJECTIVE_MARKER.sub("", raw_word).replace("_", " ").strip()


def load_synsets(
    dictionary_directory: Path,
) -> tuple[
    dict[tuple[str, str], list[str]],
    dict[tuple[str, str], list[tuple[tuple[str, str], int]]],
]:
    synsets: dict[tuple[str, str], list[str]] = {}
    related_synsets: dict[tuple[str, str], list[tuple[tuple[str, str], int]]] = {}
    for suffix in DATA_FILES:
        path = dictionary_directory / f"data.{suffix}"
        with path.open("r", encoding="utf-8") as source:
            for line in source:
                if line.startswith("  ") or " | " not in line:
                    continue
                fields = line.partition(" | ")[0].split()
                if len(fields) < 5:
                    continue
                offset = fields[0]
                part_of_speech = "a" if fields[2] == "s" else fields[2]
                word_count = int(fields[3], 16)
                words = [
                    display_word(fields[4 + (index * 2)])
                    for index in range(word_count)
                ]
                synsets[(part_of_speech, offset)] = list(dict.fromkeys(words))
                pointer_count_index = 4 + (word_count * 2)
                pointer_count = int(fields[pointer_count_index])
                targets: list[tuple[tuple[str, str], int]] = []
                for index in range(pointer_count):
                    pointer_index = pointer_count_index + 1 + (index * 4)
                    symbol, target_offset, target_part = fields[pointer_index : pointer_index + 3]
                    if symbol in {"^", "&"}:
                        target = ("a" if target_part == "s" else target_part, target_offset)
                        targets.append((target, 1 if symbol == "^" else 2))
                if targets:
                    related_synsets[(part_of_speech, offset)] = targets
    return synsets, related_synsets


def load_tag_counts(dictionary_directory: Path) -> dict[tuple[str, str, str], int]:
    """Load corpus counts used by WordNet to put the common senses first."""
    part_of_speech_codes = {"1": "n", "2": "v", "3": "a", "4": "r", "5": "a"}
    result: dict[tuple[str, str, str], int] = {}
    with (dictionary_directory / "index.sense").open("r", encoding="utf-8") as source:
        for line in source:
            fields = line.split()
            if len(fields) != 4 or "%" not in fields[0]:
                continue
            sense_key, offset, _, tag_count = fields
            raw_lemma, sense_metadata = sense_key.split("%", 1)
            part_of_speech = part_of_speech_codes.get(sense_metadata[0])
            if part_of_speech is None:
                continue
            result[(display_word(raw_lemma), part_of_speech, offset)] = int(tag_count)
    return result


def iter_ranked_synonyms(
    dictionary_directory: Path,
    synsets: dict[tuple[str, str], list[str]],
    related_synsets: dict[tuple[str, str], list[tuple[tuple[str, str], int]]],
    tag_counts: dict[tuple[str, str, str], int],
):
    """Yield co-synset words and adjective "similar to" relations by common sense."""
    for part_priority, suffix in enumerate(DATA_FILES):
        path = dictionary_directory / f"index.{suffix}"
        with path.open("r", encoding="utf-8") as source:
            for line in source:
                if line.startswith("  "):
                    continue
                fields = line.split()
                if len(fields) < 7:
                    continue
                lemma = display_word(fields[0])
                part_of_speech = fields[1]
                synset_count = int(fields[2])
                pointer_count = int(fields[3])
                offset_start = 6 + pointer_count
                offsets = fields[offset_start : offset_start + synset_count]
                ranked: dict[str, tuple[int, int, int, int, int]] = {}
                for sense_index, offset in enumerate(offsets):
                    tag_count = tag_counts.get((lemma, part_of_speech, offset), 0)
                    related_sets = [((part_of_speech, offset), 0)]
                    if part_of_speech == "a":
                        related_sets.extend(related_synsets.get((part_of_speech, offset), []))
                    for target_index, (target, relation_rank) in enumerate(related_sets):
                        words = synsets.get(target, [])
                        for word_index, synonym in enumerate(words):
                            if synonym.casefold() == lemma.casefold():
                                continue
                            score = (
                                -tag_count,
                                sense_index,
                                relation_rank,
                                part_priority,
                                (target_index * 100) + word_index,
                            )
                            previous = ranked.get(synonym.casefold())
                            if previous is None or score < previous:
                                ranked[synonym.casefold()] = score
                ordered = sorted(
                    ((score, synonym_key) for synonym_key, score in ranked.items()),
                    key=lambda item: (item[0], len(item[1]), item[1]),
                )
                yield lemma, [(synonym, score) for score, synonym in ordered]


def install_synonyms(
    database_path: Path,
    dictionary_directory: Path,
    maximum_per_word: int = 12,
) -> tuple[int, int]:
    required_files = [
        dictionary_directory / f"{kind}.{suffix}"
        for kind in ("data", "index")
        for suffix in DATA_FILES
    ]
    required_files.append(dictionary_directory / "index.sense")
    missing = [str(path) for path in required_files if not path.exists()]
    if missing:
        raise FileNotFoundError("Missing WordNet files: " + ", ".join(missing))

    connection = sqlite3.connect(database_path)
    try:
        word_metadata = {
            row[0].casefold(): (row[1], row[2], row[3], row[4])
            for row in connection.execute(
                "SELECT word, collins, oxford, bnc, frequency FROM entries"
            )
        }
        synsets, related_synsets = load_synsets(dictionary_directory)
        tag_counts = load_tag_counts(dictionary_directory)
        rows: list[tuple[str, str, int, int, int, int, int, int]] = []

        connection.executescript(
            """
            DROP TABLE IF EXISTS synonyms;
            DROP TABLE IF EXISTS synonym_candidates;
            CREATE TABLE synonym_candidates (
                word TEXT NOT NULL COLLATE NOCASE,
                synonym TEXT NOT NULL COLLATE NOCASE,
                source_score INTEGER NOT NULL,
                collins INTEGER NOT NULL,
                oxford INTEGER NOT NULL,
                bnc INTEGER NOT NULL,
                frequency INTEGER NOT NULL,
                word_rank INTEGER NOT NULL,
                PRIMARY KEY (word, synonym)
            ) WITHOUT ROWID;
            CREATE TABLE synonyms (
                word TEXT NOT NULL COLLATE NOCASE,
                synonym TEXT NOT NULL COLLATE NOCASE,
                rank INTEGER NOT NULL,
                PRIMARY KEY (word, synonym)
            ) WITHOUT ROWID;
            """
        )

        for word, candidates in iter_ranked_synonyms(
            dictionary_directory,
            synsets,
            related_synsets,
            tag_counts,
        ):
            if word.casefold() not in word_metadata:
                continue
            filtered = [
                (candidate, score)
                for candidate, score in candidates
                if candidate.casefold() in word_metadata
            ]
            if not filtered:
                continue
            rows.extend(
                (
                    word,
                    synonym,
                    (-score[0] * 1_000_000)
                    - (score[1] * 10_000)
                    - (score[2] * 1_000)
                    - (score[3] * 100),
                    *word_metadata[synonym.casefold()],
                    score[4],
                )
                for synonym, score in filtered
            )
            if len(rows) >= 10_000:
                connection.executemany(
                    """
                    INSERT INTO synonym_candidates
                    (word, synonym, source_score, collins, oxford, bnc, frequency, word_rank)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(word, synonym) DO UPDATE SET
                        source_score = excluded.source_score,
                        word_rank = excluded.word_rank
                    WHERE excluded.source_score > synonym_candidates.source_score
                    """,
                    rows,
                )
                rows.clear()

        if rows:
            connection.executemany(
                """
                INSERT INTO synonym_candidates
                (word, synonym, source_score, collins, oxford, bnc, frequency, word_rank)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(word, synonym) DO UPDATE SET
                    source_score = excluded.source_score,
                    word_rank = excluded.word_rank
                WHERE excluded.source_score > synonym_candidates.source_score
                """,
                rows,
            )
        connection.execute(
            """
            INSERT INTO synonyms (word, synonym, rank)
            SELECT word, synonym, position
            FROM (
                SELECT word, synonym,
                       row_number() OVER (
                           PARTITION BY word
                           ORDER BY source_score DESC, collins DESC, oxford DESC,
                                    CASE WHEN bnc = 0 THEN 1 ELSE 0 END, bnc,
                                    CASE WHEN frequency = 0 THEN 1 ELSE 0 END, frequency,
                                    word_rank, length(synonym), synonym
                       ) AS position
                FROM synonym_candidates
            )
            WHERE position <= ?
            """,
            (maximum_per_word,),
        )
        connection.execute("DROP TABLE synonym_candidates")
        connection.execute("CREATE INDEX synonyms_word_rank_idx ON synonyms(word, rank)")
        connection.execute("ANALYZE synonyms")
        connection.commit()
        words_with_synonyms = connection.execute(
            "SELECT count(DISTINCT word) FROM synonyms"
        ).fetchone()[0]
        synonym_count = connection.execute("SELECT count(*) FROM synonyms").fetchone()[0]
        return words_with_synonyms, synonym_count
    finally:
        connection.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("database", type=Path)
    parser.add_argument("wordnet_dictionary_directory", type=Path)
    parser.add_argument("--maximum-per-word", type=int, default=12)
    arguments = parser.parse_args()
    words, synonyms = install_synonyms(
        arguments.database,
        arguments.wordnet_dictionary_directory,
        arguments.maximum_per_word,
    )
    print(f"Installed {synonyms} synonym links for {words} words into {arguments.database}")


if __name__ == "__main__":
    main()
