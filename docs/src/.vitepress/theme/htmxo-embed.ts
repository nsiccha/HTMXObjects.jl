// HTMXObjects ↔ VitePress integration helpers.
//
// Call `setupHtmxoEmbed(router)` from your VitePress theme's `enhanceApp`
// to enable two embedding patterns:
//
//   1. `<div data-hx-base="live-app/" hx-trigger="load">` — the base path
//      is resolved at runtime (dev → `/`, prod → the deploy abspath
//      injected via `__DEPLOY_ABSPATH__`), so the same markdown works
//      under `npm run docs:dev` (Vite proxy) and the deployed site
//      (committed recordings).
//
//   2. `<div class="htmxo-embed" hx-get="…">` — every root-absolute
//      `href` / `hx-*` URL inside the swapped fragment gets rewritten
//      to go through a proxy prefix (default `/live-htmxo`, overridable
//      per-page via `<meta name="htmxo-embed-prefix" content="/live-foo">`).
//      Without this, fragment-internal links 404 against VitePress's
//      origin.
//
// Plus the standard VitePress-SPA fix: re-process new HTMX placeholders
// after every client-side route change.
//
// This file lives at HTMXObjects/assets/vitepress/htmxo-embed.ts. The
// Julia helper `vitepress_theme_install(theme_dir)` copies it into a
// docs theme directory; `make.jl` calls that helper before
// DocumenterVitepress runs.

declare const __DEPLOY_ABSPATH__: string | undefined;

interface HtmxoEmbedOptions {
    /** Default proxy prefix for root-absolute link rewriting inside
     *  `.htmxo-embed` containers. Per-page override via
     *  `<meta name="htmxo-embed-prefix" content="/live-foo">`. */
    proxyPrefix?: string;
}

/**
 * Wire HTMXObjects-embed behavior into a VitePress router.
 *
 * Call from `enhanceApp({ router })`. Idempotent: if called twice
 * (e.g. via HMR) the second call replaces the first.
 */
export function setupHtmxoEmbed(router: any, options: HtmxoEmbedOptions = {}) {
    if (typeof window === 'undefined' || !router) return;

    // Resolve the deploy base. Dev mode and the unreplaced
    // `REPLACE_ME_…` placeholder both fall back to `/` (matches the Vite
    // proxy paths). In a Documenter-built deploy, `__DEPLOY_ABSPATH__`
    // is replaced with the absolute base (e.g. `/MyPkg.jl/dev/`) and
    // recording paths resolve against that.
    const deployBase = (() => {
        // @ts-ignore - vite-injected env
        const dev = (import.meta as any).env?.DEV;
        if (dev) return '/';
        const v: string | undefined =
            (typeof __DEPLOY_ABSPATH__ !== 'undefined') ? __DEPLOY_ABSPATH__ : undefined;
        return (v && !v.startsWith('REPLACE_ME')) ? v : '/';
    })();

    const resolveProxyPrefix = () =>
        document.querySelector('meta[name="htmxo-embed-prefix"]')?.getAttribute('content')
        ?? options.proxyPrefix
        ?? '/live-htmxo';

    // (1) data-hx-base placeholders. Setting `hx-get` and calling
    // `htmx.process(el)` doesn't re-fire `hx-trigger="load"` on an
    // already-scanned element, so the request never goes out. Fire the
    // GET directly via `htmx.ajax` — the response goes through normal
    // `htmx:afterSwap`, so link rewriting (3) applies. If htmx hasn't
    // finished loading from the CDN yet we poll briefly: the marker
    // (`data-hx-base-loaded`) only flips to `1` once the ajax actually
    // fires, so a re-scan from the MutationObserver / route change won't
    // double-fire.
    const fireWhenReady = (el: HTMLElement, url: string, swap: string, tries = 0) => {
        // @ts-ignore - htmx loaded via head <script>; no types
        const htmx = window.htmx;
        if (htmx) {
            el.dataset.hxBaseLoaded = '1';
            htmx.ajax('GET', url, { target: el, swap });
            return;
        }
        if (tries > 200) return; // ~10s ceiling
        setTimeout(() => fireWhenReady(el, url, swap, tries + 1), 50);
    };
    const processHxBase = (root: ParentNode) => {
        root.querySelectorAll<HTMLElement>('[data-hx-base]').forEach((el) => {
            if (el.dataset.hxBaseLoaded === '1' || el.dataset.hxBasePending === '1') return;
            el.dataset.hxBasePending = '1';
            const suffix = el.getAttribute('data-hx-base') || '';
            const url = deployBase.replace(/\/$/, '') + '/' + suffix;
            const swap = el.getAttribute('hx-swap') || 'innerHTML';
            fireWhenReady(el, url, swap);
        });
    };

    // (2) Re-process new HTMX placeholders after VitePress SPA
    // navigation. Initial mount handled by htmx's own DOMContentLoaded
    // auto-process; this only matters for client-side route changes.
    router.onAfterRouteChanged = () => {
        processHxBase(document.body);
        // @ts-ignore - htmx loaded via head <script>; no types
        if (window.htmx) window.htmx.process(document.body);
    };

    // Initial mount + late-arriving placeholders: enhanceApp runs
    // before Vue's first render and `onAfterRouteChanged` doesn't fire
    // for the initial route, so a single deferred scan races Vue. A
    // MutationObserver catches the placeholder regardless of when the
    // SPA inserts it. We also do a one-shot scan in case the element
    // is already present (no mutation event would fire for it).
    processHxBase(document.body);
    const observer = new MutationObserver((mutations) => {
        for (const m of mutations) {
            for (const node of m.addedNodes) {
                if (!(node instanceof HTMLElement)) continue;
                if (node.matches?.('[data-hx-base]') || node.querySelector?.('[data-hx-base]')) {
                    processHxBase(node);
                }
            }
        }
    });
    observer.observe(document.body, { childList: true, subtree: true });

    // (3) Inside `.htmxo-embed`, rewrite root-absolute hrefs and hx-*
    // URLs to go through the proxy prefix on every swap. The fragment
    // server (the embedded HTMXObjects app) emits root-absolute paths
    // that are relative to its own origin; without rewriting they
    // resolve against VitePress's origin and 404.
    const URL_ATTRS = ['href', 'hx-get', 'hx-post', 'hx-put', 'hx-patch', 'hx-delete'];
    const rewriteRootRefs = (root: HTMLElement, prefix: string) => {
        const fix = (el: Element, attr: string) => {
            const v = el.getAttribute(attr);
            if (v && v.startsWith('/') && !v.startsWith('//') && !v.startsWith(prefix)) {
                el.setAttribute(attr, prefix + v);
            }
        };
        for (const attr of URL_ATTRS) {
            root.querySelectorAll(`[${attr}]`).forEach((el) => fix(el, attr));
        }
    };
    document.body.addEventListener('htmx:afterSwap', (e: any) => {
        const tgt = e?.detail?.target as HTMLElement | undefined;
        if (!tgt) return;
        const embed = tgt.closest('.htmxo-embed');
        if (!embed) return;
        rewriteRootRefs(embed as HTMLElement, resolveProxyPrefix());
    });
}
