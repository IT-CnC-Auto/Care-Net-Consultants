# Be-Matched: Legal Structure Research

**Prepared for:** Director, Care Net Consultants
**Date:** 24 September 2026
**Status:** Design note. This is research to brief the Director and the company's attorney. It is not legal advice and it does not state that any design satisfies the law.

**How to read the sources.** Direct fetching of legislation sites (SAFLII, LawLibrary, gov.za, the Department of Employment and Labour, the SARB and POPIA mirror sites) was blocked from the research environment. Every finding below therefore rests on search engine snippets of the named pages, which are marked **[snippet]** in the sources list. Section numbers appear only where a source stated them, and each is a **lead to confirm** against the official text before anyone relies on it.

---

## 0. Summary of decisions for the Director and the attorney

| No. | Decision | Owner | Why it matters |
|---|---|---|---|
| D1 | Choose the engagement model for each placement type: pure introduction (client employs or contracts the appointee directly), Care Net as temporary employment service (Care Net pays the appointee), or independent contractor marketplace. | Director with attorney | The model decides whether Care Net becomes the employer (see 2). |
| D2 | Confirm whether Care Net must register as a private employment agency today, given conflicting sources on whether the registration section of the Employment Services Act is in force. | Attorney | Department messaging says registration is required; law firm commentary says the registration section was excluded from commencement (see 1.2). |
| D3 | Remove any fee, deduction or subscription charged to appointees (work seekers) for placement services, unless the attorney confirms a lawful exception. | Director | Charging work seekers is prohibited, with a fine per contravention reported (see 1.3). |
| D4 | Replace the phrase "employee trust account" with a defined funds flow, and choose who holds client money: a registered third party payment provider or digital escrow provider (preferred on current evidence), an attorney's trust account, or a formal trust. Care Net should not hold pooled client money in its own name. | Director with attorney and bank | Holding and releasing other people's money raises Banks Act, National Payment System and FIC Act exposure (see 3). |
| D5 | Decide the VAT and income tax treatment of held funds and of Care Net's fee (agent or principal). | Director with tax practitioner | Determines what Care Net invoices and declares (see 3.7). |
| D6 | Keep a human decision maker on every discrepancy or "work not done" finding; the AI monitor may only flag. | Director | POPIA restricts decisions based solely on automated processing (see 4.1). |
| D7 | Before using Grok (xAI) or any offshore AI service on engagement letters, sign an operator agreement, establish a lawful basis for cross border transfer, and keep health information out of the AI pipeline unless the attorney approves. | Director with attorney and Information Officer | POPIA operator, cross border and special personal information rules (see 4.2 to 4.4). |
| D8 | Confirm professional registration checks for appointees (for example SACPCMP registration for construction health and safety officers) as a platform gate. | Director | Placing an unregistered appointee exposes the client and Care Net's reputation (see 5.3). |

---

## 1. Private employment agencies under the Employment Services Act, 2014

### 1.1 Does Be-Matched fall within the Act?

1.1.1 The Employment Services Act 4 of 2014 came into operation on 9 August 2015 (Cliffe Dekker Hofmeyr; Labour Guide) **[snippet]**.

1.1.2 Commentary states that both labour brokers and recruitment agencies are private employment agencies for purposes of the Act (Labour Guide; Werksmans) **[snippet]**. A portal that matches appointees to client companies for permanent, contract or per site engagements is, on that description, likely to be treated as a private employment agency. The exact statutory definition could not be read and must be confirmed.

### 1.2 Registration with the Department of Employment and Labour

1.2.1 The Department of Employment and Labour publishes material stating that "anyone recruiting and placing work seekers into employment is required by law to register with the Department" and that "all recruitment agencies must be registered" (labour.gov.za pages) **[snippet]**.

1.2.2 The Department's draft regulations on the registration of private employment agencies and temporary employment services (published for comment in 2018 in Government Gazette 42140, with public hearings in February 2019) provide for a compulsory registration and certification system, with the registrar to issue a certificate within 60 days of a complete application, a certificate displayed at the agency's premises, and a non refundable application fee (gov.za; labour.gov.za) **[snippet]**.

1.2.3 Section 13(7) is cited as requiring an electronic public register of registered private employment agencies (labour.gov.za snippet) **[snippet; lead to confirm]**.

1.2.4 **Conflict to resolve.** Cliffe Dekker Hofmeyr and Labour Guide report that the commencement notice specifically excluded section 13 (registration of private employment agencies) from coming into operation **[snippet; lead to confirm]**. No source found in this research confirms that section 13 was later proclaimed or that the draft registration regulations were finalised. The attorney must confirm the current position (decision D2). A prudent design assumes registration will be required and builds the data fields and certificate display now.

1.2.5 **What triggers it.** On the sources, the trigger is the business of recruiting and placing work seekers into employment, whether as a recruitment agency or a labour broker. Whether a pure independent contractor marketplace also triggers it could not be verified.

### 1.3 Fees charged to work seekers

1.3.1 Sources state that no person may charge a work seeker a fee for providing employment services to that work seeker, subject to an exception where the Minister, by notice in the Government Gazette, permits a specified fee for specified categories of employees or for specialised services (Maserumule; Labour Guide) **[snippet]**.

1.3.2 Sources also state that an employer may not deduct any amount from an employee's remuneration for the placement of that employee, and that contravention may attract a fine not exceeding R50 000 per contravention (Cliffe Dekker Hofmeyr) **[snippet; lead to confirm the amount and the section]**.

1.3.3 A 2015 Department media statement deals with private employment agency service fees (gov.za, 17 February 2015) **[title only]**. Its content could not be read.

1.3.4 **Design consequence.** Be-Matched should charge the client company, not the appointee. Appointee subscriptions, "profile boost" fees, verification fees or a percentage retained from the appointee's pay all need the attorney's clearance first.

---

## 2. Temporary employment services under the Labour Relations Act, 1995

### 2.1 When Care Net becomes the employer

2.1.1 Section 198(1) is quoted as defining a temporary employment service as any person who, for reward, procures for or provides to a client other persons who render services to, or perform work for, the client, and who are remunerated by the temporary employment service (acts.co.za; Labour Guide) **[snippet; lead to confirm]**.

2.1.2 The same sources state that a person so procured or provided is the employee of the temporary employment service, and the temporary employment service is that person's employer (section 198(2) per the snippets) **[snippet; lead to confirm]**.

2.1.3 **Design consequence.** The decisive fact is who remunerates the appointee. If money flows client to Care Net (or a Care Net controlled account) and Care Net pays the appointee, Care Net risks being the temporary employment service and therefore the employer. If the client pays the appointee directly (or a neutral escrow provider pays on the client's instruction) and Care Net earns only a placement or platform fee from the client, the introduction model is more likely. The "employee trust account" concept as described sits close to the first model and needs the attorney's view (decisions D1 and D4).

### 2.2 Joint and several liability

2.2.1 Sources state that section 198 applies to all placed employees regardless of earnings, and that the temporary employment service and the client are jointly and severally liable where the temporary employment service contravenes a collective agreement, an arbitration award, the Basic Conditions of Employment Act or a sectoral determination (SEESA; Labour Guide) **[snippet]**. Section 198(4) is cited for this **[lead to confirm]**.

2.2.2 Where the client is jointly and severally liable under section 198(4), or is deemed the employer under section 198A(3)(b), the employee may institute proceedings against the temporary employment service, the client, or both (SEESA) **[snippet; lead to confirm]**.

### 2.3 The deeming provision for lower paid workers

2.3.1 Section 198A applies to employees earning below the earnings threshold set under section 6 of the Basic Conditions of Employment Act (Cliffe Dekker Hofmeyr; SEESA) **[snippet]**.

2.3.2 The threshold was increased to R269 600.90 per annum from 1 May 2026 by Government Notice 7384 in Government Gazette 54544 of 17 April 2026 (DLA Piper; Werksmans; SEESA) **[snippet; one aggregator shows R269 900.90, so confirm the exact figure in the Gazette]**.

2.3.3 A "temporary service" is service to a client for a period not exceeding three months, as a substitute for a temporarily absent employee, or as designated in a collective agreement or sectoral determination (Cliffe Dekker Hofmeyr guideline; SEESA) **[snippet]**.

2.3.4 A below threshold employee placed beyond a genuine temporary service is deemed to be the employee of the client, and the Constitutional Court in *Assign Services (Pty) Ltd v NUMSA* [2018] ZACC 22 held that after three months the client becomes the sole employer for purposes of the LRA, while the temporary employment service is the employer during the first three months (SAFLII case listing; De Rebus; CEOSA) **[snippet]**.

2.3.5 **Relevance to Be-Matched.** Many first aiders and some safety officers and supervisors are likely to earn below the threshold. A per site placement running longer than three months would, under a temporary employment service model, shift employer status to the client. Clients should be told this plainly in the engagement terms.

### 2.4 Interaction with independent contractors

2.4.1 Sources state that the deeming provision in section 198A(3) does not apply to genuine independent contractors, and that the test for employee or independent contractor status differs above and below the threshold (Cliffe Dekker Hofmeyr guideline) **[snippet]**.

2.4.2 Section 200A creates a rebuttable presumption that a person earning below the threshold is an employee where any one of several listed factors is present, including control over the work or hours, integration into the organisation, at least 40 hours a month over three months, economic dependence, tools provided by the other party, and working for only one person (Cliffe Dekker Hofmeyr diagram; search summary) **[snippet; lead to confirm the exact wording of each factor]**.

2.4.3 **Design consequence.** Labelling appointees "contractors" does not settle their status. An appointee who works full time on one client's site under the client's direction is at real risk of being an employee. The attorney should approve separate contract templates for each engagement model, and the platform should capture the facts that drive the section 200A factors.

---

## 3. Holding client money

### 3.1 The problem with an "employee trust account"

3.1.1 "Employee trust account" is not a recognised legal vehicle in any source found. Money that Care Net receives from a client and later releases to an appointee against work done is, in substance, either (a) Care Net's own money with a contractual payment obligation, (b) money held for another person by a regulated intermediary, or (c) trust property under a formal trust. Each has different triggers, set out below.

### 3.2 Banks Act exposure

3.2.1 ENS (via Lexology) states that if a payment service provider accepts funds from a person for on payment to a third party but agrees to repay that person on demand, it may be accepting deposits in contravention of the Banks Act **[snippet]**.

3.2.2 The SARB published a Draft Exemption Notice under the Banks Act definition of "business of a bank" and a Draft Directive on specific payment activities on 3 March 2025. Revised drafts followed (a version dated 14 November 2025 is listed on the SARB site), described as materially different from the March versions. Under the drafts, listed "exempted payment activities" that pool public funds in a store of value or payment account would not constitute the business of a bank, but only for authorised entities that segregate and safeguard client funds (ENS; Bowmans; SARB listing) **[snippet]**. Whether these are final at September 2026 could not be verified.

3.2.3 **Design consequence.** Care Net pooling client money in its own account, with refunds on demand if work is not done, is the pattern the sources flag as risky. Using an authorised provider moves that exposure off Care Net.

### 3.3 National Payment System Act and SARB positions on third party payment providers

3.3.1 SARB Directive 1 of 2007 governs third party payment providers, being persons who accept money or the proceeds of payment instructions from payers for on payment to third persons to whom the money is due, as permitted under section 7 of the National Payment System Act. It recognises beneficiary service providers and payer service providers (PASA copy of the Directive; FinMark) **[snippet; lead to confirm section 7]**.

3.3.2 Market practice is that a third party payment provider operates under a sponsoring bank and is registered with the Payments Association of South Africa (see 5.1) **[snippet]**.

3.3.3 A National Payment System Amendment Bill intended to open the system to non bank providers was, at the latest report found, not yet introduced to Parliament; commentators suggested a 2026 implementation horizon (ENS; Mondaq) **[snippet]**. Current status at September 2026 could not be verified.

3.3.4 **Design consequence.** If Care Net itself collects client money and pays appointees for a fee, it may be acting as a third party payment provider and would need a sponsoring bank and PASA registration. Contracting with an existing registered provider avoids that.

### 3.4 Attorney's trust account (Legal Practice Act 28 of 2014)

3.4.1 Section 86 is cited as requiring every legal practitioner referred to in section 84(1) to operate a trust account; section 86(2) accounts hold money held on behalf of any person; section 86(3) accounts invest money not immediately required; section 86(4) accounts invest money on a specific client's instruction, with interest to that client less 5 percent to the Legal Practitioners Fidelity Fund (LinkedIn commentary; LSSA auditors' guide; Fidelity Fund) **[snippet; lead to confirm subsections and the percentage]**. Rule 54 of the Legal Practice Council rules deals with trust accounting, including interest (SAICA and LSSA material) **[snippet; lead to confirm]**.

3.4.2 **Fit.** An attorney can hold stake money for a transaction on agreed release conditions, and trust money has Fidelity Fund protection. The drawbacks for Be-Matched are cost per transaction, manual release, and whether an attorney will act as a routine, high volume payment conduit for a commercial platform. Whether the Legal Practice Council rules limit that use could not be verified; the attorney should advise.

### 3.5 Formal trust under the Trust Property Control Act 57 of 1988

3.5.1 Section 10 is cited as requiring trust money to be deposited in a separate bank account in the trust's name, and section 11 as requiring trust property to be separately identifiable (IOL Business Report; Trusteeze; STBB) **[snippet; lead to confirm]**. Recent amendments added beneficial ownership registers kept by the Master (Moonstone; Tax Faculty) **[snippet]**.

3.5.2 **Fit.** A trust requires trustees authorised by the Master, trust deed governance, annual administration and its own tax affairs. A trust does not by itself remove Banks Act or payment system questions if it runs a pooled payment business. Persons who carry on the business of administering trust property are accountable institutions under the FIC Act (3.6.2). This is the heaviest option.

### 3.6 Financial Intelligence Centre Act 38 of 2001

3.6.1 Amendments to Schedule 1 took effect on 19 December 2022 (Government Gazette 47596), greatly widening the list of accountable institutions (Werksmans; Moonstone; nCino KYC Africa) **[snippet]**.

3.6.2 Legal practitioners are listed as item 1; trust and company service providers as item 2, which now includes persons carrying on the business of preparing for or carrying out transactions, including as trustee, related to the investment, control, safe keeping or administration of trust property; additional money and value transfer providers were also added (FIC Public Compliance Communication 6A; Werksmans; nCino) **[snippet; lead to confirm item numbers]**.

3.6.3 Accountable institutions must register with the FIC and carry out customer due diligence, record keeping and reporting duties, with dual registration where more than one item applies (FIC reference guide; nCino) **[snippet]**.

3.6.4 **Design consequence.** If Care Net holds and releases money for clients and appointees in its own name, or acts as trustee, the attorney must assess whether Care Net becomes an accountable institution. Using a registered provider places those duties on the provider, although Care Net should still expect know your customer data requests.

### 3.7 VAT and income tax on held funds (high level)

3.7.1 Section 54 of the VAT Act 89 of 1991 is cited as treating supplies made by an agent on behalf of a principal as made by the principal, with the agent accounting for VAT only on its own commission; section 54(3) statements document disbursements (Tax Faculty; Cliffe Dekker Hofmeyr; SARS VAT Connect) **[snippet; lead to confirm]**.

3.7.2 **Design consequence.** If Care Net is only an introducer and money sits with a third party provider, Care Net's taxable supply is its fee to the client. If Care Net is a temporary employment service, it supplies the service itself: the full charge to the client is Care Net's turnover, and Care Net carries PAYE, UIF and SDL for the placed employees. Independent contractors who are VAT vendors invoice separately. Interest earned on held funds and who receives it must be settled in the terms. A tax practitioner must confirm the treatment (decision D5). No SARS ruling specific to recruitment escrow was found.

---

## 4. POPIA and automated monitoring

### 4.1 Decisions based solely on automated processing

4.1.1 Section 71(1) is reported as providing that a data subject may not be subject to a decision which results in legal consequences for them, or which affects them to a substantial degree, which is based solely on the automated processing of personal information intended to provide a profile of the person, including their performance at work, reliability, location, health or conduct (Werksmans; Polity; ITLawCo) **[snippet; lead to confirm wording]**.

4.1.2 Section 71(2) allows exceptions, including in connection with a contract where appropriate measures protect the data subject's legitimate interests, which must include an opportunity to make representations about the decision (Werksmans; Polity) **[snippet; lead to confirm]**.

4.1.3 **Design consequence.** Withholding payment, flagging "work not done" or ending an engagement because the AI bot found a discrepancy would plainly have legal and substantial effects. The bot should raise a flag for a named human reviewer who decides, and the affected appointee or client must be told and able to respond before any release is withheld.

### 4.2 Operator agreement with the AI provider

4.2.1 Section 21 is cited as requiring the responsible party to ensure, in a written contract, that an operator establishes and maintains the security measures referred to in section 19; section 20 sets operator duties, including processing only with the responsible party's knowledge or authorisation and treating information as confidential (Fasken; ITLawCo; popia.co.za listing) **[snippet; lead to confirm]**.

4.2.2 **Design consequence.** xAI (for Grok), and any hosting or orchestration provider in the path, will be an operator. Care Net must have written terms binding them to POPIA grade security and confidentiality, restricting use of prompts and documents for model training, and requiring breach notification. Standard consumer or API terms may not suffice; the attorney should review them.

### 4.3 Cross border transfer

4.3.1 Section 72 is cited as permitting transfer outside South Africa only on listed grounds, such as a recipient bound by law, binding corporate rules or an agreement providing adequate protection, the data subject's consent, or necessity for a contract with or for the data subject (CMS; Michalsons; Mashiane Attorneys) **[snippet; lead to confirm the grounds]**.

4.3.2 **Design consequence.** Sending engagement letters containing names, identity numbers, rates and site details to a United States based model provider is a cross border transfer. A data transfer agreement and notice to data subjects are the minimum; the lawful ground should be recorded.

### 4.4 Special personal information if health data is involved

4.4.1 Section 26 is reported as prohibiting processing of special personal information, which includes health information, unless an exception in sections 27 to 33 applies; section 32 authorises certain processing of health information, including by employers and insurers, subject to confidentiality (Michalsons; popia.co.za listing) **[snippet; lead to confirm]**.

4.4.2 Regulations on processing health information under section 32(6) were reported in 2025 and 2026 commentary (Labour Guide; Mayet; ITLawCo; Moonstone) **[snippet]**. Their final status and content could not be verified.

4.4.3 Section 57(1)(d) is reported as requiring prior authorisation from the Information Regulator before transferring special personal information to a third country without adequate protection (search summary citing Michalsons) **[snippet; lead to confirm]**.

4.4.4 **Design consequence.** First aid incident records, medical fitness certificates and injury reports are health information. Keep them out of the AI monitoring pipeline and out of offshore processing until the attorney and Information Officer confirm a lawful basis and any prior authorisation.

---

## 5. Market practice

### 5.1 Digital escrow and milestone payments

5.1.1 TradeSafe describes itself as a South African digital escrow service offering split payments, milestone payments and drawdowns; commentary states that funds are held in a dedicated escrow account at Standard Bank separate from operating funds, that it operates as a third party payment provider, and that Standard Bank took a 35 percent shareholding (tradesafe.co.za; Africa Global Funds; Disrupt Africa) **[snippet]**.

5.1.2 Truzo describes itself as an authorised financial services provider (FSP 51539) and third party payment provider sponsored by FirstRand Bank, registered with PASA, holding South African client funds in trust accounts (truzo.com; Financial IT) **[snippet]**.

5.1.3 Paysho and Payburse also market escrow services in South Africa (paysho.co.za; payburse.com) **[snippet]**. Their regulatory status was not checked.

5.1.4 These are examples found in sources, not recommendations. Due diligence on any provider should confirm sponsoring bank, PASA registration, fund segregation, fees, API support for milestone release and dispute handling.

### 5.2 Contractor platforms and staffing firms

5.2.1 Kandua (home services) states that professionals are paid quickly and that customers may pay a deposit so the professional can prepare; SweepSouth offers prepaid booking by instant EFT or SnapScan (kandua.com; SweepSouth help centre) **[snippet]**. Neither source confirmed a formal escrow model.

5.2.2 International employer of record and contractor platforms (Deel, Rippling, Papaya Global, Remote) handle South African contractor contracts and payouts (their published guides) **[snippet]**. No source described how South African staffing firms for health and safety appointees structure escrow; that could not be verified.

### 5.3 Professional registration of appointees

5.3.1 Sources state that construction health and safety officers appointed under Construction Regulation 8(5) must be registered with the SACPCMP, and that health and safety representatives are designated under sections 17 and 18 of the Occupational Health and Safety Act (SACPCMP registration rules; SERR Synergy; Labour Guide) **[snippet; lead to confirm]**. This supports decision D8.

---

## 6. What could not be verified

6.1 The full text of any statute or regulation, because official sites were blocked.

6.2 Whether section 13 of the Employment Services Act is now in force and whether the registration regulations are final.

6.3 Whether the SARB exemption notice and payment activities directive are final at September 2026, and the status of the National Payment System Amendment Bill.

6.4 Whether Legal Practice Council rules restrict attorneys acting as routine escrow agents for a platform.

6.5 The exact 2026 BCEA threshold figure (two figures appear in sources).

6.6 Final POPIA health information regulations, and any Information Regulator guidance on AI.

6.7 How South African health and safety staffing firms handle escrow in practice.

---

## 7. Sources

All entries were read as search result snippets only unless stated; none could be fetched in full.

7.1 Labour Guide, "Employment Services Act": https://labourguide.co.za/general/employment-services-act [snippet]
7.2 Cliffe Dekker Hofmeyr, "Employment Services Act came into effect on 9 August 2015": https://www.cliffedekkerhofmeyr.com/en/news/publications/2015/employment/employment-alert-12-august-employment-services-act-came-into-effect-on-9-august-2015.html [snippet]
7.3 Maserumule, "The Employment Services Act": https://www.masconsulting.co.za/the-employment-services-act/ and PDF https://www.masconsulting.co.za/wp-content/uploads/2017/08/Employment-Services-Act.pdf [snippet]
7.4 Werksmans, "Employment Services Act": https://werksmans.com/employment-services-act/ [snippet]
7.5 Department of Employment and Labour, PEA and TES page: https://www.labour.gov.za/DocumentCenter/Pages/Private-Employment-Agencies-(PEA)-and-Temporary-Employment-Services-(TES).aspx [snippet]
7.6 Department of Employment and Labour, "Anyone recruiting and placing work seekers...": https://www.labour.gov.za/anyone-recruiting-and-placing-work-seekers-into-employment-is-required-by-law-to-register-with-the-department-of-labour-(2) [snippet]
7.7 Department of Employment and Labour, "Did you know? All recruitment agencies must be registered": https://www.labour.gov.za/DocumentCenter/Publications/Public%20Employment%20Services/Did%20you%20Know%20that%20All%20recruitment%20agencies%20must%20be%20registered%20with%20Department%20of%20Employment%20and%20Labour%20.pdf [title only]
7.8 Draft registration regulations, GG 42140: https://www.gov.za/sites/default/files/gcis_document/201812/42140rg10902gon1432s.pdf [snippet]
7.9 gov.za, "Labour on registration of PEAs and TES" (26 February 2019): https://www.gov.za/news/labour-registration-private-employment-agencies-and-temporary-employment-services-26-feb-2019 [snippet]
7.10 gov.za, "Labour on private employment agencies service fees" (17 February 2015): https://www.gov.za/news/media-statements/labour-private-employment-agencies-service-fees-17-feb-2015 [title only; fetch blocked]
7.11 acts.co.za, LRA section 198: https://source.acts.co.za/labour-relations-act-1995/198__temporary_employment_services.php [snippet]
7.12 SEESA, "Temporary employment: what's changed": https://www.seesa.co.za/blog/temporary-employment-whats-changed-for-employers-and-labour-brokers/ [snippet]
7.13 Cliffe Dekker Hofmeyr, Temporary Employment Services Guideline: https://www.cliffedekkerhofmeyr.com/practice-areas/downloads/Employment-Law-Temporary-Employment-Services-Guideline.pdf [snippet]
7.14 Cliffe Dekker Hofmeyr, section 200A diagram (December 2023): https://www.cliffedekkerhofmeyr.com/export/sites/cdh/news/publications/2023/Practice/Employment/Employment-Law-Alert-5-December-2023-Diagram.pdf [snippet]
7.15 *Assign Services (Pty) Ltd v NUMSA* [2018] ZACC 22: https://www.saflii.org/za/cases/ZACC/2018/22.html [snippet]
7.16 De Rebus, Assign Services update: https://www.derebus.org.za/employment-law-update-the-constitutional-court-brings-finality-on-the-interpretation-of-an-amendment-to-the-lra/ [snippet]
7.17 CEOSA, deeming provision: https://ceosa.org.za/the-effect-of-the-deeming-provision-on-the-employment-relationship-in-terms-of-section-198a-of-the-labour-relations-act/ [snippet]
7.18 DLA Piper, "BCEA earnings threshold and national minimum wage increase" (2026): https://www.dlapiper.com/en-us/insights/publications/2026/04/bcea-earnings-threshold-and-national-minimum-wage-increase [snippet]
7.19 Werksmans, "1 May 2026 BCEA earnings threshold adjustment": https://werksmans.com/understanding-the-1-may-2026-bcea-earnings-threshold-adjustment-implications-for-employers-and-employees/ [snippet]
7.20 SARB Directive 1 of 2007 (PASA copy): https://authorisation.pasa.org.za/wp-content/uploads/2024/07/SARB-Directive-1-of-2007-Third-Party-Payments-Providers.pdf [snippet; fetch blocked]
7.21 FinMark Trust, retail payment services note: https://finmark.org.za/system/documents/files/000/000/372/original/FocNote3_ProfileRPSinSA1.pdf [snippet]
7.22 ENS via Lexology, "Breaking the bank": https://www.lexology.com/library/detail.aspx?g=07f9fcf0-4904-4a21-a336-f82846e67fd0 [snippet]
7.23 SARB, Draft Payment Activities Exemption Notice (14 November 2025): https://www.resbank.co.za/content/dam/sarb/what-we-do/payments-and-settlements/pem/dialogues/2025/Draft%20Payment%20Activities%20Exemption%20Notice%20-%20for%20publication%20-%2014%20Nov%20%202025.pdf [title only; fetch blocked]
7.24 Bowmans, SARB draft activity based authorisation framework: https://bowmanslaw.com/insights/the-south-african-reserve-bank-has-recently-published-a-draft-activity-based-authorisation-framework-for-participants-banks-and-non-banks-in-the-national-payment-system/ [snippet]
7.25 ENS, "When will South Africa's NPS Bill come into force?": https://www.ensafrica.com/news/detail/10690/when-will-south-africas-nps-bill-come-into-fo [snippet]
7.26 LinkedIn (C Holliday), "Legal Practice Act 28 of 2014, Section 86": https://www.linkedin.com/pulse/legal-practice-act-28-2014-section-86-carl-holliday [snippet]
7.27 LSSA, Guide for registered auditors on legal practitioners' trust accounts: https://www.lssa.org.za/wp-content/uploads/2020/05/Guide-for-RAs_Engagements-on-LP-Trust-Accounts-Revised-March-2020-clean.pdf [snippet]
7.28 Legal Practitioners Fidelity Fund, trust bank accounts: https://www.fidfund.co.za/trust-accounts/ [snippet]
7.29 IOL Business Report, "Why a trust requires its own bank account": https://iol.co.za/business-report/opinion/2020-09-02-trust-to-trust-why-a-trust-requires-its-own-bank-account/ [snippet]
7.30 Moonstone, amendments to the Trust Property Control Act: https://www.moonstone.co.za/what-trustees-should-know-about-the-amendments-to-the-trust-property-control-act/ [snippet]
7.31 Werksmans, FIC Act amendments: https://www.werksmans.com/legal-updates-and-opinions/the-implication-of-the-amendments-to-the-financial-intelligence-centre-act-38-of-2001/ [snippet]
7.32 FIC, Public Compliance Communication 6A (TCSPs): https://www.fic.gov.za/wp-content/uploads/2023/09/2023.08-PCC-PCC-6A-Trust-and-company-service-provider.pdf [snippet]
7.33 FIC, Reference guide for all accountable institutions: https://www.fic.gov.za/wp-content/uploads/2023/09/2022.12-CG-FIC-Act-reference-guide.pdf [snippet]
7.34 nCino KYC Africa, new categories in Schedule 1: https://blog.kycafrica.ncino.com/the-new-categories-in-fic-act-schedule-1 [snippet]
7.35 Tax Faculty, "VAT agency and principals": https://taxfaculty.ac.za/news/read/vat-agency-and-principals-2 [snippet]
7.36 SARS, VAT Connect Issue 15: https://www.sars.gov.za/businesses-and-employers/my-business-and-tax/newsletters/vat-connect-issue-15-december-2022/ [snippet]
7.37 Werksmans, "When machines make decisions" (POPIA section 71): https://werksmans.com/when-machines-make-decisions-understanding-the-impact-of-the-protection-of-personal-information-act-2013-popia/ [snippet]
7.38 ITLawCo, automated decision assessment under POPIA: https://itlawco.com/focus-areas/data-protection-and-privacy/protection-of-personal-information-act/automated-decision-assessment-under-popia/ [snippet]
7.39 Fasken, "Beware of the operator contract": https://www.fasken.com/en/knowledge/2023/09/beware-of-the-operator-contract-a-necessity-for-popia-compliance [snippet]
7.40 CMS, "Managing cross-border data transfers": https://cms.law/en/zaf/legal-updates/Managing-cross-border-data-transfers [snippet]
7.41 Michalsons, guidance on transborder flows: https://www.michalsons.com/blog/guidance-note-on-cross-border-transfers-to-from-south-africa/77246 [snippet]
7.42 Michalsons, privacy in healthcare: https://www.michalsons.com/blog/privacy-in-healthcare/8637 [snippet]
7.43 Labour Guide, new POPIA regulations on health information: https://labourguide.co.za/general/new-popia-regulations-on-the-processing-of-health-information-what-employers-must-know [snippet]
7.44 TradeSafe: https://www.tradesafe.co.za/ and FAQ https://www.tradesafe.co.za/faq/ [snippet]
7.45 Africa Global Funds, Standard Bank stake in TradeSafe: https://www.africaglobalfunds.com/news/investors/standard-bank-acquires-35-of-tradesafe-escrow/ [snippet]
7.46 Truzo: https://www.truzo.com/ and Financial IT article https://financialit.net/news/payments/truzo-becomes-first-and-only-fca-approved-digital-escrow-service-focus-africa [snippet]
7.47 Paysho: https://paysho.co.za/ ; Payburse: https://payburse.com/ [snippet]
7.48 Kandua: https://kandua.com/ ; SweepSouth payment methods: https://help.sweepsouth.com/hc/en-us/articles/115005448085-Approved-Payment-Methods [snippet]
7.49 Deel, contractors in South Africa: https://www.deel.com/hiring/contractors/south-africa/ [snippet]
7.50 SACPCMP registration rules for construction health and safety officers: https://sacpcmp.org.za/wp-content/uploads/2018/11/Registration-Rules-for-Construction-Health-and-Safety-Officers.pdf [snippet]
7.51 SERR Synergy, OHS requirements for construction: https://serr.co.za/what-are-the-ohs-legislative-requirements-for-the-sa-construction-industry [snippet]
