import Foundation

/// Ready-made starting content for text documents. Placeholders such as `{{client.name}}` are
/// filled in at render time, so the starter stays correct when details change later.
public struct DocumentStarter: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: DocumentKind
    public let name: String
    public let summary: String
    public let title: String
    public let markup: String

    public static func starters(for kind: DocumentKind) -> [DocumentStarter] {
        all.filter { $0.kind == kind }
    }

    public static func starter(id: String) -> DocumentStarter? {
        all.first { $0.id == id }
    }

    public static let all: [DocumentStarter] = proposals + agreements + letters + reports

    public static func blank(for kind: DocumentKind) -> DocumentStarter {
        DocumentStarter(id: "\(kind.rawValue).blank", kind: kind, name: "Blank \(kind.displayName)", summary: "Start from an empty page.",
                        title: kind == .letter ? "" : kind.displayName, markup: kind == .letter ? "Dear {{client.contact}}," : "# \(kind.displayName)")
    }

    // MARK: Proposals

    static let proposals: [DocumentStarter] = [
        DocumentStarter(id: "proposal.business", kind: .proposal, name: "Business Proposal", summary: "Overview, scope, timeline and investment.", title: "Business Proposal", markup: """
        # Proposal for {{client.name}}
        Prepared by {{company.name}} on {{document.date}}. This proposal is valid until {{document.valid_until}}.
        ## Overview
        Thank you for the opportunity to propose our services. This document outlines our understanding of your goals, the work we will deliver and the investment required.
        ## Objectives
        - Describe the first business objective.
        - Describe the second business objective.
        - Describe how success will be measured.
        ## Scope of Work
        1. Discovery and requirements workshop.
        2. Design and approval of key deliverables.
        3. Build, testing and handover.
        ## Timeline
        | Phase | Duration | Deliverable |
        | Discovery | 1 week | Requirements document |
        | Design | 2 weeks | Approved designs |
        | Build & handover | 4 weeks | Final delivery |
        ## Investment
        The pricing for this proposal is set out in the table below. Applicable taxes are shown separately.
        """),
        DocumentStarter(id: "proposal.sow", kind: .proposal, name: "Scope of Work", summary: "Deliverables, assumptions, exclusions and acceptance.", title: "Scope of Work", markup: """
        # Scope of Work
        This Scope of Work is agreed between {{company.name}} and {{client.name}}.
        ## Deliverables
        - Deliverable one, with a clear description of what is included.
        - Deliverable two.
        ## Assumptions
        - The client will provide content and feedback within 3 working days.
        - Work will be reviewed at agreed milestones.
        ## Out of Scope
        - Anything not listed under Deliverables.
        ## Acceptance
        Each deliverable is considered accepted when approved in writing, or 5 working days after delivery without written objection.
        """),
    ]

    // MARK: Agreements

    static let agreements: [DocumentStarter] = [
        DocumentStarter(id: "agreement.service", kind: .agreement, name: "Service Agreement", summary: "General services contract between two businesses.", title: "Service Agreement", markup: """
        # Service Agreement
        This Service Agreement is made on {{document.date}} between **{{company.name}}**, {{company.address}} (the "Service Provider"), and **{{client.name}}**, {{client.address}} (the "Client").
        ## 1. Services
        The Service Provider will perform the services described in Schedule A (the "Services") with reasonable skill and care.
        ## 2. Fees and Payment
        The Client will pay the fees set out in Schedule A. Invoices are payable within 15 days of the invoice date.
        ## 3. Term and Termination
        This Agreement starts on the date above and continues until the Services are complete. Either party may terminate with 30 days' written notice.
        ## 4. Confidentiality
        Each party will keep the other party's confidential information secret and use it only for this Agreement.
        ## 5. Limitation of Liability
        Neither party is liable for indirect or consequential loss. Total liability is limited to the fees paid under this Agreement.
        ## 6. Governing Law
        This Agreement is governed by the laws of India.
        ---
        # Schedule A: Services and Fees
        | Service | Fee |
        | Describe the service | Amount |
        """),
        DocumentStarter(id: "agreement.nda", kind: .agreement, name: "Non-Disclosure Agreement", summary: "Mutual NDA to protect confidential information.", title: "Non-Disclosure Agreement", markup: """
        # Mutual Non-Disclosure Agreement
        This Agreement is made on {{document.date}} between **{{company.name}}** and **{{client.name}}** (each a "Party").
        ## 1. Purpose
        The Parties wish to share confidential information to evaluate a possible business relationship (the "Purpose").
        ## 2. Confidential Information
        Confidential Information means any non-public business, technical or financial information disclosed by one Party to the other, in any form.
        ## 3. Obligations
        - Use Confidential Information only for the Purpose.
        - Not disclose it to third parties without prior written consent.
        - Protect it with at least reasonable care.
        ## 4. Exclusions
        These obligations do not apply to information that is public, already known, independently developed, or required to be disclosed by law.
        ## 5. Term
        This Agreement lasts 2 years from the date above. Confidentiality obligations survive for 3 years after it ends.
        ## 6. Governing Law
        This Agreement is governed by the laws of India.
        """),
        DocumentStarter(id: "agreement.freelancer", kind: .agreement, name: "Freelancer Contract", summary: "Engagement terms for an independent contractor.", title: "Freelancer Contract", markup: """
        # Freelancer Contract
        This contract is made on {{document.date}} between **{{company.name}}** (the "Client") and **{{client.name}}** (the "Freelancer").
        ## 1. Engagement
        The Freelancer is engaged as an independent contractor, not an employee, to deliver the work described below.
        ## 2. Work and Deliverables
        - Describe the work.
        - Describe the deliverables and deadlines.
        ## 3. Payment
        The Client will pay the agreed fee within 15 days of receiving a valid invoice.
        ## 4. Intellectual Property
        On full payment, all rights in the deliverables pass to the Client.
        ## 5. Termination
        Either party may end this contract with 14 days' written notice. Work completed up to that date will be paid for.
        """),
        DocumentStarter(id: "agreement.website", kind: .agreement, name: "Website Development Agreement", summary: "Design, build, hosting and handover of a website.", title: "Website Development Agreement", markup: """
        # Website Development Agreement
        This Agreement is made on {{document.date}} between **{{company.name}}** (the "Developer") and **{{client.name}}** (the "Client").
        ## 1. Project
        The Developer will design and develop a website as described in the proposal referenced {{document.number}}.
        ## 2. Client Responsibilities
        - Provide content, images and feedback on time.
        - Arrange domain access where required.
        ## 3. Milestones and Payment
        | Milestone | Payment |
        | Signing of this agreement | 40% |
        | Design approval | 30% |
        | Launch | 30% |
        ## 4. Warranty
        The Developer will fix defects reported within 30 days after launch at no extra cost.
        ## 5. Ownership
        On full payment, the Client owns the website content and design. Third-party components remain under their own licences.
        """),
        DocumentStarter(id: "agreement.maintenance", kind: .agreement, name: "Maintenance & Support Agreement", summary: "Ongoing support with response times.", title: "Maintenance and Support Agreement", markup: """
        # Maintenance and Support Agreement
        This Agreement is made on {{document.date}} between **{{company.name}}** and **{{client.name}}**.
        ## 1. Services
        - Security and software updates.
        - Monthly backups and uptime monitoring.
        - Up to 5 hours of minor changes per month.
        ## 2. Response Times
        | Priority | Response |
        | Critical | 4 working hours |
        | Normal | 2 working days |
        ## 3. Fees
        The monthly fee is payable in advance. Unused hours do not carry forward.
        ## 4. Term
        This Agreement runs for 12 months and renews automatically unless either party gives 30 days' notice.
        """),
    ]

    // MARK: Letters

    static let letters: [DocumentStarter] = [
        DocumentStarter(id: "letter.general", kind: .letter, name: "Business Letter", summary: "A plain letter on your letterhead.", title: "", markup: """
        Dear {{client.contact}},
        **Subject: Write the subject here**
        Write your letter here.
        Yours sincerely,
        """),
        DocumentStarter(id: "letter.offer", kind: .letter, name: "Offer Letter", summary: "Job offer with role, salary and joining date.", title: "Offer Letter", markup: """
        Dear {{client.name}},
        **Subject: Offer of Employment**
        We are pleased to offer you the position of **[Job Title]** at {{company.name}}. Your annual cost to company will be **[Amount]**, and your expected joining date is **[Date]**.
        Your appointment will be subject to the terms in your appointment letter, which will be issued on joining. Please confirm your acceptance by signing and returning a copy of this letter by {{document.valid_until}}.
        We look forward to welcoming you to the team.
        Yours sincerely,
        """),
        DocumentStarter(id: "letter.appointment", kind: .letter, name: "Appointment Letter", summary: "Formal appointment with key terms.", title: "Appointment Letter", markup: """
        Dear {{client.name}},
        **Subject: Letter of Appointment**
        Further to your acceptance of our offer, we are pleased to appoint you as **[Job Title]** with effect from **[Date]**, on the following terms:
        1. Probation: 6 months from the date of joining.
        2. Working hours: as per company policy.
        3. Notice period: 30 days on either side after confirmation.
        4. Confidentiality: you will keep all company information confidential during and after your employment.
        Please sign the duplicate copy of this letter as a token of your acceptance.
        Yours sincerely,
        """),
        DocumentStarter(id: "letter.experience", kind: .letter, name: "Experience Letter", summary: "Confirms employment period and role.", title: "Experience Letter", markup: """
        # To Whom It May Concern
        This is to certify that **{{client.name}}** worked with {{company.name}} as **[Job Title]** from **[Start Date]** to **[End Date]**.
        During this period, their conduct and performance were found to be good. We wish them every success in the future.
        """),
        DocumentStarter(id: "letter.relieving", kind: .letter, name: "Relieving Letter", summary: "Confirms resignation and full settlement.", title: "Relieving Letter", markup: """
        Dear {{client.name}},
        **Subject: Relieving Letter**
        This is to confirm that your resignation has been accepted and you are relieved from your duties as **[Job Title]** with effect from close of business on **[Date]**.
        We confirm that your full and final settlement has been completed. We thank you for your contributions and wish you the very best.
        Yours sincerely,
        """),
        DocumentStarter(id: "letter.authorization", kind: .letter, name: "Authorization Letter", summary: "Authorises a person to act on your behalf.", title: "Authorization Letter", markup: """
        # To Whom It May Concern
        **Subject: Letter of Authorization**
        We, {{company.name}}, hereby authorise **[Name]**, holding **[ID document and number]**, to **[describe the purpose]** on our behalf.
        This authorization is valid until **[Date]**. Kindly extend your cooperation.
        """),
        DocumentStarter(id: "letter.reminder", kind: .letter, name: "Payment Reminder", summary: "Polite reminder for an overdue payment.", title: "Payment Reminder", markup: """
        Dear {{client.contact}},
        **Subject: Payment reminder for invoice [Invoice Number]**
        This is a friendly reminder that payment of **[Amount]** for invoice **[Invoice Number]** dated **[Date]** is now overdue.
        If you have already made the payment, please ignore this letter and share the transaction reference so we can update our records. Otherwise, we would appreciate payment at your earliest convenience.
        Thank you for your continued business.
        Yours sincerely,
        """),
    ]

    // MARK: Reports

    static let reports: [DocumentStarter] = [
        DocumentStarter(id: "report.project", kind: .report, name: "Project Report", summary: "Status, progress, risks and next steps.", title: "Project Status Report", markup: """
        # Project Status Report
        Prepared for {{client.name}} on {{document.date}}.
        ## Summary
        Give a short overview of where the project stands.
        ## Progress
        | Workstream | Status | Notes |
        | Design | Complete | Approved |
        | Development | In progress | On schedule |
        | Testing | Not started | Starts next week |
        ## Risks and Issues
        - Describe any risk and how it will be handled.
        ## Next Steps
        1. Next step one.
        2. Next step two.
        """),
        DocumentStarter(id: "report.minutes", kind: .report, name: "Meeting Minutes", summary: "Attendees, decisions and action items.", title: "Meeting Minutes", markup: """
        # Meeting Minutes
        **Date:** {{document.date}}  **Attendees:** [Names]
        ## Agenda
        1. Agenda item one.
        2. Agenda item two.
        ## Decisions
        - Record each decision made.
        ## Action Items
        | Action | Owner | Due |
        | Describe the action | Name | Date |
        """),
        DocumentStarter(id: "report.completion", kind: .report, name: "Work Completion Report", summary: "Confirms delivered work for sign-off.", title: "Work Completion Report", markup: """
        # Work Completion Report
        This report confirms that the work described below has been completed for {{client.name}}.
        ## Work Completed
        - Describe completed work.
        ## Handover
        All deliverables, credentials and documentation have been handed over on {{document.date}}.
        ## Client Acceptance
        The client confirms that the work has been completed to their satisfaction.
        """),
        DocumentStarter(id: "report.certificate", kind: .report, name: "Completion Certificate", summary: "Short certificate of completion.", title: "Certificate of Completion", markup: """
        # Certificate of Completion
        This is to certify that **{{company.name}}** has successfully completed **[Project / Work]** for **{{client.name}}** on {{document.date}}.
        The work was completed in accordance with the agreed scope and specifications.
        """),
    ]
}
