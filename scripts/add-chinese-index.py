#!/usr/bin/env python3
"""Add or refresh the compact Chinese reverse index in an ECDICT database."""

from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path

from chinese_reverse_index import INSERT_SQL, SCHEMA, curated_rows, reverse_rows


def rebuild(database_path: Path) -> tuple[int, int]:
    connection = sqlite3.connect(database_path)
    connection.execute("PRAGMA journal_mode = DELETE")
    connection.execute("DROP INDEX IF EXISTS zh_lookup_term_rank_idx")
    connection.execute("DROP TABLE IF EXISTS zh_lookup")
    connection.executescript(SCHEMA)

    pending: list[tuple[str, str, int]] = []
    source_count = 0
    cursor = connection.execute(
        """
        SELECT word, translation, collins, oxford, bnc, frequency
        FROM entries
        WHERE translation <> ''
          AND instr(word, ' ') = 0
          AND (collins > 0 OR oxford > 0 OR bnc > 0 OR frequency > 0)
        """
    )
    for word, translation, collins, oxford, bnc, frequency in cursor:
        source_count += 1
        pending.extend(
            reverse_rows(
                word,
                translation,
                collins,
                oxford,
                bnc,
                frequency,
            )
        )
        if len(pending) >= 10_000:
            connection.executemany(INSERT_SQL, pending)
            pending.clear()

    if pending:
        connection.executemany(INSERT_SQL, pending)
    connection.executemany(INSERT_SQL, curated_rows())

    connection.commit()
    row_count = connection.execute("SELECT count(*) FROM zh_lookup").fetchone()[0]
    connection.execute("ANALYZE zh_lookup")
    connection.commit()
    connection.close()
    return source_count, row_count


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("database", type=Path)
    arguments = parser.parse_args()
    source_count, row_count = rebuild(arguments.database)
    print(
        f"Built Chinese reverse index in {arguments.database}: "
        f"{row_count} mappings from {source_count} English entries"
    )


if __name__ == "__main__":
    main()
