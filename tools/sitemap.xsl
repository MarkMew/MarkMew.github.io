<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:sitemap="http://www.sitemaps.org/schemas/sitemap/0.9">

  <xsl:output method="html" version="1.0" encoding="UTF-8" indent="yes"/>

  <xsl:template match="/">
    <html lang="en">
      <head>
        <meta charset="UTF-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1"/>
        <title>XML Sitemap</title>
        <style>
          :root {
            --bg: #f7f4ef;
            --panel: #fffdf8;
            --ink: #1e2a2f;
            --muted: #5f6b70;
            --line: #d8d2c6;
            --soft: #ece6db;
          }

          * {
            box-sizing: border-box;
          }

          body {
            margin: 0;
            font-family: "Segoe UI", "Noto Sans", sans-serif;
            background:
              radial-gradient(circle at 20% -10%, #d7efe9 0%, transparent 35%),
              radial-gradient(circle at 85% 10%, #f5dfcc 0%, transparent 32%),
              var(--bg);
            color: var(--ink);
          }

          .wrap {
            width: min(1120px, 92vw);
            margin: 40px auto;
          }

          .hero {
            background: linear-gradient(135deg, #0f766e, #14532d);
            color: #ffffff;
            border-radius: 16px;
            padding: 28px;
            box-shadow: 0 12px 30px rgba(0, 0, 0, 0.15);
          }

          .hero h1 {
            margin: 0;
            font-size: clamp(1.4rem, 2.2vw, 2.1rem);
            letter-spacing: 0.02em;
          }

          .hero p {
            margin: 10px 0 0;
            opacity: 0.95;
            line-height: 1.6;
          }

          .stats {
            margin-top: 14px;
            display: flex;
            gap: 16px;
            flex-wrap: wrap;
            font-size: 0.95rem;
          }

          .chip {
            background: rgba(255, 255, 255, 0.16);
            border: 1px solid rgba(255, 255, 255, 0.34);
            border-radius: 999px;
            padding: 6px 12px;
          }

          .panel {
            margin-top: 18px;
            background: var(--panel);
            border: 1px solid var(--line);
            border-radius: 16px;
            overflow: hidden;
            box-shadow: 0 8px 20px rgba(20, 25, 35, 0.07);
          }

          table {
            width: 100%;
            border-collapse: collapse;
          }

          thead th {
            text-align: left;
            padding: 14px 16px;
            background: var(--soft);
            color: #2d3b40;
            font-weight: 700;
            letter-spacing: 0.02em;
            font-size: 0.9rem;
          }

          tbody td {
            padding: 13px 16px;
            border-top: 1px solid var(--line);
            vertical-align: top;
            line-height: 1.45;
            font-size: 0.95rem;
          }

          tbody tr:nth-child(even) {
            background: #fffaf2;
          }

          a {
            color: #0b5e58;
            text-decoration: none;
            word-break: break-word;
          }

          a:hover {
            text-decoration: underline;
          }

          .muted {
            color: var(--muted);
          }

          @media (max-width: 780px) {
            .wrap {
              width: 95vw;
              margin: 22px auto;
            }

            .hero {
              padding: 20px;
              border-radius: 14px;
            }

            thead th:nth-child(3),
            thead th:nth-child(4),
            tbody td:nth-child(3),
            tbody td:nth-child(4) {
              display: none;
            }
          }
        </style>
      </head>
      <body>
        <div class="wrap">
          <section class="hero">
            <h1>XML Sitemap</h1>
            <p>This document helps search engines discover important pages on this site.</p>
            <div class="stats">
              <span class="chip">
                URL Count: <xsl:value-of select="count(sitemap:urlset/sitemap:url)"/>
              </span>
              <span class="chip">
                Schema: sitemaps.org 0.9
              </span>
            </div>
          </section>

          <section class="panel">
            <table>
              <thead>
                <tr>
                  <th>URL</th>
                  <th>Last Modified</th>
                  <th>Change Frequency</th>
                  <th>Priority</th>
                </tr>
              </thead>
              <tbody>
                <xsl:for-each select="sitemap:urlset/sitemap:url">
                  <tr>
                    <td>
                      <a href="{sitemap:loc}">
                        <xsl:value-of select="sitemap:loc"/>
                      </a>
                    </td>
                    <td class="muted">
                      <xsl:choose>
                        <xsl:when test="sitemap:lastmod">
                          <xsl:value-of select="sitemap:lastmod"/>
                        </xsl:when>
                        <xsl:otherwise>-</xsl:otherwise>
                      </xsl:choose>
                    </td>
                    <td class="muted">
                      <xsl:choose>
                        <xsl:when test="sitemap:changefreq">
                          <xsl:value-of select="sitemap:changefreq"/>
                        </xsl:when>
                        <xsl:otherwise>-</xsl:otherwise>
                      </xsl:choose>
                    </td>
                    <td class="muted">
                      <xsl:choose>
                        <xsl:when test="sitemap:priority">
                          <xsl:value-of select="sitemap:priority"/>
                        </xsl:when>
                        <xsl:otherwise>-</xsl:otherwise>
                      </xsl:choose>
                    </td>
                  </tr>
                </xsl:for-each>
              </tbody>
            </table>
          </section>
        </div>
      </body>
    </html>
  </xsl:template>
</xsl:stylesheet>
