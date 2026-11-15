# Browser assets

Static, dependency-free frontend served by ASP.NET Core:

| File | Purpose |
| --- | --- |
| [index.html](index.html) | Transfer-center page and controls |
| [app.css](app.css) | Layout, cards, citations, and audit overlay styling |
| [app.js](app.js) | Same-origin API calls, transfer selection, history preview, briefing options, and audit rendering |

There is no npm build or separate frontend server. Run the
[ASP.NET Core app](../README.md) and open `http://localhost:5099`.

The browser displays live database-backed records, not bundled patient data.
History preview and optional history-grounded generation are independent
actions. The UI displays persisted source snapshots and reports API failures;
it must not silently substitute synthetic successful results.

Never put model credentials or direct model calls here: static assets are
downloadable by every client. Keep inference and validation in SQL and
coordinate changes with [models](../Models/README.md) and
[data access](../Data/README.md).
