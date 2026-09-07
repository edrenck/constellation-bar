import Foundation

/// Fixed read-only helper sent over SSH. No remote files are installed or changed.
/// Kept inline so both SwiftPM and the distributable app use the identical probe.
enum RemoteAgentProbe {
    static let source = #"""
import os, sys, json, sqlite3, pathlib, fcntl, uuid, stat

def text(value, limit=240):
    return ' '.join(str(value or '').split())[:limit]

def activity(value):
    if value == 'inProgress': return 'active'
    if value in ('completed', 'failed', 'interrupted'): return 'idle'
    return 'unknown'

def database(path):
    return sqlite3.connect(path.as_uri() + '?mode=ro', uri=True, timeout=0.1)

def legacy(path):
    # Inspect only a bounded tail, accepting complete lifecycle lines only.
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    with os.fdopen(fd, 'rb') as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode): return 'unknown'
        offset = max(0, info.st_size - 8 * 1048576)
        stream.seek(offset)
        data = stream.read(8 * 1048576)
    lines = data.split(b'\n')
    lines.pop()  # Last line is empty or an incomplete write.
    if offset and lines: lines.pop(0)
    for line in reversed(lines):
        try:
            event = json.loads(line)
            if event.get('type') != 'event_msg': continue
            kind = event.get('payload', {}).get('type')
            if kind == 'task_started': return 'active'
            if kind in ('task_complete', 'turn_aborted'): return 'idle'
        except (ValueError, AttributeError): continue
    return 'unknown'

def sample(home):
    result = {'version': 1, 'available': False, 'tasks': [], 'message': ''}
    try:
        locks = []
        for path in (home / 'thread-writer-locks').glob('*.lock'):
            try: uuid.UUID(path.stem)
            except ValueError: continue
            try: fd = os.open(str(path), os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
            except FileNotFoundError: continue
            with os.fdopen(fd, 'rb') as stream:
                if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode): continue
                try: fcntl.flock(stream, fcntl.LOCK_SH | fcntl.LOCK_NB)
                except BlockingIOError: locks.append(path.stem)
        if not (home / 'thread-writer-locks').is_dir():
            raise ValueError('Codex writer-lock directory is missing')
        if len(locks) > 256: raise ValueError('Too many live tasks to sample safely')
        with database(home / 'state_5.sqlite') as metadata:
            for task_id in sorted(locks):
                row = metadata.execute('SELECT history_mode, rollout_path FROM threads WHERE id = ? AND archived = 0', (task_id,)).fetchone()
                if row is None: continue
                status, detail = 'unknown', 'No recognized turn status yet'
                try:
                    if row[0] == 'paginated':
                        with database(home / 'thread_history_1.sqlite') as history:
                            turn = history.execute('SELECT status FROM thread_turns WHERE thread_id = ? ORDER BY rollout_ordinal DESC LIMIT 1', (task_id,)).fetchone()
                            status = activity(turn[0] if turn else None)
                    elif row[0] == 'legacy': status = legacy(row[1])
                except (OSError, sqlite3.Error): detail = 'Task lifecycle record could not be read'
                fields = ('', '')
                for title in ["COALESCE(NULLIF(name, ''), title)", 'title']:
                    try:
                        fields = metadata.execute('SELECT substr(' + title + ', 1, 240), substr(cwd, 1, 4096) FROM threads WHERE id = ?', (task_id,)).fetchone() or fields
                        break
                    except sqlite3.Error: pass
                result['tasks'].append({'id': task_id, 'activity': status, 'title': text(fields[0]), 'project': text(pathlib.Path(fields[1]).name) if fields[1] else '', 'statusDetail': detail if status == 'unknown' else ''})
        result['available'] = True
        result['message'] = 'Connected over SSH'
    except (OSError, sqlite3.Error, ValueError):
        result['tasks'] = []
        result['message'] = 'Remote Codex data is missing, busy, or unsupported'
    return result

home = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(os.environ.get('CODEX_HOME', str(pathlib.Path.home() / '.codex')))
print(json.dumps(sample(home.absolute()), ensure_ascii=True))
"""#
}
