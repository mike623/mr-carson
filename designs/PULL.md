# Designs — pulled from Claude Design via MCP

This folder mirrors the **mr carson** Claude Design project root. Treat it as a
checkout: do not hand-edit; re-pull to refresh.

- **Project:** `mr carson`
- **Project ID:** `d805b08f-5ff3-4092-904e-1599653b406a`
- **URL:** https://claude.ai/design/p/d805b08f-5ff3-4092-904e-1599653b406a?file=Mr+Carson.dc.html

## Files

| File | Role |
|------|------|
| `Mr Carson.dc.html` | The app design — every screen + the prototype state script. Source of truth for implementation. |
| `Mr Carson Icon Set.dc.html` | The 10-glyph iconography spec (Service Bell, Camera, Ledger, Cloche, Basket, Carriage Wheel, Estate Key, Sundry Tag, Padlock, Quill). |
| `support.js` | dc-runtime — renders `.dc.html` in a browser. Generated; do not edit. |
| `ios-frame.jsx` | iOS device frame component imported by `Mr Carson.dc.html`. |
| `screens/*.png`, `.thumbnail` | Editor-generated preview captures. |

## How to re-pull (same way every time)

Use the `DesignSync` MCP tool (needs design scopes; run `/design-login` if prompted):

1. `list_files` with `projectId` above → see remote paths.
2. `get_file` per path → write into this folder, mirroring the remote root.

Future design changes land in the remote project; re-running the two steps
brings this folder current.
