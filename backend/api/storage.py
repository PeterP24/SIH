"""SQLite persistence for signatures, verifications and threat-detection logs."""

from __future__ import annotations

import json
import sqlite3
import threading
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

DEFAULT_DB_PATH = Path(__file__).resolve().parent.parent / "data" / "qds.db"

_SCHEMA = """
CREATE TABLE IF NOT EXISTS signatures (
    signature_id TEXT PRIMARY KEY,
    message      TEXT NOT NULL,
    message_hash TEXT NOT NULL,
    signer       TEXT NOT NULL,
    key_id       TEXT NOT NULL,
    key_bits     TEXT NOT NULL,
    payload      TEXT NOT NULL,
    created_at   REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS events (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type   TEXT NOT NULL,          -- sign | verify | attack
    signature_id TEXT,
    subject      TEXT,                   -- attack type or verifier name
    verdict      TEXT,                   -- ACCEPT | REJECT | SIGNED
    detected     INTEGER,                -- 1 threat detected, 0 clean, NULL n/a
    expected_detection INTEGER,
    mismatch_rate REAL,
    qber          REAL,
    threshold     REAL,
    forgery_probability REAL,
    elapsed_ms    REAL,
    payload       TEXT NOT NULL,
    created_at    REAL NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_events_created ON events(created_at DESC);
"""


class Storage:
    """Small thread-safe wrapper over a SQLite database."""

    def __init__(self, db_path: Optional[Path] = None) -> None:
        self.db_path = Path(db_path or DEFAULT_DB_PATH)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()
        self._conn = sqlite3.connect(self.db_path, check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        with self._lock:
            self._conn.executescript(_SCHEMA)
            self._conn.commit()

    # ------------------------------------------------------------ signatures
    def save_signature(self, signature: Dict[str, Any], key_bits: List[int]) -> None:
        with self._lock:
            self._conn.execute(
                "INSERT OR REPLACE INTO signatures VALUES (?,?,?,?,?,?,?,?)",
                (
                    signature["signature_id"],
                    signature["message"],
                    signature["message_hash"],
                    signature["signer"],
                    signature["key_id"],
                    json.dumps(key_bits),
                    json.dumps(signature),
                    signature["created_at"],
                ),
            )
            self._conn.commit()

    def get_signature(self, signature_id: str) -> Optional[Dict[str, Any]]:
        with self._lock:
            row = self._conn.execute(
                "SELECT payload, key_bits FROM signatures WHERE signature_id = ?",
                (signature_id,),
            ).fetchone()
        if row is None:
            return None
        payload = json.loads(row["payload"])
        payload["_key_bits"] = json.loads(row["key_bits"])
        return payload

    def list_signatures(self, limit: int = 50) -> List[Dict[str, Any]]:
        with self._lock:
            rows = self._conn.execute(
                "SELECT payload FROM signatures ORDER BY created_at DESC LIMIT ?",
                (limit,),
            ).fetchall()
        return [json.loads(r["payload"]) for r in rows]

    def latest_signature_id(self) -> Optional[str]:
        with self._lock:
            row = self._conn.execute(
                "SELECT signature_id FROM signatures ORDER BY created_at DESC LIMIT 1"
            ).fetchone()
        return row["signature_id"] if row else None

    # ---------------------------------------------------------------- events
    def log_event(
        self,
        event_type: str,
        payload: Dict[str, Any],
        *,
        signature_id: Optional[str] = None,
        subject: Optional[str] = None,
        verdict: Optional[str] = None,
        detected: Optional[bool] = None,
        expected_detection: Optional[bool] = None,
        mismatch_rate: Optional[float] = None,
        qber: Optional[float] = None,
        threshold: Optional[float] = None,
        forgery_probability: Optional[float] = None,
        elapsed_ms: Optional[float] = None,
    ) -> int:
        with self._lock:
            cur = self._conn.execute(
                """INSERT INTO events (event_type, signature_id, subject, verdict, detected,
                       expected_detection, mismatch_rate, qber, threshold,
                       forgery_probability, elapsed_ms, payload, created_at)
                   VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                (
                    event_type,
                    signature_id,
                    subject,
                    verdict,
                    None if detected is None else int(detected),
                    None if expected_detection is None else int(expected_detection),
                    mismatch_rate,
                    qber,
                    threshold,
                    forgery_probability,
                    elapsed_ms,
                    json.dumps(payload),
                    time.time(),
                ),
            )
            self._conn.commit()
            return int(cur.lastrowid)

    def list_events(
        self, limit: int = 100, event_type: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        query = "SELECT * FROM events"
        params: List[Any] = []
        if event_type:
            query += " WHERE event_type = ?"
            params.append(event_type)
        query += " ORDER BY id DESC LIMIT ?"
        params.append(limit)
        with self._lock:
            rows = self._conn.execute(query, params).fetchall()
        events = []
        for row in rows:
            item = dict(row)
            item["payload"] = json.loads(item["payload"])
            if item.get("detected") is not None:
                item["detected"] = bool(item["detected"])
            if item.get("expected_detection") is not None:
                item["expected_detection"] = bool(item["expected_detection"])
            events.append(item)
        return events

    def verified_messages_for(self, signature_id: str) -> List[str]:
        """Messages this signature has already been presented against.

        Used for the replay registry: a second, *different* message for the same
        signature id is a replay attempt regardless of the quantum statistics.
        """
        with self._lock:
            rows = self._conn.execute(
                """SELECT payload FROM events
                   WHERE signature_id = ? AND event_type IN ('verify','attack')""",
                (signature_id,),
            ).fetchall()
        messages = []
        for row in rows:
            payload = json.loads(row["payload"])
            message = payload.get("message") or payload.get("presented_message")
            if isinstance(message, str):
                messages.append(message)
        return messages

    # --------------------------------------------------------------- metrics
    def metric_rows(self) -> List[Dict[str, Any]]:
        with self._lock:
            rows = self._conn.execute(
                """SELECT event_type, subject, verdict, detected, expected_detection,
                          mismatch_rate, qber, forgery_probability, elapsed_ms, created_at
                   FROM events ORDER BY id ASC"""
            ).fetchall()
        return [dict(r) for r in rows]

    def close(self) -> None:
        with self._lock:
            self._conn.close()
