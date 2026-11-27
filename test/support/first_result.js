// A result its page asks for the first time shows its operation's progress in
// the result itself, as the page's first load does: an edit made before the
// first answer arrived, a tab the reader opens, and a tab a mutation's
// `open_tab` opens. A result already on the screen stays there while its next
// answer computes, reported beside it.
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
  const report = {};
  // The page's first request for its open tab is still on its way when the
  // reader picks another setting: the new request replaces it.
  let edited = false;
  document.addEventListener('htmx:beforeSend', e => {
    const path = e.detail.requestConfig.path || '';
    if (edited || path.indexOf('/initial') !== 0) return;
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
      await until(() => shown('initial', 'b'), 'the edited first result');

      document.querySelector('a[data-tab-name="clicked"]').click();
      report.clicked = await running('clicked');
      await release('clicked:b');
      await until(() => shown('clicked', 'b'), 'the clicked result');

      pick('c');
      report.refresh = await running('clicked');
      report.refresh.kept = !!shown('clicked', 'b');
      await release('clicked:c');
      await until(() => shown('clicked', 'c') && reporter('clicked').hidden, 'the refreshed result');

      document.querySelector('a[data-tab-name="add"]').click();
      await sleep(100);
      const form = document.querySelector('form[hx-post="/add"]');
      form.querySelector('input[name="name"]').value = 'a';
      form.requestSubmit();
      report.opened = await running('opened');
      report.opened.tab = document.querySelector('a[data-tab-name="opened"]').getAttribute('aria-selected');
      await release('opened:a');
      await until(() => shown('opened', 'a'), 'the opened result');
    } catch (err) { report.error = String(err.stack || err); }
    await fetch('/test-report', {method: 'POST', body: JSON.stringify(report)});
  });
})();
