// A result its page asks for the first time shows its operation's progress in
// the result itself, as the page's first load does: an edit made before the
// first answer arrived, a tab the reader opens, and a tab a mutation's
// `open_tab` opens. A result already on the screen stays there while its next
// answer computes, reported beside it, until the page's `progress_after`; then
// the progress takes its place. A tab `open_tab` opens for other inputs starts
// over at once, and one it opens for the inputs it shows keeps its result.
(function () {
  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
  async function until(check, name) {
    const end = performance.now() + 15000;
    while (!check()) {
      if (performance.now() > end) throw Error('Timed out waiting for ' + name);
      await sleep(10);
    }
  }
  const region = view => document.querySelector('[data-htmxo-follow="/' + view + '"]');
  const reporter = view => {
    const next = region(view).nextElementSibling;
    return next && next.classList.contains('htmxo-live-reporter') ? next : null;
  };
  const shown = (view, key) => region(view).querySelector('[data-result="' + view + ':' + key + '"]');
  const polling = el => el && el.querySelector('.treebar-poller');
  const pick = value => document.querySelector('input[name="setting"][value="' + value + '"]').click();
  const release = key => fetch('/test-release/' + key);
  const tab = view => document.querySelector('a[data-tab-name="' + view + '"]');
  // What the reader sees of the operation running for `view`.
  function progress(view) {
    const r = region(view), poller = polling(r), rep = reporter(view);
    const tree = poller && poller.querySelector('.treebar-poller-inner');
    return {
      inResult: !!poller,
      beside: !!polling(rep),
      standIn: !!r.querySelector(':scope > progress, :scope > [hx-trigger]'),
      tree: !!tree && tree.checkVisibility() && tree.getBoundingClientRect().height > 0,
      text: poller ? poller.innerText : ''
    };
  }
  async function running(view) {
    await until(() => polling(region(view)) || polling(reporter(view)), 'the operation of ' + view);
    // Its progress tree arrives with the poller; let the page settle around it.
    await sleep(150);
    return progress(view);
  }
  // The page is left as it should be once `view` shows the result for `key`.
  async function landed(view, key) {
    await until(() => shown(view, key) && !polling(region(view)) && !polling(reporter(view)),
      'the result ' + view + ':' + key);
    const rep = reporter(view);
    return region(view).children.length === 1 && (!rep || rep.hidden) &&
      !region(view).hasAttribute('data-htmxo-live-busy');
  }
  // The mutation of the Add tab, which answers `open_tab("opened"; setting=name)`.
  async function add(name) {
    tab('add').click();
    await sleep(100);
    const form = document.querySelector('form[hx-post="/add"]');
    form.querySelector('input[name="name"]').value = name;
    form.requestSubmit();
  }
  const report = {}, requests = {};
  // The page's first request for its open tab is still on its way when the
  // reader picks another setting: the new request replaces it.
  let edited = false;
  document.addEventListener('htmx:beforeSend', e => {
    const url = new URL(e.detail.requestConfig.path, location.href);
    if (url.searchParams.has('__htmxo_poll') || url.searchParams.has('__htmxo_form')) return;
    const view = url.pathname.slice(1);
    requests[view] = (requests[view] || 0) + 1;
    if (edited || view !== 'initial') return;
    edited = true;
    report.placeholder = !!region('initial').querySelector(':scope > [hx-trigger]');
    // Once the page's own load handlers have run, and long before the held
    // answer could arrive.
    setTimeout(() => pick('b'), 0);
  });
  window.addEventListener('load', async () => {
    try {
      report.edit = await running('initial');
      await release('initial:b');
      await landed('initial', 'b');

      tab('clicked').click();
      report.clicked = await running('clicked');
      await release('clicked:b');
      await landed('clicked', 'b');

      // A result on screen stays while its next answer computes...
      pick('c');
      report.refresh = await running('clicked');
      report.refresh.kept = !!shown('clicked', 'b');
      // ...until the page's `progress_after`: then the progress takes its place.
      await until(() => polling(region('clicked')), 'the progress in place of the result');
      report.takeover = progress('clicked');
      report.takeover.kept = !!shown('clicked', 'b');
      report.takeover.busy = region('clicked').hasAttribute('data-htmxo-live-busy');
      await release('clicked:c');
      report.takeover.landed = await landed('clicked', 'c');

      // A tab a mutation's answer opens for the first time.
      await add('a');
      report.opened = await running('opened');
      report.opened.tab = tab('opened').getAttribute('aria-selected');
      await release('opened:a');
      await landed('opened', 'a');

      // Opened again for another setting, it starts over at once.
      await add('b');
      report.reopened = await running('opened');
      report.reopened.kept = !!shown('opened', 'a');
      await release('opened:b');
      report.reopened.landed = await landed('opened', 'b');

      // Opened for the setting it shows, it keeps its result: the page asks
      // for it again, as after any mutation, and never draws the first-load bar.
      let bar = false;
      const watch = new MutationObserver(() => { bar = bar || !!region('opened').querySelector(':scope > progress'); });
      watch.observe(region('opened'), {childList: true});
      const before = requests.opened || 0;
      await add('b');
      await until(() => tab('opened').getAttribute('aria-selected') === 'true' &&
        (requests.opened || 0) > before, 'the tab opened again');
      await sleep(400);
      watch.disconnect();
      report.same = {bar, requests: (requests.opened || 0) - before, kept: await landed('opened', 'b')};
    } catch (err) { report.error = String(err.stack || err); }
    await fetch('/test-report', {method: 'POST', body: JSON.stringify(report)});
  });
})();
