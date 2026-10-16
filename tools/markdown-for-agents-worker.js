/**
 * Markdown for Agents (free-tier alternative)
 *
 * Serves pre-generated Markdown variants of posts and language homepages
 * when a client requests `Accept: text/markdown`. Other requests reach
 * the normal HTML origin.
 *
 * This does not require the paid "Markdown for Agents" zone feature.
 */
export default {
  async fetch(request) {
    const url = new URL(request.url);
    const accept = request.headers.get("Accept") || "";
    const wantsMarkdown = accept.split(",").some((entry) => {
      const [type, ...parameters] = entry.split(";");
      if (type.trim().toLowerCase() !== "text/markdown") return false;
      const quality = parameters.find((parameter) => /^\s*q\s*=/i.test(parameter));
      return !quality || Number(quality.split("=")[1]) > 0;
    });
    const isHomepage = /^\/(?:en|ja)?\/?$/.test(url.pathname);
    const isPost = /^\/(?:en\/|ja\/)?posts\/[^/]+\/?$/.test(url.pathname);

    if (!wantsMarkdown || !(isHomepage || isPost) || !["GET", "HEAD"].includes(request.method)) {
      return fetch(request);
    }

    const mdPath = isHomepage
      ? `${url.pathname.endsWith("/") ? url.pathname : `${url.pathname}/`}index.md`
      : url.pathname.endsWith("/")
        ? `${url.pathname}index.md`
        : `${url.pathname}/index.md`;
    const mdUrl = new URL(mdPath, url.origin);

    const mdResponse = await fetch(new Request(mdUrl, { method: "GET" }), { cf: { cacheTtl: 300 } });
    if (!mdResponse.ok) {
      return fetch(request);
    }

    const body = await mdResponse.text();
    const headers = new Headers(mdResponse.headers);
    headers.set("Content-Type", "text/markdown; charset=utf-8");
    const vary = headers.get("Vary");
    if (!vary?.split(",").some((value) => value.trim().toLowerCase() === "accept")) {
      headers.set("Vary", vary ? `${vary}, Accept` : "Accept");
    }
    for (const name of ["Content-Length", "Content-Encoding", "Content-Range", "ETag", "Last-Modified"]) {
      headers.delete(name);
    }
    return new Response(request.method === "HEAD" ? null : body, { status: 200, headers });
  },
};
