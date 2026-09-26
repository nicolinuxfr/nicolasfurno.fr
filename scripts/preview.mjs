import { spawn } from 'node:child_process';
import { watch } from 'node:fs';

const server = spawn('hugo', ['server'], { stdio: 'inherit' });
let timer;
let running = false;
let pending = false;

async function refresh() {
  if (running) { pending = true; return; }
  running = true;
  do {
    pending = false;
    const discovery = spawn(process.execPath, ['scripts/discovery.mjs'], { stdio: 'inherit' });
    const code = await new Promise(resolve => discovery.on('close', resolve));
    if (code !== 0) console.error('La mise à jour des fiches de personnes a échoué.');
  } while (pending);
  running = false;
}

const content = watch('content', { recursive: true }, () => {
  clearTimeout(timer);
  timer = setTimeout(refresh, 500);
});

function stop(signal) {
  clearTimeout(timer);
  content.close();
  server.kill(signal);
}

process.on('SIGINT', () => stop('SIGINT'));
process.on('SIGTERM', () => stop('SIGTERM'));
server.on('close', code => { content.close(); process.exitCode = code || 0; });
