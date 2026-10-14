import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';

test('Tailwind native watcher rebuilds changed and newly added source files', {timeout: 30000}, async () => {
  // Keep the fixture under the project so CSS package resolution uses this lockfile.
  const cache = path.resolve('.cache');
  await mkdir(cache, {recursive: true});
  const fixture = await mkdtemp(path.join(cache, 'tailwind-watch-'));
  let child;
  let closed;
  let logs = '';
  let failure;
  let hasClosed = false;
  try {
    await mkdir(path.join(fixture, 'content'));
    const source = path.join(fixture, 'content', 'index.html');
    const output = path.join(fixture, 'output.css');
    await writeFile(path.join(fixture, 'input.css'), '@import "tailwindcss" source(none);\n@source "./content";\n');
    await writeFile(source, '<div class="p-[13px]"></div>');
    child = spawn(process.execPath, [
      path.resolve('node_modules/@tailwindcss/cli/dist/index.mjs'),
      '-i', path.join(fixture, 'input.css'), '-o', output, '--watch=always',
    ], {stdio: ['ignore', 'pipe', 'pipe']});
    closed = new Promise(resolve => child.once('close', () => {
      hasClosed = true;
      resolve();
    }));
    child.on('error', error => { failure = error; });
    child.stdout.on('data', chunk => { logs += chunk; });
    child.stderr.on('data', chunk => { logs += chunk; });

    async function waitForCss(fragment) {
      const deadline = Date.now() + 8000;
      while (Date.now() < deadline) {
        if (failure) throw failure;
        assert.ok(!hasClosed && child.exitCode === null && child.signalCode === null, `Tailwind exited early: ${logs}`);
        let css = '';
        try { css = await readFile(output, 'utf8'); }
        catch (error) { if (error.code !== 'ENOENT') throw error; }
        if (css.includes(fragment)) return;
        await delay(50);
      }
      assert.fail(`Tailwind did not emit ${fragment}: ${logs}`);
    }

    await waitForCss('padding: 13px');
    await writeFile(source, '<div class="p-[17px]"></div>');
    await waitForCss('padding: 17px');
    await writeFile(path.join(fixture, 'content', 'new.html'), '<div class="m-[19px]"></div>');
    await waitForCss('margin: 19px');
    assert.equal(child.exitCode, null);
  } finally {
    try {
      if (child && !hasClosed) {
        child.kill();
        await Promise.race([closed, delay(1000)]);
        if (!hasClosed) {
          child.kill('SIGKILL');
          await Promise.race([closed, delay(1000)]);
        }
        assert.ok(hasClosed, 'Tailwind child did not stop');
      }
    } finally {
      await rm(fixture, {recursive: true, force: true});
    }
  }
});
