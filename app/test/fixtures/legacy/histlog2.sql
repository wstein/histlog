CREATE TABLE shells (
    	id INTEGER PRIMARY KEY AUTOINCREMENT,
    	path TEXT UNIQUE NOT NULL,
    	version TEXT,
    	created_at REAL DEFAULT (julianday('now'))
        );
CREATE TABLE sqlite_sequence(name,seq);
CREATE TABLE ttys (
    	id INTEGER PRIMARY KEY AUTOINCREMENT,
    	device TEXT NOT NULL,
    	created_at REAL DEFAULT (julianday('now'))
        );
CREATE TABLE paths (
    	id INTEGER PRIMARY KEY AUTOINCREMENT,
    	path TEXT NOT NULL,
    	type TEXT NOT NULL CHECK (type IN ('f', 'd')),
    	created_at REAL DEFAULT (julianday('now'))
        );
CREATE TABLE sessions (
    	id INTEGER PRIMARY KEY AUTOINCREMENT,
    	shell_id INTEGER,
    	tty_id INTEGER,
    	path_id INTEGER,
    	pid INTEGER,
    	parent_pid INTEGER,
    	start_time REAL,
    	timezone TEXT,
    	created_at REAL DEFAULT (julianday('now')),
    	FOREIGN KEY (shell_id) REFERENCES shells (id),
    	FOREIGN KEY (tty_id) REFERENCES ttys (id),
    	FOREIGN KEY (path_id) REFERENCES paths (id)
        );
CREATE TABLE metadata (
            key TEXT PRIMARY KEY,
            value TEXT
          );
CREATE TABLE cmd_texts (
    	id INTEGER PRIMARY KEY AUTOINCREMENT,
    	command TEXT UNIQUE NOT NULL,
    	created_at REAL DEFAULT (julianday('now'))
        );
CREATE TABLE commands (
    	id INTEGER PRIMARY KEY AUTOINCREMENT,
    	session_id INTEGER,
    	cmd_text_id INTEGER,
    	path_old_id INTEGER,
    	path_new_id INTEGER,
    	start_time REAL,
    	duration REAL,
    	exit_code INTEGER,
    	is_private INTEGER DEFAULT 0,
    	is_assisted INTEGER DEFAULT 0,
    	created_at REAL DEFAULT (julianday('now')),
    	FOREIGN KEY (session_id) REFERENCES sessions (id),
    	FOREIGN KEY (cmd_text_id) REFERENCES cmd_texts (id),
    	FOREIGN KEY (path_old_id) REFERENCES paths (id),
    	FOREIGN KEY (path_new_id) REFERENCES paths (id)
        );
CREATE TABLE path_args (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        command_id INTEGER,
        path_id INTEGER,
        arg_position INTEGER,
        created_at REAL DEFAULT (julianday('now')),
        FOREIGN KEY (command_id) REFERENCES commands (id),
        FOREIGN KEY (path_id) REFERENCES paths (id),
        UNIQUE (command_id, path_id, arg_position)
        );
CREATE INDEX idx_shells_path ON shells (path);
CREATE INDEX idx_ttys_device ON ttys (device);
CREATE INDEX idx_paths_path ON paths (path);
CREATE INDEX idx_paths_type ON paths (type);
CREATE INDEX idx_sessions_shell_id ON sessions (shell_id);
CREATE INDEX idx_sessions_created_at ON sessions (created_at);
CREATE INDEX idx_sessions_start_time ON sessions (start_time);
CREATE INDEX idx_sessions_path_id ON sessions (path_id);
CREATE UNIQUE INDEX idx_cmd_texts_command ON cmd_texts (command);
CREATE INDEX idx_cmd_texts_created_at ON cmd_texts (created_at);
CREATE INDEX idx_commands_session_id ON commands (session_id);
CREATE INDEX idx_commands_cmd_text_id ON commands (cmd_text_id);
CREATE INDEX idx_commands_created_at ON commands (created_at);
CREATE INDEX idx_commands_start_time ON commands (start_time);
CREATE INDEX idx_commands_exit_code ON commands (exit_code);
CREATE INDEX idx_path_args_command_id ON path_args (command_id);
CREATE INDEX idx_path_args_path_id ON path_args (path_id);
CREATE INDEX idx_commands_session_id_created_at ON commands (session_id, created_at);
CREATE INDEX idx_commands_exit_code_created_at ON commands (exit_code, created_at);
CREATE INDEX idx_path_args_command_id_arg_position ON path_args (command_id, arg_position);
CREATE INDEX idx_commands_session_created_where_failed ON commands (session_id, created_at) WHERE exit_code != 0;
CREATE INDEX idx_paths_path_where_file ON paths (path) WHERE type = 'f';
CREATE INDEX idx_paths_path_where_dir ON paths (path) WHERE type = 'd';
CREATE VIEW history_view AS
        SELECT
    	cmd.id as cmd_text_id,
    	cmd.session_id as session_id,
    	s.pid as session_pid,
    	s.parent_pid as session_parent_pid,
    	datetime(s.created_at, 'unixepoch') as session_started,
    	sh.path as shell_path,
    	t.device as tty_device,
    	c.command,
    	datetime(cmd.start_time, 'unixepoch') as command_started,
    	cmd.start_time as start_time,
    	cmd.duration,
    	cmd.exit_code,
    	cmd.is_private,
    	p_old.path as cwd_old,
    	p_new.path as cwd_new,
    	CASE
    	WHEN p_old.path IS NOT NULL AND p_new.path IS NOT NULL AND p_old.path != p_new.path THEN 1
    	ELSE 0
    	END as directory_changed
    	FROM commands cmd
        LEFT JOIN sessions s ON cmd.session_id = s.id
    	JOIN cmd_texts c ON cmd.cmd_text_id = c.id
        LEFT JOIN shells sh ON s.shell_id = sh.id
        LEFT JOIN ttys t ON s.tty_id = t.id
        LEFT JOIN paths p_old ON cmd.path_old_id = p_old.id
        LEFT JOIN paths p_new ON cmd.path_new_id = p_new.id
      ORDER BY cmd.start_time DESC
/* history_view(cmd_text_id,session_id,session_pid,session_parent_pid,session_started,shell_path,tty_device,command,command_started,start_time,duration,exit_code,is_private,cwd_old,cwd_new,directory_changed) */;
CREATE VIEW sessions_view AS
        SELECT
    	s.id as session_id,
    	s.pid,
    	s.parent_pid,
    	s.timezone,
    	s.created_at,
    	datetime(s.created_at) as created_time,
    	sh.path as shell_path,
    	sh.version as shell_version,
    	t.device as tty_device,
    	p.path as working_directory
        FROM sessions s
        LEFT JOIN shells sh ON s.shell_id = sh.id
        LEFT JOIN ttys t ON s.tty_id = t.id
        LEFT JOIN paths p ON s.path_id = p.id
/* sessions_view(session_id,pid,parent_pid,timezone,created_at,created_time,shell_path,shell_version,tty_device,working_directory) */;
