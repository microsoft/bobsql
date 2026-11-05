# Web feature options

[FeatureFlags.cs](FeatureFlags.cs) binds the application's feature switches.
`AiAssistance` covers the AI assistance card and Research page; `AiAgent`
controls the in-app assistant. Both default off.

Follow [first-app](../../../README.md), then the owning AI area, before
enabling a feature. Flags expose already-deployed capabilities; they do not
deploy SQL objects, models, or DAB services. Check both flag states after
changes and keep secrets out of configuration committed to source.
