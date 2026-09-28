#!/usr/bin/env python3
"""Best-effort Codex transcript capture for Nowledge Mem Stop hooks."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any


CAPTURE_DEADLINE_SECONDS = 105.0
MIN_CAPTURE_ATTEMPT_SECONDS = 1.0
SKILL_OUTCOME_TIMEOUT_SECONDS = 8.0
CAPTURE_ENQUEUE_TIMEOUT_SECONDS = 5.0
CODEX_HOOK_SUCCESS_RESPONSE = {"continue": True}
DELEGATED_CONVERSATION_ORIGINATORS = frozenset({"raft-daemon", "slock-daemon"})
MAX_SESSION_META_BYTES = 256 * 1024

_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

try:
    from skill_outcome import build_outcome_args, extract_skill_outcomes_from_file
except Exception:  # pragma: no cover - defensive for partial installs
    build_outcome_args = None
    extract_skill_outcomes_from_file = None

from nmem_runtime import build_nmem_command as _build_nmem_command
from nmem_runtime import cmd_exe_path as _cmd_exe_path
from nmem_runtime import find_nmem_command as _find_nmem_command
from nmem_runtime import windows_no_window_kwargs as _windows_no_window_kwargs


def _write_hook_response() -> None:
    json.dump(CODEX_HOOK_SUCCESS_RESPONSE, sys.stdout)
    sys.stdout.write("\n")


def _run_entrypoint() -> object:
    exit_code: object = 0
    try:
        exit_code = main()
    except SystemExit as exc:
        exit_code = exc.code
    finally:
        _write_hook_response()
    return exit_code


def _read_hook_input() -> dict[str, Any]:
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return {}
    return payload if isinstance(payload, dict) else {}


def _payload_value(payload: dict[str, Any], *keys: str) -> str | None:
    containers: list[dict[str, Any]] = [payload]
    for outer_key in ("input", "data", "payload"):
        nested = payload.get(outer_key)
        if isinstance(nested, dict):
            containers.append(nested)
            nested_input = nested.get("input")
            if isinstance(nested_input, dict):
                containers.append(nested_input)

    for container in containers:
        for key in keys:
            value = container.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()
    return None


def _transcript_originator(transcript_path: str | None) -> str | None:
    """Read Codex's authoritative session originator without parsing the rollout."""
    if not transcript_path:
        return None

    try:
        with Path(transcript_path).expanduser().open("r", encoding="utf-8") as handle:
            for _ in range(8):
                line = handle.readline(MAX_SESSION_META_BYTES + 1)
                if not line:
                    return None
                if len(line) > MAX_SESSION_META_BYTES:
                    return None
                if not line.strip():
                    continue
                record = json.loads(line)
                if not isinstance(record, dict) or record.get("type") != "session_meta":
                    return None
                session = record.get("payload")
                if not isinstance(session, dict):
                    return None
                originator = session.get("originator")
                if isinstance(originator, str) and originator.strip():
                    return originator.strip().lower()
                return None
    except (OSError, UnicodeError, json.JSONDecodeError):
        return None
    return None


def _delegated_conversation_originator(payload: dict[str, Any]) -> str | None:
    originator = _transcript_originator(
        _payload_value(payload, "transcript_path", "transcriptPath")
    )
    if originator in DELEGATED_CONVERSATION_ORIGINATORS:
        return originator
    return None


def _log_path() -> Path:
    plugin_data = os.environ.get("PLUGIN_DATA") or os.environ.get("CLAUDE_PLUGIN_DATA")
    if plugin_data:
        return Path(plugin_data).expanduser() / "nowledge-mem-stop-hook.log"

    codex_home = os.environ.get("CODEX_HOME")
    if codex_home:
        return Path(codex_home).expanduser() / "log" / "nowledge-mem-stop-hook.log"

    return Path.home() / ".codex" / "log" / "nowledge-mem-stop-hook.log"


def _log(message: str) -> None:
    try:
        path = _log_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        with path.open("a", encoding="utf-8") as handle:
            handle.write(f"[{timestamp}] {message}\n")
    except Exception:
        pass


def _deadline_after(seconds: float) -> float:
    return time.monotonic() + max(0.0, seconds)


def _remaining_seconds(deadline: float | None) -> float | None:
    if deadline is None:
        return None
    return max(0.0, deadline - time.monotonic())


def _capture_lock_root(payload: dict[str, Any]) -> Path:
    codex_home = os.environ.get("CODEX_HOME")
    if codex_home:
        return Path(codex_home).expanduser() / "log" / "nowledge-mem-stop-hook-locks"

    derived = _derive_codex_home(_payload_value(payload, "transcript_path", "transcriptPath"))
    if derived:
        return derived / "log" / "nowledge-mem-stop-hook-locks"

    return Path.home() / ".codex" / "log" / "nowledge-mem-stop-hook-locks"


def _nmem_command() -> str | None:
    return _find_nmem_command()


def _derive_codex_home(transcript_path: str | None) -> Path | None:
    if not transcript_path:
        return None
    path = Path(transcript_path).expanduser()
    for parent in (path.parent, *path.parents):
        if parent.name == "sessions":
            return parent.parent
    return None


def _build_env(payload: dict[str, Any]) -> dict[str, str]:
    env = os.environ.copy()
    if not env.get("CODEX_HOME"):
        derived = _derive_codex_home(_payload_value(payload, "transcript_path", "transcriptPath"))
        if derived:
            env["CODEX_HOME"] = str(derived)
    return env


def _build_enqueue_command(nmem: str, payload: dict[str, Any]) -> list[str]:
    args = ["--json", "t", "capture", "--from", "codex"]
    session_id = _payload_value(payload, "session_id", "sessionId")
    if session_id:
        args.extend(["--session-id", session_id])
    cwd = _payload_value(payload, "cwd")
    if cwd:
        project = str(Path(cwd).expanduser())
        if nmem.lower().endswith(".cmd"):
            project = _cmd_exe_path(project)
        args.extend(["--project", project])
    transcript_path = _payload_value(payload, "transcript_path", "transcriptPath")
    if transcript_path:
        transcript = str(Path(transcript_path).expanduser())
        if nmem.lower().endswith(".cmd"):
            transcript = _cmd_exe_path(transcript)
        args.extend(["--transcript-path", transcript])
    return _build_nmem_command(nmem, *args)


def _run_enqueue(
    nmem: str,
    payload: dict[str, Any],
) -> subprocess.CompletedProcess[str]:
    command = _build_enqueue_command(nmem, payload)
    _log(f"enqueue: {subprocess.list2cmdline(command)}")
    return subprocess.run(
        command,
        env=_build_env(payload),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=CAPTURE_ENQUEUE_TIMEOUT_SECONDS,
        check=False,
        **_windows_no_window_kwargs(),
    )


def _enqueue_succeeded(proc: subprocess.CompletedProcess[str]) -> bool:
    if proc.returncode != 0:
        return False
    try:
        payload = json.loads(proc.stdout or "{}")
    except json.JSONDecodeError:
        return False
    return isinstance(payload, dict) and payload.get("status") == "enqueued"


def _background_spawn_kwargs() -> dict[str, Any]:
    kwargs: dict[str, Any] = {
        "stdin": subprocess.DEVNULL,
        "stdout": subprocess.DEVNULL,
        "stderr": subprocess.DEVNULL,
        "close_fds": True,
    }
    if sys.platform == "win32":
        kwargs["creationflags"] = (
            getattr(subprocess, "CREATE_NO_WINDOW", 0x08000000)
            | getattr(subprocess, "DETACHED_PROCESS", 0x00000008)
            | getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0x00000200)
        )
    else:
        kwargs["start_new_session"] = True
    return kwargs


def _dispatch_skill_outcomes(payload: dict[str, Any]) -> None:
    safe_payload = {
        "session_id": _payload_value(payload, "session_id", "sessionId"),
        "cwd": _payload_value(payload, "cwd"),
        "transcript_path": _payload_value(
            payload,
            "transcript_path",
            "transcriptPath",
        ),
    }
    safe_payload = {key: value for key, value in safe_payload.items() if value}
    if not safe_payload:
        return
    encoded = base64.urlsafe_b64encode(
        json.dumps(safe_payload, separators=(",", ":")).encode("utf-8")
    ).decode("ascii")
    command = [
        sys.executable,
        str(Path(__file__).resolve()),
        "--skill-outcome-payload",
        encoded,
    ]
    try:
        subprocess.Popen(command, **_background_spawn_kwargs())
    except Exception as exc:
        _log(f"skill-outcome: background dispatch failed: {exc}")


def _skill_outcome_lock_root(payload: dict[str, Any]) -> Path:
    return _capture_lock_root(payload) / "skill-outcomes"


def _skill_outcome_lock_path(
    payload: dict[str, Any],
    skill_id: str,
    version: str,
) -> Path:
    basis = {
        "host": "codex",
        "session_id": _payload_value(payload, "session_id", "sessionId") or "",
        "transcript_path": _payload_value(
            payload,
            "transcript_path",
            "transcriptPath",
        ) or "",
        "skill_id": skill_id,
        "version": version,
    }
    encoded = json.dumps(basis, sort_keys=True, separators=(",", ":"))
    key = hashlib.sha256(encoded.encode("utf-8")).hexdigest()
    return _skill_outcome_lock_root(payload) / f"{key}.reported"


def _claim_skill_outcome_report(
    payload: dict[str, Any],
    skill_id: str,
    version: str,
) -> tuple[Path, Path | None] | None:
    marker_path = _skill_outcome_lock_path(payload, skill_id, version)
    lock_path = marker_path.with_suffix(".lock")
    if marker_path.exists():
        return None

    try:
        lock_path.parent.mkdir(parents=True, exist_ok=True)
        try:
            fd = os.open(lock_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError:
            try:
                age = time.time() - lock_path.stat().st_mtime
                if age <= CAPTURE_DEADLINE_SECONDS:
                    return None
                # ponytail: expire one capture budget after a crash; add a CLI idempotency key to remove the retry window.
                lock_path.unlink()
                fd = os.open(lock_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            except (FileExistsError, OSError):
                return None
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(str(time.time()))
            handle.write("\n")
        if marker_path.exists():
            _release_skill_outcome_claim(lock_path)
            return None
        return marker_path, lock_path
    except OSError as exc:
        _log(f"skill-outcome: lock unavailable ({exc}); reporting without guard")
        return marker_path, None


def _release_skill_outcome_claim(lock_path: Path | None) -> None:
    if lock_path is None:
        return
    try:
        lock_path.unlink()
    except OSError:
        pass


def _mark_skill_outcome_reported(marker_path: Path, lock_path: Path | None) -> None:
    try:
        fd = os.open(marker_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(str(time.time()))
            handle.write("\n")
    except FileExistsError:
        pass
    except OSError as exc:
        _log(f"skill-outcome: reported but dedupe marker failed ({exc}); lease retained")
        return
    _release_skill_outcome_claim(lock_path)


def _report_skill_outcomes(
    nmem: str,
    payload: dict[str, Any],
    *,
    deadline: float | None = None,
) -> None:
    if extract_skill_outcomes_from_file is None or build_outcome_args is None:
        _log("skill-outcome: extractor unavailable")
        return
    transcript_path = _payload_value(payload, "transcript_path", "transcriptPath")
    outcomes = extract_skill_outcomes_from_file(transcript_path)
    if not outcomes:
        return

    env = _build_env(payload)
    for skill_id, version in outcomes:
        remaining = _remaining_seconds(deadline)
        if remaining is not None and remaining < MIN_CAPTURE_ATTEMPT_SECONDS:
            _log("skill-outcome: skipped because Stop hook budget is exhausted")
            return
        timeout_seconds = (
            SKILL_OUTCOME_TIMEOUT_SECONDS
            if remaining is None
            else min(SKILL_OUTCOME_TIMEOUT_SECONDS, remaining)
        )
        claim = _claim_skill_outcome_report(payload, skill_id, version)
        if claim is None:
            continue
        marker_path, lock_path = claim
        try:
            command = _build_nmem_command(nmem, *build_outcome_args(skill_id, version))
            proc = subprocess.run(
                command,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=timeout_seconds,
                check=False,
                **_windows_no_window_kwargs(),
            )
        except subprocess.TimeoutExpired:
            _release_skill_outcome_claim(lock_path)
            _log(f"skill-outcome: timed out reporting {skill_id}@{version}")
            continue
        except Exception as exc:
            _release_skill_outcome_claim(lock_path)
            _log(f"skill-outcome: failed reporting {skill_id}@{version}: {exc}")
            continue

        if proc.returncode == 0:
            _mark_skill_outcome_reported(marker_path, lock_path)
            _log(f"skill-outcome: reported {skill_id}@{version}")
        else:
            _release_skill_outcome_claim(lock_path)
            detail = (proc.stderr or proc.stdout or "").strip()
            _log(
                f"skill-outcome: nmem exited {proc.returncode} for "
                f"{skill_id}@{version}: {detail[:300]}"
            )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--event", default="stop", help="Diagnostic event label.")
    parser.add_argument("--skill-outcome-payload", help=argparse.SUPPRESS)
    args, _ = parser.parse_known_args()

    if args.skill_outcome_payload:
        try:
            payload = json.loads(
                base64.urlsafe_b64decode(args.skill_outcome_payload.encode("ascii"))
            )
        except (ValueError, UnicodeError, json.JSONDecodeError):
            return 0
        nmem = _nmem_command()
        if nmem and isinstance(payload, dict):
            _report_skill_outcomes(
                nmem,
                payload,
                deadline=_deadline_after(CAPTURE_DEADLINE_SECONDS),
            )
        return 0

    payload = _read_hook_input()
    session_id = _payload_value(payload, "session_id", "sessionId")
    cwd = _payload_value(payload, "cwd")
    transcript_path = _payload_value(payload, "transcript_path", "transcriptPath")
    _log(
        f"start event={args.event} session={session_id or 'missing'} "
        f"cwd={cwd or 'missing'} transcript={transcript_path or 'missing'}"
    )

    nmem = _nmem_command()
    if not nmem:
        _log("skip: nmem not found")
        return 0

    delegated_originator = _delegated_conversation_originator(payload)
    if delegated_originator:
        # Raft owns the real channel/thread boundary. Its long-lived Codex
        # rollout is an execution trace containing inbox control notices and
        # empty final answers, not a user conversation. Keep skill telemetry,
        # but never persist that rollout as a Codex Thread.
        _dispatch_skill_outcomes(payload)
        _log(
            "skip: delegated conversation host owns thread capture "
            f"originator={delegated_originator}"
        )
        return 0

    if not session_id:
        _log("skip: durable capture requires session identity")
        return 0
    try:
        enqueue_proc = _run_enqueue(nmem, payload)
    except (subprocess.TimeoutExpired, OSError, ValueError) as exc:
        _log(f"enqueue: unavailable; capture skipped: {exc}")
        return 0
    if _enqueue_succeeded(enqueue_proc):
        _dispatch_skill_outcomes(payload)
        _log("enqueue: durable capture accepted")
        return 0
    detail = (enqueue_proc.stderr or enqueue_proc.stdout or "").strip()
    _log(
        f"enqueue: nmem exited {enqueue_proc.returncode}; "
        f"capture skipped: {detail[:300]}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(_run_entrypoint())
