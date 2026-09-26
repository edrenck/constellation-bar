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

def versioned(home, prefix, fallback):
    candidates = [(int(p.stem[len(prefix)+1:]), p) for p in home.glob(prefix + '_*.sqlite') if p.stem[len(prefix)+1:].isdigit()]
    if candidates: return max(candidates)[1]
    return next((home / name for name in (prefix + '.sqlite', prefix + '.db') if (home / name).is_file()), home / fallback)

def user_task(source, agent_path):
    if source == 'subagent': return False
    try:
        value = json.loads(source or '{}')
        if isinstance(value, dict) and 'subagent' in value: return False
    except (ValueError, TypeError): pass
    return not agent_path or agent_path == '/root'

def rollout_path(value, home):
    if not value: return None
    path = pathlib.Path(value).expanduser()
    return path if path.is_absolute() else home / path

def history_path(home, rollout):
    local = versioned(home, 'thread_history', 'thread_history_1.sqlite')
    if local.is_file(): return local
    if rollout:
        for ancestor in list(rollout.parents)[:4]:
            if ancestor.name in ('sessions', 'archived_sessions'):
                sibling = versioned(ancestor.parent, 'thread_history', 'thread_history_1.sqlite')
                if sibling.is_file(): return sibling
                break
    return local

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
        if len(locks) > 256: raise ValueError('Too many live tasks to sample safely')
        with database(versioned(home, 'state', 'state_5.sqlite')) as metadata:
            columns = {row[1] for row in metadata.execute('PRAGMA table_info(threads)')}
            history_column = 'history_mode' if 'history_mode' in columns else "'legacy'"
            source_column = 'source' if 'source' in columns else "''"
            agent_path_column = 'agent_path' if 'agent_path' in columns else "''"
            for task_id in sorted(locks):
                row = metadata.execute('SELECT ' + history_column + ', rollout_path, ' + source_column + ', ' + agent_path_column + ' FROM threads WHERE id = ? AND archived = 0', (task_id,)).fetchone()
                if row is None or not user_task(row[2], row[3]): continue
                rollout = rollout_path(row[1], home)
                status, detail = 'unknown', 'No recognized turn status yet'
                try:
                    if row[0] == 'paginated':
                        with database(history_path(home, rollout)) as history:
                            turn = history.execute('SELECT status FROM thread_turns WHERE thread_id = ? ORDER BY rollout_ordinal DESC LIMIT 1', (task_id,)).fetchone()
                            status = activity(turn[0]) if turn else 'idle'
                    elif row[0] == 'legacy' and rollout: status = legacy(rollout)
                except (OSError, sqlite3.Error):
                    detail = 'Task lifecycle record could not be read'
                    if row[0] == 'paginated' and rollout:
                        try: status = legacy(rollout)
                        except OSError: pass
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
