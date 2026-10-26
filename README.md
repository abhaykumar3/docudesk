# DocuDesk for Mac

Offline-first macOS app for creating, organising, exporting and backing up business documents.
Built from [`docs/prd.md`](docs/prd.md). Phase 1 MVP.

## Build & run

Requires macOS 14+ and Swift 6 (Xcode or Command Line Tools).

```bash
scripts/build-app.sh          # release build → build/DocuDesk.app
open build/DocuDesk.app
swift run DocuDeskChecks      # calculation, storage, PDF and backup checks
swift run DocuDeskDemo ~/DocuDesk-Demo   # optional: a workspace full of sample data
```

The app icon (`scripts/AppIcon.icns`) is generated from the vector logo in
`Sources/DocuDeskCore/Engine/BrandMark.swift`; after changing the logo run
`swift run BrandAssets icon scripts/AppIcon.icns`.

Keep the project and the workspace folder **outside iCloud Drive** (Desktop/Documents sync can
corrupt the SQLite database and build folders). First-run setup warns about synced folders.

## What's in it

| Area | Where |
|---|---|
| Money maths (Decimal only, GST CGST/SGST/IGST, inclusive/exclusive, discounts, round-off, payments, amount in words) | `Sources/DocuDeskCore/Engine/DocumentCalculator.swift` |
| 12 document types × 5 styles = 60 built-in templates; custom versioned templates | `Engine/TemplateLibrary.swift`, `Storage/WorkspaceStore+Library.swift` |
| Starter content for proposals, agreements, letters, reports; clause library | `Engine/Starters.swift`, `Engine/ClauseLibrary.swift` |
| Rich text (RTFD storage, merge fields like `{{client.name}}`, page breaks, restyling) | `Rendering/RichText.swift` |
| PDF renderer (Core Graphics + TextKit, pagination, repeating table headers, Page X of Y) | `Rendering/DocumentRenderer.swift` |
| Word export (hand-written Office Open XML: text, tables, images, footer page numbers) | `Rendering/DocxExporter.swift` |
| Workspace folders, JSON records, SQLite + FTS5 index, numbering, issue/revise/duplicate/convert | `Storage/WorkspaceStore.swift` |
| Payments, tags, archive, pins, bulk export, saved filters, duplicate detection | `Storage/WorkspaceStore+Operations.swift` |
| Verified backups (SHA-256 manifest) and safe restore | `Storage/BackupService.swift` |
| SwiftUI app: dashboard, editor with live preview and word-processor body, documents, templates & designer, clauses, clients, catalog, reports, storage, settings & company profiles | `Sources/DocuDesk/` |

## Workspace layout

```
DocuDesk/
├── workspace.json                 marker + format version
├── Database/docudesk.sqlite       index, clients, products, settings
├── Documents/Invoices/2026/INV-2026-0001/
│   ├── document.json              canonical editable record
│   ├── INV-2026-0001.pdf          exported output
│   └── revisions/                 issued + superseded snapshots
├── Assets/  Backups/  Exports/  Templates/
```

## Integrity rules (from the PRD)

- "Saved" is shown only after the atomic file write and the index update both succeed.
- Issued documents are content-locked; corrections create a revision and keep the old copy.
- Documents keep company/customer snapshots, so editing a client never changes old invoices.
- A missing folder or database is reported; DocuDesk never silently creates an empty replacement.
- Drafts are deleted to the macOS Trash; issued documents can only be cancelled.
- Restores verify every checksum first and move current data aside instead of deleting it.

## Compatibility

Records written by Phase 1 open unchanged: new fields use `@Defaulted` / zero-default decoding, and
the database migrates from schema 1 to 2 on open (both covered by `DocuDeskChecks`).

## Phase 3 additions

| Area | Where |
|---|---|
| Custom document types (name, prefix, layout, labels, statuses, typed fields, `{{field.x}}`) | `Model/CustomDocumentType.swift`, `Storage/WorkspaceStore+CustomTypes.swift` |
| Version history: field/item/paragraph comparison and restore | `Engine/DocumentComparer.swift`, `Storage/WorkspaceStore+Revisions.swift` |
| Encrypted backups (PBKDF2-SHA256 → AES-256-GCM, chunked, tamper/truncation-proof; Keychain) | `Storage/BackupCrypto.swift` |
| Excel (.xlsx) list and report workbooks, PNG page export | `Rendering/XLSXWriter.swift`, `Storage/WorkspaceStore+Exports.swift` |
| CSV import (clients, products) and bulk generation (clients or CSV rows) | `Engine/CSV.swift`, `Storage/WorkspaceStore+Bulk.swift` |
| Template designer: density, logo size, columns, item heading, watermark, section order, UPI QR | `Engine/TemplateLibrary.swift`, `Rendering/DocumentRenderer.swift` |
| On-device AI drafting/rewriting (Apple Intelligence, macOS 26; hidden when unavailable) | `Sources/DocuDesk/Editor/AIAssistant.swift` |

## Known limits

- The template designer is section-based, not a free-form drag-and-drop canvas.
- Tables of contents list headings without page numbers; headings can be orphaned at a page end.
- Word export doesn't apply watermarks, section order or the UPI QR code.
- AI drafting needs Apple Intelligence; drafts are text for review, not legal or tax advice.
- Not yet signed with a Developer ID or notarised; no custom app icon.
