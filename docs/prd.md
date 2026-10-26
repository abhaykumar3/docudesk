# DocuDesk for Mac — Product Requirements Document

**Document status:** Product specification  
**Version:** 1.0  
**Platform:** macOS  
**Product type:** Offline-first desktop document creation and management software  
**Working name:** DocuDesk for Mac

---

## 1. Product Overview

### 1.1 Vision

DocuDesk for Mac is an offline-first macOS application that enables users to create, customize, organize, export, and retrieve business and personal documents from one local workspace.

The product combines a document generator, a reusable template library, a local records manager, and a lightweight business-document workflow. Core functionality must work without an internet connection or a user account.

### 1.2 Problem Statement

Freelancers, agencies, consultants, and small businesses often rely on several disconnected tools to create invoices, quotations, agreements, reports, and letters. Their documents become scattered across folders, templates are inconsistent, and locating historical records can be time-consuming.

DocuDesk addresses these problems with:
- Built-in templates for common document types.
- Reusable company, customer, and product/service records.
- Structured document creation with live previews.
- Reliable PDF export and printing.
- Searchable local records and visible file storage.
- Local backup and restore workflows.

### 1.3 Product Goals

1. Enable users to create professional documents quickly.
2. Provide built-in templates for common business and personal use cases.
3. Save document records and exported files to user-accessible local folders.
4. Operate without internet access for all core workflows.
5. Support accurate calculations and reusable structured data.
6. Make documents easy to search, archive, export, back up, and restore.
7. Keep the architecture extensible so new document types and templates can be added without redesigning the whole application.

### 1.4 Non-Goals for the Initial Release

- Mandatory cloud storage or account registration.
- Multi-user collaboration.
- Automatic email delivery.
- Online payment collection.
- E-signature integrations.
- Automatic GST filing or e-invoice submission.
- Bank account integration.
- AI-generated legal advice.
- Windows or Linux support.
- An online template marketplace.

---

## 2. Target Users

| User group | Primary needs |
|---|---|
| Freelancers | Invoices, estimates, receipts, proposals |
| Agencies | Quotations, proposals, scopes of work, service agreements |
| Small businesses | Invoices, purchase orders, delivery notes, payment records |
| Consultants | Proposals, reports, engagement letters |
| Accountants | Consistent document generation and organized records |
| Individuals | Letters, applications, declarations, personal forms |

### 2.1 Primary User Stories

- As a freelancer, I want to create an invoice from a template so that I can bill a client quickly.
- As a business owner, I want company and customer information to be reusable so that I do not re-enter it for every document.
- As a user, I want documents saved in ordinary folders so that I can find them through Finder.
- As a user, I want the app to work offline so that my work is not dependent on a service being available.
- As a user, I want to search by document number, customer, date, or type so that I can find old records quickly.
- As a user, I want to export a professional PDF so that I can print or share it.
- As a user, I want to back up and restore my records so that a computer or drive failure does not permanently destroy my work.
- As a user, I want to create custom templates so that my documents reflect my brand and workflow.

---

## 3. Product Principles

1. **Offline-first:** Core features must work without a network connection.
2. **Local ownership:** Users control the data directory and can inspect files in Finder.
3. **Template-first:** Users choose a document type and template rather than starting from a blank page.
4. **Professional output:** PDF documents must render and print consistently.
5. **Reusable data:** Company, customer, product, and service information should be reusable.
6. **Historical integrity:** Issued documents must preserve the relevant information as it existed when issued.
7. **Transparent persistence:** The application must communicate save status and storage failures clearly.
8. **Extensible design:** Document types, fields, templates, and exporters should be modular.

---

## 4. Document Types

The application should use a modular document engine. Each document type defines its fields, validation rules, calculations, lifecycle states, and supported export formats.

### 4.1 Invoices and Billing

- Standard invoice
- Tax invoice
- GST invoice for Indian businesses
- Pro forma invoice
- Advance payment invoice
- Final invoice
- Recurring invoice template
- Credit note
- Debit note
- Payment receipt
- Outstanding statement

### 4.2 Sales and Proposals

- Quotation
- Estimate
- Business proposal
- Project cost estimate
- Scope of work (SOW)
- Statement of services
- Pricing sheet and rate card
- Service package comparison
- Sales order
- Order confirmation

### 4.3 Procurement and Operations

- Purchase order
- Purchase requisition
- Delivery challan
- Goods receipt note
- Work order
- Job sheet
- Inventory issue note
- Vendor comparison sheet

### 4.4 Agreements and HR

- Service agreement
- Website development agreement
- Maintenance and support agreement
- Non-disclosure agreement
- Freelancer contract
- Employment offer letter
- Appointment letter
- Experience letter
- Relieving letter
- Joining form
- Authorization letter

### 4.5 General Business Documents

- Letterhead and official letters
- Payment reminders
- Meeting minutes
- Project reports
- Completion certificates
- Work completion reports
- Business expense reports
- Handover documents
- Checklists
- Declaration forms

### 4.6 Scope Strategy

The initial release must prioritize a high-quality core library. New document types should be addable through schemas and renderers instead of requiring entirely separate application screens.

---

## 5. Information Architecture and Navigation

The application should use a native-feeling macOS layout with a sidebar, toolbar, searchable lists, keyboard shortcuts, and familiar save/export behavior.

### 5.1 Primary Navigation

- Dashboard
- Create Document
- All Documents
- Templates
- Customers
- Products & Services
- Local Folders
- Settings

### 5.2 Dashboard

Display:
- Total document count.
- Draft documents requiring completion.
- Recently created or edited documents.
- Recently exported PDFs.
- Invoice totals and outstanding amounts when invoice tracking is enabled.
- Quick actions for invoice, quotation, agreement, and general document creation.
- Current local-storage status.
- Backup warnings and inaccessible-storage warnings.

Financial figures must be calculated from local records and clearly distinguish draft, issued, paid, overdue, and cancelled documents.

---

## 6. Functional Requirements

### 6.1 Template Library

**Priority:** P0 for core templates; P1 for advanced customization.

Requirements:
- Include built-in templates organized by category.
- Provide multiple visual styles for popular document types.
- Show a preview before creation.
- Support A4, A5, Letter, and other appropriate paper sizes.
- Support portrait and landscape orientation.
- Support logos, colors, typography, headers, footers, and page numbering.
- Support multi-page documents and repeating table headers.
- Allow templates to be favorited, duplicated, and customized.
- Allow custom template import/export where practical.
- Tag templates by document type, industry, and style.
- Version template definitions and preserve the template version used by existing documents.

Suggested styles:
- Minimal
- Corporate
- Modern
- Classic
- Professional
- Elegant

#### Template Editor

Users should be able to configure:
- Logo placement and dimensions.
- Font family, size, weight, and color.
- Margins, spacing, and alignment.
- Table columns and widths.
- Header and footer content.
- Optional fields and sections.
- Accent colors and borders.
- Terms and conditions.
- Signature and stamp areas.
- Page numbering and repeating elements.

The MVP should use a controlled section-based editor rather than promise a full graphic-design canvas.

### 6.2 Universal Document Creation Workflow

1. Choose a document type.
2. Select and preview a template.
3. Enter document details.
4. Review the live preview.
5. Save the editable record locally.
6. Export or print.

All document types should share the same general workflow while using specialized schemas and validation rules.

### 6.3 Invoice and Quotation Builder

Required fields and capabilities:
- Seller and buyer information.
- Document number, issue date, and due date.
- Payment terms.
- Line items, descriptions, quantities, units, and unit prices.
- Per-line and document-level discounts.
- Configurable taxes.
- Tax-inclusive and tax-exclusive pricing.
- Shipping, additional charges, deposits, and adjustments.
- Subtotal, tax totals, grand total, and amount in words.
- Notes, terms, bank/payment details, logo, signature, and authorized signatory.
- Multiple currencies and configurable currency formatting.
- Duplicate, revise, and convert quotation to invoice.
- Payment statuses: paid, partially paid, unpaid, overdue, and cancelled.

#### Calculation Example

For two items at ₹10,000 each:
- Subtotal: ₹20,000
- Discount: ₹2,000
- Taxable value: ₹18,000
- GST at 18%: ₹3,240
- Total: ₹21,240

All calculations must be deterministic application logic, never AI-generated arithmetic. Tax rules must be configurable; the app must not assume every Indian transaction uses the same rate or tax split. The app should not represent itself as an official tax-filing or compliance service.

### 6.4 Document Lifecycle and Version History

Suggested states:
- Draft
- Issued
- Sent
- Accepted
- Partially Paid
- Paid
- Overdue
- Cancelled

States should vary by document type. For example, an NDA does not need payment states.

Requirements:
- Duplicate as a new document.
- Create revised versions.
- Maintain revision numbers and timestamps.
- Preserve issued-document snapshots.
- Keep an audit history of important edits.
- Restore earlier editable revisions.
- Link related records, such as quotation → invoice → receipt.
- Avoid silently rewriting historical invoices; corrections should use a revision or appropriate adjustment document.

### 6.5 Customer Database

Customer fields:
- Unique ID.
- Individual or company name.
- Billing and shipping addresses.
- Email and telephone.
- Contact person.
- Optional GSTIN and other business identifiers.
- Default currency and payment terms.
- Notes.
- Linked documents.
- Active or archived status.

Users must be able to create documents without first registering a customer. The app may offer to save newly entered customer information as a reusable record.

### 6.6 Products and Services Database

Fields:
- Unique ID.
- Name and description.
- SKU or service code.
- Unit of measurement.
- Default price and currency.
- Optional tax category and rate.
- Optional discount.
- Active or archived status.

Users must be able to add one-off line items without creating a permanent catalog entry.

### 6.7 General Document Editor

Requirements:
- Headings, paragraphs, lists, tables, and text formatting.
- Images and logos.
- Page breaks and page-layout controls.
- Headers, footers, and page numbers.
- Reusable text snippets and clauses.
- Signature blocks and document metadata.
- Table of contents for long documents where applicable.
- Spell-check integration where supported by macOS.
- Search and replace.
- Auto-save and recovery after unexpected termination.

Editing a document created from a template must not modify the master template.

### 6.8 PDF and File Export

**PDF export is mandatory for version 1.**

PDF requirements:
- Correct fonts, logos, line wrapping, and page breaks.
- A4 and Letter support.
- Multi-page table pagination and repeating headers where appropriate.
- Print preview and native macOS print dialog.
- PDF metadata such as title and author.
- Deterministic file naming.
- User-selectable export destination.
- Optional password protection only if implemented securely.

Format priorities:

| Format | Priority | Purpose |
|---|---|---|
| PDF | P0 | Final documents and printing |
| DOCX | P1 | Editable letters, reports, and agreements |
| CSV | P1 | Export record lists |
| JSON | P1 | Portable structured backup |
| XLSX | P2 | Spreadsheet-style reports |
| PNG | P2 | Document preview or image export |

Do not claim perfect conversion of every template to every format. DOCX/XLSX support should be validated by document category, with PDF as the reliable final-output format.

### 6.9 Search and Organization

Search across:
- Document number and title.
- Customer or company name.
- Document type and status.
- Dates and amounts.
- Item descriptions and tags.
- Supported document text.

Filters:
- Date range.
- Type.
- Status.
- Customer.
- Amount range.
- Tags.

Additional features:
- Favorites and pinned documents.
- Custom collections.
- Recently opened documents.
- Recently exported files.
- Tags such as Client, Internal, Urgent, and Tax.
- Saved filters.
- Duplicate detection.
- Configurable archival rules.

### 6.10 Bulk Operations

Users should be able to:
- Select multiple records.
- Export selected documents.
- Export filtered lists to CSV.
- Archive records.
- Add or remove tags.
- Back up selected records.
- Delete drafts or duplicates with confirmation.

Issued records must have stronger deletion safeguards than drafts. Deletion must not silently break references from historical documents.

### 6.11 Settings

Settings sections:
- Company profiles.
- Document defaults.
- Numbering rules.
- Currency and formatting.
- Taxes.
- Templates and branding.
- Storage directory.
- Backup and restore.
- Privacy and optional local encryption.
- Appearance.
- Accessibility.

Support multiple company profiles. Each profile must have its own numbering configuration and document defaults.

---

## 7. Offline Storage and File Management

### 7.1 Default Directory

Default location:

`~/Documents/DocuDesk/`

Users may select another local directory or an external drive. Network and cloud-synced folders are optional, not required.

### 7.2 Recommended Folder Structure

```text
DocuDesk/
├── Database/
│   └── docudesk.sqlite
├── Documents/
│   ├── Invoices/
│   │   └── 2026/
│   │       └── INV-2026-0001/
│   │           ├── document.json
│   │           ├── invoice.pdf
│   │           ├── attachments/
│   │           └── revisions/
│   ├── Quotations/
│   ├── Agreements/
│   └── Reports/
├── Templates/
├── Assets/
├── Backups/
└── Exports/
```

The final implementation must define one canonical location for each record and artifact. Avoid uncontrolled duplicate copies or conflicting sources of truth.

### 7.3 Document Record

A JSON document record may include:
- Stable document ID.
- Document number and type.
- Schema and document version.
- Company and customer snapshots.
- Dates and status.
- Currency and line items.
- Calculation results.
- Template ID and template version.
- Relative paths to attachments and exports.
- Revision metadata.
- Created and modified timestamps.

The exported PDF is an output artifact, not the only source of truth. Editable document data must remain available independently.

### 7.4 Storage Architecture

Use a hybrid local-storage model:
- SQLite for search indexes, customer/product records, statuses, relationships, and settings.
- JSON records for portable editable document data.
- PDF and other exported files for user-facing documents.
- Asset files for logos, signatures, and attachments.

The database should be rebuildable from validated document records where practical. Rebuild procedures must preserve IDs, document numbering, relationships, and version history.

### 7.5 Save Behavior

Requirements:
- Auto-save drafts after a short idle period.
- Display Saving, Saved, and Save Failed states.
- Use atomic writes where possible.
- Never indicate that a document is saved before the write succeeds.
- Recover drafts after unexpected termination.
- Detect inaccessible or moved storage directories.
- Prevent accidental overwriting of unrelated files.
- Keep backups separate from live records.
- Clearly explain storage errors.

If a selected external drive is unavailable, the app must not silently switch to an empty database. It should clearly report the issue and offer safe recovery choices.

### 7.6 Backup and Restore

Requirements:
- Create backup now.
- Configurable automatic local backup.
- Restore from a backup package.
- Export all records to a portable archive.
- Verify backup integrity before restore.
- Configurable retention of previous backups.
- Warn when a backup destination is unavailable or the last successful backup is old.
- Support an external drive as a backup destination.
- Validate backup compatibility with the app version.

Optional encrypted backups may be supported using well-reviewed encryption and secure password handling. Warn users that losing the password may make a backup unrecoverable.

---

## 8. Security and Privacy

Requirements:
- No mandatory sign-in.
- No mandatory cloud storage.
- No transmission of document contents for analytics or telemetry.
- No automatic document uploads.
- Store data in user-controlled directories.
- Use appropriate macOS file permissions.
- Use macOS Keychain for secrets when needed.
- Confirm permanent deletion.
- Validate imported JSON and template files.
- Protect against malformed files, unsafe paths, and unintended overwrites.
- Avoid unnecessary personal or financial information in diagnostic logs.
- Sign and notarize macOS distribution builds where applicable.
- Ensure optional online update checks do not interfere with core offline functionality.

---

## 9. Technical Architecture

### 9.1 Recommended Stack

| Component | Technology | Purpose |
|---|---|---|
| Desktop UI | SwiftUI | Native macOS interface |
| Language | Swift | Application logic and platform integration |
| Database | SQLite; optionally SwiftData for simpler entities | Durable local records |
| File persistence | FileManager and Codable | Local folders and JSON |
| PDF generation | Core Graphics / PDFKit | PDF creation and printing |
| PDF preview | PDFKit | Page-by-page preview |
| General editor | SwiftUI with AppKit integration as needed | Rich-text editing |
| DOCX export | Dedicated document-generation library | Editable Word documents |
| Search | SQLite indexes and optionally FTS5 | Fast local search |
| Secret storage | macOS Keychain | Secure storage of secrets |
| Distribution | Signed and notarized DMG or app package | macOS installation |

**Alternative:** Tauri 2 with React/TypeScript and a Rust backend is suitable if cross-platform support and reuse of web-development skills are important. For a Mac-first application with deep macOS integration, SwiftUI is preferred.

### 9.2 Architecture Layers

1. **Presentation:** Navigation, forms, document editor, template gallery, previews.
2. **Application services:** Document operations, template engine, calculations, search, versioning, backup.
3. **Persistence:** SQLite records, JSON document files, assets, exports, backups.
4. **Rendering and export:** PDF, print, and supported editable-format exporters.

### 9.3 Architecture Rules

- UI screens must use centralized document and storage services rather than manipulating arbitrary files independently.
- The document model must remain independent of its rendered PDF.
- Template definitions must be versioned.
- Calculation logic must be isolated and thoroughly tested.
- File writes and database updates must have explicit failure and recovery handling.
- All business-critical workflows must work without a network connection.
- Storage operations must prevent path traversal and unsafe overwrites.
- Database migrations must be tested against supported previous versions.

---

## 10. Data Model

| Entity | Key fields |
|---|---|
| `CompanyProfile` | ID, name, address, logo, tax identifiers, defaults |
| `Customer` | ID, name, contact details, address, tax ID |
| `ProductService` | ID, name, SKU, unit, price, tax configuration |
| `Document` | ID, number, type, title, status, dates, currency, profile ID |
| `DocumentLineItem` | ID, document ID, description, quantity, unit price, discount, tax |
| `DocumentTemplate` | ID, name, type, version, layout definition |
| `DocumentRevision` | ID, document ID, revision number, snapshot, timestamp |
| `PaymentRecord` | ID, invoice ID, amount, date, method, reference |
| `Attachment` | ID, document ID, relative path, media type |
| `DocumentRelationship` | Source ID, target ID, relationship type |
| `BackupRecord` | ID, destination, timestamp, verification status |
| `AppSettings` | Storage path, preferences, numbering configuration |

### Data Integrity Rules

- Every record must have a stable unique ID, preferably a UUID.
- Document numbers must be unique within their configured numbering scope.
- Store monetary values using fixed-precision decimals or integer minor units where appropriate, not binary floating-point values.
- Store timestamps consistently and display dates using the user's chosen locale.
- Issued documents must preserve company and customer snapshots.
- Keep a reference to the template version used by each document.
- Use schema migrations for database upgrades.
- Define relationship and deletion rules so historical records are not accidentally orphaned.

---

## 11. User Experience and Design

### 11.1 Visual Direction

- Native-feeling macOS interface.
- Clean, restrained, professional design.
- Sidebar navigation and a compact toolbar.
- System typography and familiar controls.
- Light and dark appearance support.
- Accessible contrast and readable text.
- Clear empty, loading, saving, error, and success states.

### 11.2 Editor Layout

Where screen size permits:
- **Left panel:** Document fields and line items.
- **Center panel:** Live page preview.
- **Right inspector:** Template styling, page settings, and export options.

On smaller windows, collapse the inspector and provide a preview toggle.

### 11.3 Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `⌘ N` | New document |
| `⌘ S` | Save document |
| `⌘ P` | Print |
| `⌘ F` | Search |
| `⌘ ⇧ E` | Export document |
| `⌘ Z` | Undo |
| `⌘ ⇧ Z` | Redo |

Final shortcuts must respect macOS conventions and avoid conflicts with standard text editing.

---

## 12. Non-Functional Requirements

These are targets to validate during development, not claims about an existing implementation.

| Area | Target |
|---|---|
| Offline operation | All core features work with networking disabled |
| Startup | Target under 3 seconds on a supported Mac with a warm launch |
| Search | Target under 300 ms for 10,000 indexed records |
| Draft saving | Target under 1 second for typical edits |
| PDF export | Target under 2 seconds for a typical 1–5 page document |
| Reliability | No silent loss of acknowledged saved data |
| Scale | At least 50,000 document records without architectural redesign |
| Accessibility | Keyboard navigation and VoiceOver for core workflows |
| Recovery | Detect incomplete writes and validate backups |
| Compatibility | Publish a defined range of supported macOS versions |
| Portability | Export core records and attachments in a documented format |

Targets must be validated on real hardware, including Apple Silicon Macs with limited memory.

---

## 13. MVP Scope and Roadmap

Estimates below are indicative and depend on developer experience, testing, design quality, and export requirements.

### Phase 1: Core MVP — Suggested 4–6 weeks

- Native macOS shell and navigation.
- Company profile and reusable customer records.
- Invoice, quotation, and receipt templates.
- At least 15 polished built-in templates.
- Line items, discounts, configurable tax calculations.
- PDF generation and printing.
- SQLite database and local folder storage.
- Document search, status filters, and numbering.
- Auto-save, recovery, and basic backup/restore.
- Offline operation and first-run setup.

### Phase 2: Business Document Suite — Indicative 3–5 additional weeks

- Agreements, proposals, reports, and purchase orders.
- General rich-text document editor.
- Template customization and reusable clauses.
- DOCX and CSV exports.
- Payment tracking and quotation-to-invoice conversion.
- Document revisions and linked records.
- Multiple company profiles.
- Advanced search and bulk export.

### Phase 3: Advanced Productivity — Indicative 3–6 additional weeks or more

- Advanced template designer.
- Custom document schemas.
- Spreadsheet and report exports.
- Encrypted backup packages.
- Bulk document generation.
- Document comparison and revision restoration.
- Optional AI-assisted drafting.
- Optional import/export integrations.

A solo developer working part-time or learning SwiftUI may require substantially longer, particularly for rich-text editing and DOCX fidelity.

---

## 14. Acceptance Criteria

The MVP is ready only when these tests pass:

1. **First launch:** The app creates or lets the user choose a local data directory without requiring an account.
2. **Offline mode:** Creating, editing, searching, saving, printing, and exporting work with Wi-Fi disabled.
3. **Invoice correctness:** Line-item calculations, discounts, tax, rounding, and grand totals match approved test cases.
4. **PDF fidelity:** The PDF preserves the selected template, page dimensions, text, and pagination.
5. **Persistence:** Saved documents remain available after quitting and relaunching.
6. **Folder visibility:** Users can locate document files through Finder.
7. **Search:** Search and filters return expected records without network access.
8. **Backup restore:** A verified backup restores documents, attachments, IDs, and numbering configuration.
9. **Crash recovery:** The app recovers valid saved data and identifies incomplete or damaged records.
10. **Historical integrity:** Editing a customer profile does not alter a previously issued document snapshot.
11. **Duplicate handling:** Duplicating an invoice creates a new draft without overwriting the original.
12. **Storage failure:** An inaccessible folder produces a clear error without silently creating a replacement database.

---

## 15. Edge Cases and Failure Handling

The app must safely handle:
- Mac shutdown during a save.
- Data directory moved or renamed.
- Disk full.
- PDF destination file open in another application.
- Same document edited in two app windows.
- Template deleted after use by existing documents.
- Missing or corrupted logo.
- Documents with hundreds of line items.
- Partial payment, refund, or rounding adjustment.
- System date or timezone changes.
- Duplicate document numbers.
- Backups created by older app versions.
- Customer archived while linked to historical invoices.
- External drive disconnecting during use.
- Unsupported fonts or image formats.

The application must provide understandable errors and safe recovery behavior rather than silently discarding data.

---

## 16. Product Success Metrics

- First invoice created in under 2 minutes after setup.
- Existing document found in under 10 seconds.
- 100% of approved PDF layout and calculation test cases pass.
- Zero acknowledged saves lost during normal operation.
- 100% of valid backup test packages restore successfully.
- All core workflows complete without internet access.

These are product targets and should be measured in testing.

---

## 17. Release Checklist

Before release:
- Verify every core workflow with networking disabled.
- Test calculations against approved test fixtures.
- Test PDF rendering across supported paper sizes.
- Test backup and restore on a clean installation.
- Test storage permission errors and external-drive removal.
- Test migrations from each supported previous version.
- Verify keyboard navigation and VoiceOver for core flows.
- Confirm logs do not expose unnecessary customer or financial data.
- Sign and notarize the macOS distribution build.
- Provide clear installation, backup, restore, and data-location documentation.

---

## 18. Final Recommendation

Build DocuDesk around four foundations:

1. A reliable local document engine.
2. A high-quality built-in template library.
3. Reusable data and deterministic calculation services.
4. Transparent folder storage and dependable backup/restore.

Keep the document content, template definition, rendered PDF, and database index separate but linked. This enables editable records, professional output, reliable searching, and template redesign without destroying historical documents.

The recommended initial stack is **SwiftUI + SQLite + JSON document records + native PDFKit/Core Graphics**.

Make the application **offline-first rather than offline-only**. Core work remains local and private, while future optional features such as encrypted backup destinations, additional template packs, or cloud synchronization can be added without making the core application dependent on them.
