# CNC MSP FORGE: KERNEL INGESTION WORKFLOW

Document Reference: CNC-MSP-FORGE-ING-V1.0-2026 | Anchor: KRN-ING-01 v1.1.0 | Classification: INTERNAL

## 1. PURPOSE

1.1 This document defines how a legal or clinical source enters the Cognitive Kernel, how it is verified, and how it is excluded. The agent may only assert what the kernel contains. Anything else is [CONFIRM] and routes to the OMP queue.

## 2. THE THREE GATES

2.1 A source is citable only when its msp_legal_instrument row reads status verified, which requires all three gates:
2.1.1 Gate a. The primary instrument itself is located: the Act, Regulation, Government Gazette notice, HPCSA booklet, SANS standard, or peer reviewed guideline. Recorded in source_one.
2.1.2 Gate b. A second authoritative corroboration: Department of Employment and Labour or DMRE guidance, a SASOM position paper, or an accredited academic or professional source. Recorded in source_two.
2.1.3 Gate c. A currency check confirming the instrument has not been amended, repealed, or superseded, with the amendment history recorded. Recorded in source_three and amendment_history.

2.2 A source that cannot pass all three gates is excluded, not padded, and logged in msp_kernel_exclusion with the failed gate and the reason.

## 3. WORKFLOW FUNCTIONS

3.1 Stage: `select msp_ingest_instrument(short_name, full_citation, type, gazette_ref, effective_date);` creates a pending row carrying [CONFIRM] markers in all three source fields. A pending row is never citable.

3.2 Verify: `select msp_verify_instrument(id, source_one, source_two, source_three, amendment_history, verified_by, review_due);` asserts non empty, non [CONFIRM] sources at every gate and a future review date, then sets status verified with the verification date.

3.3 Exclude: `select msp_exclude_instrument(id, failed_gate, reason, excluded_by);` sets status excluded and writes the exclusion register row.

3.4 Watch: the msp_verification_due view lists verified instruments within sixty days of review_due. It must be checked before any pack generation batch. Founding example: the Noise-Induced Hearing Loss Regulations, 2003 carry review_due 06/09/2026, the date regulation 18 of the Noise Exposure Regulations, 2024 repeals them.

## 4. VERIFICATION RECORD DISCIPLINE

4.1 verified_by names the person or agent and the method. Documentary verification performed by the build agent is recorded as subject to OMP ratification and stands only until a human verifier ratifies or supersedes it.

4.2 OEL values live on msp_hazard with their citing instrument in oel_instrument and verification_status verified only when the value itself has passed the gates. An unverified OEL never prints in a released pack; the PROFILE stage treats it as unresolved and routes the exceedance assessment to the OMP queue.

4.3 Intervals longer than the twelve month floor are impossible without a legal basis citation: the msp_interval_floor_citation check constraint enforces this in the database.

## 5. PHASE 1 VERIFICATION LEDGER (12/08/2026)

5.1 Verified (13): OHS Act 85 of 1993; Construction Regulations, 2014; Noise-Induced Hearing Loss Regulations, 2003 (repeal horizon 06/09/2026 recorded); Noise Exposure Regulations, 2024; Regulations for Hazardous Chemical Agents, 2021; Ergonomics Regulations, 2019; COIDA as amended 2026; Employment Equity Act section 7; BCEA section 17(3) with the Code of Good Practice on the Arrangement of Working Time; NRTA PrDP medical provisions; HPCSA Booklets 1, 10, and 11.

5.2 Staged pending (6): General Safety Regulations; General Administrative Regulations; General Machinery Regulations; Driven Machinery Regulations; Code of Practice for Audiometry, 2025; SANS 10083 (edition to confirm, CR-12.3).

5.3 Verified OELs (2): noise 85 dB(A) 8 hour rating level; respirable crystalline silica 0.1 mg/m3 8 hour TWA. All other limit values remain unverified and uncitable (CR-12.1).

5.4 Excluded: none to date.

## 6. TAXONOMY EXTENSION RULE

6.1 The taxonomy is data, not code. A new industry, subindustry, role, hazard mapping, or protocol is an insert by the forge_verifier role, never a deploy. A subindustry becomes selectable in the onboarding form only when its role, hazard, and protocol map has passed verification (Phase 6 batch gate on msp_subindustry.selectable).

## 7. LEARNING UPDATE LEDGER, RELEASE 1.1.0 (16/09/2026, migration 042)

7.1 Source: the Care Net Consultants OH Value Chain Regulatory Instrument Pack dated 15/09/2026 (primary Gazette texts with dual URL corroboration and a currency check on that date), supplied by the MD with the instruction to update the kernel with all the occupational health legislation currently available. Documentary verification by the IT maintenance agent, subject to OMP ratification (CR-14.1).

7.2 Transition executed: the Noise-Induced Hearing Loss Regulations, 2003 (repealed 06/09/2026 by regulation 18 of the Noise Exposure Regulations, 2024) and the Environmental Regulations for Workplaces, 1987 (repealed 06/09/2026 by regulation 21 of the Physical Agents Regulations, 2024) are superseded. Every protocol that cited them now cites the 2024 instrument. Both rows stay for packs dated before the transition, which the FRAME stage still handles by engagement date.

7.3 Verified new (9): Physical Agents Regulations, 2024 (Table 1 values: heat stress WBGT action level 27 and limit 30; hand arm vibration 2,5 and 5 metres per square second; whole body vibration 0,5 and 1,15 metres per square second; ultraviolet 0,1 microwatt per square centimetre; records 40 years), mapped to every industry; Code of Practice for Audiometry, 2025 (from pending); SANS 10083:2023 Edition 6.1 (from pending, licensed copy held); SANS 451:2008 Edition 1 (licensed copy held); Circular Instruction 171 (COIDA); POPIA; Health Professions Act 56 of 1974; Nursing Act 33 of 2005; Asbestos Abatement Regulations, 2020 as amended 2022.

7.4 Currency checks of 15/09/2026 appended (10): OHS Act; Construction Regulations, 2014; HCA Regulations, 2021; HBA Regulations, 2022; Lead Regulations, 2001 (the 2024 draft is for comment only, CR-14.2); General Administrative Regulations, 2003; General Safety Regulations, 1986 (amended by GN 5954 of 6 March 2025); COIDA (Proclamation 306 of 2026 commencement dates recorded); EEA section 7; Noise Exposure Regulations, 2024.

7.5 Verified OELs now (4): noise 85 dB(A); respirable crystalline silica 0.1 mg/m3; lead 0.15 mg/m3; heat stress WBGT 30 (action level 27). Vibration values are recorded on hazard G but the numeric field stays null because the key carries two limits (CR-14.4).

7.6 Still pending and uncitable: General Machinery Regulations (draft 2025 replacement on the standing watch). Not entered by design: the Draft Lead Regulation, 2024 (for comment, CR-14.2); Compensation Fund CompEasy manuals and the COIDA Service Book (guidance, CR-14.5); SASOM and SASOHN guideline bodies (member only, catalogued in the pack); SANS 10182 and SANS 10154 (catalogue only until licensed copies are held, CR-12.3).
