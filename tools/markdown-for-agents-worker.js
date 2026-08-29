/**
 * Markdown for Agents (free-tier alternative)
 *
 * Serves the pre-generated raw Markdown variant of a post or the homepage
 * (built by _plugins/markdown-variant-hook.rb at /posts/<slug>/index.md
 * and /index.md) when a client sends `Accept: text/markdown`. Falls back
 * to normal HTML for everyone else. Deploy as a Cloudflare Worker route
 * on your zone, e.g. www.markmew.com/* (or www.markmew.com/posts/* plus
 * www.markmew.com/ if you only want partial coverage).
 *
 * This does not require the paid "Markdown for Agents" zone feature.
 */
export default {
  async fetch(request) {
    const url = new URL(request.url);
    const accept = request.headers.get("Accept") || "";
    const wantsMarkdown = accept.includes("text/markdown");
    const isHomepage = url.pathname === "/";
    const isPost = url.pathname.startsWith("/posts/");

    if (!wantsMarkdown || !(isHomepage || isPost)) {
      return fetch(request);
    }

    const mdPath = isHomepage
      ? "/index.md"
      : url.pathname.endsWith("/")
        ? `${url.pathname}index.md`
        : `${url.pathname}/index.md`;
    const mdUrl = new URL(mdPath, url.origin);

    const mdResponse = await fetch(mdUrl, { cf: { cacheTtl: 300 } });
    if (!mdResponse.ok) {
      return fetch(request);
    }

    const body = await mdResponse.text();
    const headers = new Headers(mdResponse.headers);
    headers.set("Content-Type", "text/markdown; charset=utf-8");
    headers.set("Vary", "Accept");
    headers.set("x-markdown-tokens", String(Math.ceil(body.length / 4)));

    return new Response(body, { status: 200, headers });
  },
};
