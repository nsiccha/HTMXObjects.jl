// Exercise the generated page, its real htmx requests and its EventSource.
// For the late-stream trial, withhold progress until the first recovery poll.
(function () {
  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
  async function until(check, name) {
    const end = performance.now() + 15000;
    while (!check()) {
      if (performance.now() > end) throw Error('Timed out waiting for ' + name);
      await sleep(10);
    }
  }
  const report = {headerEvents: 0};
  let trial, region, input, source, lastResult;
  const NativeSource = window.EventSource;
  window.EventSource = class extends NativeSource {
    constructor(url) {
      super(url);
      source = this;
      super.addEventListener('result', e => { lastResult = e.data; });
    }
    addEventListener(type, listener, options) {
      if (type === 'progress') {
        super.addEventListener(type, e => {
          if (trial && trial.name === 'late') return;
          listener.call(this, e);
          if (this === source && trial && trial.name === 'drop' && !trial.released) {
            this.close();
            this.dispatchEvent(new Event('error'));
            release(9);
          }
        }, options);
      } else super.addEventListener(type, listener, options);
    }
  };
  document.addEventListener('tab-header', () => report.headerEvents++);
  document.addEventListener('htmx:beforeSend', e => {
    const request = trial;
    if (!request) return;
    const url = new URL(e.detail.requestConfig.path, location.href);
    if (url.pathname !== '/tab_preview') return;
    if (url.searchParams.has('__htmxo_poll')) {
      request.polls++;
      if (request.name === 'failure') {
        const xhr = e.detail.xhr;
        xhr.addEventListener('load', () => {
          request.errorStatus = xhr.status;
          request.errorId = xhr.getResponseHeader('X-HTMXO-Error-Id');
        }, {once: true});
      }
      if (request.name === 'late' && source && source.readyState === NativeSource.OPEN && !request.released) {
        e.detail.xhr.addEventListener('loadend', () => release(4), {once: true});
      }
    } else {
      request.requests++;
      request.sent = performance.now() - request.start;
      e.detail.xhr.addEventListener('load', () => {
        request.deferred = e.detail.xhr.responseText.includes('treebar-poller-inner');
      }, {once: true});
    }
  });
  document.addEventListener('htmx:beforeSwap', e => {
    const d = e.detail;
    if (!trial || !d.htmxoLiveTerminal || d.target !== region) return;
    trial.offers++;
    trial.pushed = !!d.treebarPushed;
    if (trial.name === 'veto') e.preventDefault();
    if (trial.name === 'stream') d.serverResponse = d.serverResponse.replace('Result 2', 'Edited 2');
  });
  function release(value) {
    trial.released = performance.now() - trial.start;
    return fetch('/test-release/' + value);
  }
  function begin(name) {
    trial = report[name] = {name, requests: 0, polls: 0, offers: 0, start: performance.now()};
  }
  function commit(value) {
    input.value = value;
    const edit = trial;
    edit.start = performance.now();
    input.dispatchEvent(new Event('change', {bubbles: true}));
    input.dispatchEvent(new Event('change', {bubbles: true}));
    setTimeout(() => { edit.nextTurn = edit.requests === 1; }, 0);
  }
  const reporter = () => region.nextElementSibling;
  const shown = value => region.querySelector('[data-value="' + value + '"]');
  async function run(name, value, previous = value - 1) {
    begin(name);
    const previousSource = source;
    commit(value);
    if (value > 1) {
      await until(() => reporter().querySelector('.treebar-poller-inner') &&
        source && source !== previousSource, 'reporter and stream');
      if (!shown(previous)) throw Error('Previous result lost during ' + name);
      if (name === 'superseded') return; // leave this worker running across the next edit
      if (name === 'newer') await fetch('/test-release/7');
      if (name === 'pause') reporter().querySelector('.treebar-pause').click();
      if (name === 'legacy') reporter().querySelector('[data-htmxo-operation-stream]')
        .setAttribute('data-htmxo-operation-stream', '');
      if (name !== 'late' && name !== 'drop') await release(value);
      if (name === 'pause') {
        await until(() => source.readyState === NativeSource.CLOSED, 'paused completion');
        if (!shown(previous) || trial.offers) throw Error('Paused result landed early');
        reporter().querySelector('.treebar-pause').click();
      }
    }
    if (name === 'veto') {
      await until(() => trial.offers && reporter().hidden, 'vetoed answer');
      if (!shown(previous)) throw Error('Live target ignored the veto');
    } else if (name === 'failure') {
      await until(() => trial.errorId && region.innerHTML.includes(trial.errorId), 'recorded failure');
    } else {
      await until(() => shown(value), name + ' result');
    }
    trial.rendered = performance.now() - trial.start;
    if (name === 'stream') {
      if (region.textContent !== 'Edited 2') throw Error('Rewrite lost');
      source.dispatchEvent(new MessageEvent('result', {data: lastResult}));
    }
    if (value > 1 && (!reporter().hidden || region.hasAttribute('data-htmxo-live-busy')))
      throw Error('Refresh stayed busy');
    // Let the completed stream close before starting the next trial.
    if (value > 1) await until(() => source.readyState === NativeSource.CLOSED, 'stream close');
  }
  window.addEventListener('load', async () => {
    try {
      region = document.querySelector('[data-htmxo-follow="/tab_preview"]');
      input = document.querySelector('input[name="setting"]');
      await until(() => region.querySelector('[data-value="0"]'), 'initial result');
      await sleep(400);
      begin('typing');
      input.value = '1';
      input.dispatchEvent(new Event('input', {bubbles: true}));
      await sleep(350);
      report.typingRequests = trial.requests;
      begin('invalid');
      input.setCustomValidity('Choose a valid setting');
      commit(1);
      await sleep(350);
      input.setCustomValidity('');
      await run('inline', 1);
      await run('stream', 2);
      await run('headers', 3);
      await run('late', 4);
      await run('pause', 5);
      await run('veto', 6);
      await run('superseded', 7, 5);
      await run('newer', 8, 5);
      await run('drop', 9);
      await run('legacy', 10);
      await run('failure', 11);
    } catch (err) { report.error = String(err.stack || err); }
    await fetch('/test-report', {method: 'POST', body: JSON.stringify(report)});
  });
})();
