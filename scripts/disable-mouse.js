#!/usr/bin/env node
// Run a command in a PTY and strip terminal mouse-tracking from its output.
//
// Claude Code (like most TUIs) turns on mouse reporting by emitting DEC private
// mode "set" sequences (e.g. ESC[?1000h, ESC[?1006h). While that mode is
// active, some terminals -- notably macOS Terminal.app -- capture mouse drags
// for the application instead of doing a normal text selection, so output can
// no longer be selected/copied with a plain drag.
//
// Claude Code offers no option to turn mouse reporting off, so we filter it out
// a layer below: the wrapped command runs under `script`, which gives it a real
// PTY (it still renders as a TUI), and we drop the mouse enable/disable
// sequences from the stream that flows back to the outer terminal. The terminal
// therefore never enters mouse mode and ordinary selection keeps working -- at
// the cost of mouse interaction inside the TUI, which is exactly the intent.
'use strict';

const { spawn } = require('child_process');

const argv = process.argv.slice(2);
if (argv.length === 0) {
  process.stderr.write('claudainer-disable-mouse: no command given\n');
  process.exit(2);
}

// DEC private mode set/reset for the mouse-tracking modes:
//   9    X10 compatibility            1003  any-event tracking
//   1000 normal (click) tracking      1005  UTF-8 extended coordinates
//   1001 highlight tracking           1006  SGR extended coordinates
//   1002 button-event tracking        1015  urxvt extended coordinates
// Both enable (h) and disable (l) are stripped so nothing can toggle the mode.
const MOUSE = /\x1b\[\?(?:9|1000|1001|1002|1003|1005|1006|1015)[hl]/g;

// A trailing, not-yet-terminated CSI: a lone ESC, or ESC[ / ESC[? / ESC[?123;…
// without the final letter. Held back so a mouse sequence split across two
// chunks is still matched once the rest arrives.
const PARTIAL = /\x1b(?:\[\??[0-9;]*)?$/;

// Single-quote an argument for the `sh -c` string that `script` runs.
const shellQuote = (arg) => `'${arg.replace(/'/g, `'\\''`)}'`;
const command = argv.map(shellQuote).join(' ');

// `script` (util-linux) gives the child a real PTY so it still renders as a
// TUI; we filter the stream it prints. stdin/stderr are inherited so input and
// errors pass straight through; stdout is piped so we can strip mouse codes.
//   -q quiet  -e return child's exit code  -f flush after each write
const child = spawn('script', ['-q', '-e', '-f', '-c', command, '/dev/null'], {
  stdio: ['inherit', 'pipe', 'inherit'],
});

// latin1 maps each byte to one code point and back losslessly, so the
// ASCII-only patterns above operate on raw bytes without mangling UTF-8.
let pending = '';

child.stdout.on('data', (chunk) => {
  let data = (pending + chunk.toString('latin1')).replace(MOUSE, '');
  const tail = PARTIAL.exec(data);
  if (tail) {
    pending = data.slice(tail.index);
    data = data.slice(0, tail.index);
  } else {
    pending = '';
  }
  if (data) process.stdout.write(Buffer.from(data, 'latin1'));
});

child.stdout.on('end', () => {
  if (pending) {
    const flushed = pending.replace(MOUSE, '');
    if (flushed) process.stdout.write(Buffer.from(flushed, 'latin1'));
    pending = '';
  }
});

child.on('error', (err) => {
  process.stderr.write(`claudainer-disable-mouse: ${err.message}\n`);
  process.exit(127);
});

child.on('exit', (code) => {
  process.exit(code == null ? 1 : code);
});
