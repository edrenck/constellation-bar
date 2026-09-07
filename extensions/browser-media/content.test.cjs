const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(__dirname + '/content.js', 'utf8');
(async () => {
  let listener, snapshot, stopped = false;
  const element = { paused: true, ended: false, readyState: 4, duration: 120, currentTime: 10, seekable: { length: 1 },
    async play() { this.paused = false; }, pause() { this.paused = true; } };
  const context = {
    document: { title: 'Example video', querySelectorAll: () => [element] },
    chrome: { runtime: { async sendMessage(message) { snapshot = message.state; }, onMessage: {
      addListener(value) { listener = value; }, removeListener(value) { if (listener === value) listener = null; }
    }}},
    setInterval: () => 1, clearInterval: () => { stopped = true; }, Date, Number, Error
  };
  vm.runInNewContext(source, context);
  assert.equal(snapshot.title, 'Example video');
  assert.equal(snapshot.canSeek, true);
  const command = (id, action, position) => ({ type: 'command', command: { id, action, position, timestamp: Date.now() / 1000 } });
  await listener(command('one', 'playPause'));
  assert.equal(element.paused, false);
  assert.equal(snapshot.acknowledged, 'one');
  await listener(command('one', 'playPause'));
  assert.equal(element.paused, false, 'duplicate command must not toggle again');
  await listener(command('two', 'seek', 900));
  assert.equal(element.currentTime, 120);
  await listener(command('three', 'arbitraryScript'));
  assert.match(snapshot.error, /not supported/);
  element.play = async () => { throw Error('Playback blocked'); }; element.paused = true;
  await listener(command('four', 'playPause'));
  assert.equal(snapshot.error, 'Playback blocked');
  await listener({ type: 'stop' });
  assert.equal(stopped, true); assert.equal(listener, null);
  console.log('Browser content tests passed');
})();
