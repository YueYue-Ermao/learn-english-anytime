#!/usr/bin/env python3
"""Convert the ECDICT CSV into a compact, read-only SQLite database."""

from __future__ import annotations

import argparse
import csv
import os
import sqlite3
from pathlib import Path

from chinese_reverse_index import INSERT_SQL, SCHEMA, curated_rows, reverse_rows


def normalized_word(value: str) -> str:
    return "".join(character for character in value.lower() if character.isalnum())


def exchange_forms(value: str) -> list[str]:
    forms: list[str] = []
    for part in value.split("/"):
        if ":" not in part:
            continue
        exchange_type, raw_forms = part.split(":", 1)
        if exchange_type not in {"p", "d", "i", "3", "r", "t", "s"}:
            continue
        forms.extend(item.strip() for item in raw_forms.split(",") if item.strip())
    return forms


def integer_or_zero(value: str) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def build_database(source: Path, destination: Path) -> tuple[int, int, int]:
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(destination.suffix + ".building")
    if temporary.exists():
        temporary.unlink()

    connection = sqlite3.connect(temporary)
    connection.executescript(
        """
        PRAGMA journal_mode = OFF;
        PRAGMA synchronous = OFF;
        PRAGMA temp_store = MEMORY;
        CREATE TABLE entries (
            word TEXT PRIMARY KEY COLLATE NOCASE,
            normalized TEXT NOT NULL,
            phonetic TEXT,
            definition TEXT,
            translation TEXT,
            pos TEXT,
            collins INTEGER NOT NULL DEFAULT 0,
            oxford INTEGER NOT NULL DEFAULT 0,
            tags TEXT,
            bnc INTEGER NOT NULL DEFAULT 0,
            frequency INTEGER NOT NULL DEFAULT 0,
            exchange TEXT
        ) WITHOUT ROWID;
        CREATE TABLE forms (
            form TEXT PRIMARY KEY COLLATE NOCASE,
            lemma TEXT NOT NULL
        ) WITHOUT ROWID;
        """
        + SCHEMA
    )

    entry_count = 0
    form_count = 0
    pending_entries: list[tuple[object, ...]] = []
    pending_forms: list[tuple[str, str]] = []
    pending_reverse: list[tuple[str, str, int]] = []

    with source.open("r", encoding="utf-8-sig", newline="") as source_file:
        reader = csv.DictReader(source_file)
        for row in reader:
            word = (row.get("word") or "").strip()
            if not word:
                continue

            translation = (row.get("translation") or "").strip()
            collins = integer_or_zero(row.get("collins") or "0")
            oxford = integer_or_zero(row.get("oxford") or "0")
            bnc = integer_or_zero(row.get("bnc") or "0")
            frequency = integer_or_zero(row.get("frq") or "0")

            pending_entries.append(
                (
                    word,
                    normalized_word(word),
                    (row.get("phonetic") or "").strip(),
                    (row.get("definition") or "").strip(),
                    translation,
                    (row.get("pos") or "").strip(),
                    collins,
                    oxford,
                    (row.get("tag") or "").strip(),
                    bnc,
                    frequency,
                    (row.get("exchange") or "").strip(),
                )
            )
            entry_count += 1

            for form in exchange_forms(row.get("exchange") or ""):
                if form.casefold() == word.casefold():
                    continue
                pending_forms.append((form, word))

            pending_reverse.extend(
                reverse_rows(word, translation, collins, oxford, bnc, frequency)
            )

            if len(pending_entries) >= 10_000:
                connection.executemany(
                    """
                    INSERT OR REPLACE INTO entries
                    (word, normalized, phonetic, definition, translation, pos,
                     collins, oxford, tags, bnc, frequency, exchange)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    pending_entries,
                )
                connection.executemany(
                    "INSERT OR IGNORE INTO forms (form, lemma) VALUES (?, ?)",
                    pending_forms,
                )
                connection.executemany(INSERT_SQL, pending_reverse)
                form_count += len(pending_forms)
                pending_entries.clear()
                pending_forms.clear()
                pending_reverse.clear()

    if pending_entries:
        connection.executemany(
            """
            INSERT OR REPLACE INTO entries
            (word, normalized, phonetic, definition, translation, pos,
             collins, oxford, tags, bnc, frequency, exchange)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            pending_entries,
        )
        connection.executemany(
            "INSERT OR IGNORE INTO forms (form, lemma) VALUES (?, ?)",
            pending_forms,
        )
        connection.executemany(INSERT_SQL, pending_reverse)
        form_count += len(pending_forms)

    connection.executemany(INSERT_SQL, curated_rows())

    connection.executescript(
        """
        CREATE INDEX entries_normalized_idx ON entries(normalized);
        CREATE INDEX forms_lemma_idx ON forms(lemma);
        ANALYZE;
        VACUUM;
        """
    )
    entry_count = connection.execute("SELECT count(*) FROM entries").fetchone()[0]
    form_count = connection.execute("SELECT count(*) FROM forms").fetchone()[0]
    reverse_count = connection.execute("SELECT count(*) FROM zh_lookup").fetchone()[0]
    connection.close()
    os.replace(temporary, destination)
    return entry_count, form_count, reverse_count


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    arguments = parser.parse_args()
    entries, forms, reverse_mappings = build_database(arguments.source, arguments.destination)
    size = arguments.destination.stat().st_size
    print(
        f"Built {arguments.destination}: {entries} entries, {forms} forms, "
        f"{reverse_mappings} Chinese reverse mappings, {size} bytes"
    )


if __name__ == "__main__":
    main()
