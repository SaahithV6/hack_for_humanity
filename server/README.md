# Moth enrichment proxy

Optional. The app is fully functional without it.

This service exists for one reason: **an iOS app cannot hold an API key.**
Anyone can pull it out of the bundle. So the key lives here instead.

## What it does

One endpoint, `POST /v1/enrich`, which asks Claude to write the bedtime
summary. That is the only thing a cloud model is used for in Moth — see the
reasoning in the root README.

## What it deliberately does not do

- **It does not log request bodies.** Errors log the exception name only.
- **It does not decide anything.** Counts, minutes, streaks and highlights are
  all computed on the phone. The model writes prose.
- **It is not trusted.** Every response is re-validated by the harness on the
  device, after this server, before it reaches a user. If this service were
  compromised tomorrow it could not put a fabricated number or an invented
  accomplishment in front of anybody.
- **It rejects anything off-schema.** The request shape is `.strict()`; unknown
  fields are an error, not something to ignore.

## Deploy to Render

The included `render.yaml` is a blueprint. Point Render at this repo, then set
`ANTHROPIC_API_KEY` in the dashboard (it is marked `sync: false`, so it is
never committed).

Then set `EnrichmentClient.defaultEndpoint` in `App/EnrichmentClient.swift` to
the service URL.

## Local

```bash
npm install
npm run typecheck
ANTHROPIC_API_KEY=sk-... npm run build && npm start
```
