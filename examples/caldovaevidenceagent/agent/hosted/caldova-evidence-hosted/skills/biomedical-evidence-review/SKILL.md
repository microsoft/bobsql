---
name: biomedical-evidence-review-v2
description: Use for broad, comparative, or follow-up biomedical evidence questions that require focused parallel retrieval, cross-source synthesis, limitations, concise citations, and a next research question.
---

# Biomedical Evidence Review

## Investigation workflow

1. Interpret the research goal and decompose it into exactly three distinct, focused queries: primary mechanism, comparison or translation, and limitations or uncertainty.
2. Call the SQL MCP tool `search_evidence` exactly three times, once for each focused query, with `top_k` set to 3. Issue the calls together when parallel tool calling is available.
3. Select the three most relevant distinct articles across the MCP results. Do not summarize every returned passage. Use `get_article_context` only when the returned neighboring passages are insufficient to interpret a selected result.
4. Compare mechanisms, corroboration, disagreement, study limitations, and uncertainty. This cross-source judgment is the value beyond ranked evidence search.
5. Calibrate confidence to the exact claim. When multiple sources converge on mechanistic plausibility, state `High for mechanistic plausibility` even if human clinical causality or effect size remains limited. Do not collapse those separate judgments into `Mixed`.
6. Cite a source once per compact claim group using its plain PMCID, such as `PMC10142784`. Do not emit Markdown links or raw URLs; the application renders PMCIDs as links.
7. State clearly when the corpus is insufficient. Never invent articles, PMCIDs, quotations, findings, or citations.
8. Keep the initial briefing between 110 and 150 words. Avoid repeating a finding in multiple sections.
9. End with one short suggested follow-up question.

## Conversation continuity

For follow-up questions, retain the earlier investigation and answer from it when sufficient. If new evidence is needed, call `search_evidence` only for the evidence gap and use `get_article_context` only when necessary. Every follow-up must use the same visual response structure below; never return a prose-only paragraph. Keep follow-ups concise and no longer than the initial briefing.

For a strongest-causal-evidence follow-up, use exactly these evidence-signal labels:

- `**Strongest**`: name the leading source and its direct causal intervention or manipulation
- `**Comparison**`: explain why the other evidence is less causal
- `**Limitation**`: state the leading source's most important translational caveat

## Response structure

- `## Bottom line`: one sentence, 30 words maximum
- `## Evidence signals`: exactly three bullets; begin each with a bold 1-3 word label and keep each bullet under 22 words
- `## Confidence`: one sentence, 25 words maximum; lead with `High for mechanistic plausibility` when supported, then separately qualify human clinical causality or effect size
- `## Suggested follow-up`: one short question, 20 words maximum
- Sources: exactly three plain PMCIDs
