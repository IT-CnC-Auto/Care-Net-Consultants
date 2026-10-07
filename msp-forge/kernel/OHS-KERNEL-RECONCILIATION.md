# CNC OHS Industry Kernel and the live Cognitive Kernel: reconciliation

Prepared 23/09/2026 for the Director. Compares the CNC OHS Legal Compliance Kernel pack supplied on 23/09/2026 (held verbatim in `kernel/cnc-ohs-industry-kernel/`, status SANDBOX until OMP and attorney review) with the live Cognitive Kernel in the Supabase project, read on 23/09/2026 (release 1.0.0). Nothing in the live kernel has been changed by this comparison. Every divergence below is a decision for the Director and the OMP, recorded in SPEC.md Part B, register items HSF-7 and HSF-11 to HSF-16.

## 1. The starting position agrees

1.1 **Industries.** The seventeen industries in the pack are the seventeen in the live kernel, by name and order.

1.2 **Roles.** Every role count in the pack matches the live kernel: Agriculture 19, Cleaning 10, Construction 31, Education 10, Government 16, Healthcare 18, Hospitality 12, Manufacturing 41, Mining 35, Office 10, Petrochemical 16, Retail 12, Security 10, Telecommunications 15, Transport 30, Utilities 16, Waste 15. Total 316.

1.3 **Protocols.** Both hold thirty medical protocols, and the names correspond one to one.

1.4 **Method rules shared.** Risk assessment first, protocol second; mining is never sold as an OHS Act only pack; Care Net screens fitness and does not diagnose; the employer pays. HSF FORGE already builds on all four.

## 2. The pack confirms the live kernel is out of date (HSF-7)

2.1 The pack treats the Noise Exposure Regulations, 2024 and the Physical Agents Regulations, 2024 as operative, and the NIHL Regulations, 2003 and the Environmental Regulations for Workplaces, 1987 as repealed from 06/09/2026.

2.2 The live kernel still cites the NIHL Regulations, 2003 for audiometry (protocol 1) and the Environmental Regulations, 1987 for heat stress (protocol 14), both marked verified. Repository migration 042 fixes both, but has never been applied to the live project.

2.3 The pack therefore independently confirms HSF-7. Migration 042 should be applied (with OMP ratification) before any further Plan or File is released.

## 3. Protocol legal basis, row by row

| # | Protocol | Live kernel basis | Pack basis and strength | Finding |
| --- | --- | --- | --- | --- |
| 1 | Audiometry | NIHL Regulations, 2003 | Noise Exposure Regulations, 2024 and Code of Practice; strong | Conflict: live cites a repealed instrument (HSF-7) |
| 2 | Spirometry | HCA Regulations | HCA and Asbestos surveillance, OMP directed; practice | Agree |
| 3 | Respiratory symptom questionnaire | HCA Regulations | HCA, Asbestos, physical agents screening; practice | Agree |
| 4 | Chest X-ray per silica protocol | HCA Regulations | No single Gazette; OMP directed under HCA or Asbestos; mines to MHSA; catalogue | Agree outside mining; mining basis open (HSF-11) |
| 5 | Dust disease battery for mine workers | ODMWA (benefit examination battery) | MHSA and mine medical Codes of Practice; catalogue | Different instruments: ODMWA covers benefit examinations, MHSA covers surveillance. Both may apply (HSF-11) |
| 6 | Blood lead biological monitoring | Lead Regulations, 2001 | Lead Regulations, 2001; strong | Agree |
| 7 | Lead exposure clinical examination | Lead Regulations, 2001 | Lead Regulations, 2001; strong | Agree |
| 8 | Biological monitoring for chemical agents | HCA Regulations | HCA Regulations; strong | Agree |
| 9 | Chemical exposure medical assessment | HCA Regulations | HCA Regulations; strong | Agree |
| 10 | Cholinesterase monitoring | HCA Regulations | HCA under OMP protocol; practice | Agree |
| 11 | Dermatological screen | HCA Regulations | HCA and HBA; practice | Agree; pack adds HBA |
| 12 | Heights medical | Construction Regulations, 2014 | Construction Regulations and OHS Act risk assessment; practice | Agree |
| 13 | Confined space medical | None | OHS Act and programmes; no dedicated regulation; practice | Agree: neither cites a dedicated instrument |
| 14 | Heat stress tolerance | Environmental Regulations, 1987 | Physical Agents Regulations, 2024; strong | Conflict: live cites a repealed instrument (HSF-7) |
| 15 | Heat tolerance, hot underground workings | MHSA, verified | MHSA heat instruments; catalogue | Confidence differs (HSF-11) |
| 16 | Vibration and musculoskeletal screen | Ergonomics Regulations, 2019 | Physical Agents Regulations, 2024; strong | Differs; migration 042 moves this to the Physical Agents Regulations |
| 17 | Musculoskeletal and ergonomic assessment | Ergonomics Regulations, 2019 | OHS Act duties and EEA section 7; practice | Differs: the pack does not hold the Ergonomics Regulations, 2019 at all (HSF-13) |
| 18 | Night work medical | BCEA night work Code | Physical Agents Regulations and BCEA interface; practice | Agree in substance |
| 19 | PrDP statutory medical | NRTA PrDP medical, verified | NRTA framework; catalogue | Confidence differs (HSF-11) |
| 20 | Lifting machine operator fitness | Driven Machinery Regulations, verified | Driven Machinery Regulations, edition to confirm; catalogue | Confidence differs (HSF-11) |
| 21 | Mine certificate of fitness | Fitness to Perform Work Guideline (MHSA), verified | MHSA medical certificate framework; catalogue | Confidence differs (HSF-11) |
| 22 | Railway safety critical fitness | SANS 3000-4 (RSR), verified | RSR standards; unverified | Confidence differs (HSF-11) |
| 23 | General medical, electrical work | Electrical Machinery and Installation Regulations, verified | Electrical regulations; catalogue | Confidence differs (HSF-11) |
| 24 | Vision, colour vision and UV skin | None | OHS Act and Physical Agents interfaces; practice | Agree: no single instrument |
| 25 | Radiation worker surveillance | Hazardous Substances Act (radiation control), verified | Hazardous Substances Act and NNR; unverified | Confidence differs (HSF-11) |
| 26 | Occupational TB screening | HBA Regulations, 2022 | HBA Regulations, 2022; strong | Agree |
| 27 | Hepatitis B pathway | HBA Regulations, 2022 | HBA Regulations, 2022; strong | Agree |
| 28 | Biological agent surveillance | HBA Regulations, 2022 | HBA Regulations, 2022; strong | Agree |
| 29 | Zoonosis surveillance | HBA Regulations, 2022 | HBA Regulations, 2022; practice | Agree |
| 30 | Food handler fitness | Food Premises Hygiene Regulations, R638 of 2018 | Municipal by laws per metro; society guidance | Differs: live cites a national regulation the pack does not hold (HSF-14) |

Summary: 16 agree, 2 conflict because the live kernel is behind (HSF-7), and 12 differ in basis or confidence (protocol 4 agrees outside mining only).

## 4. Instrument confidence: the core difference in method

4.1 The live kernel marks MHSA, the Fitness to Perform Work Guideline, the NRTA PrDP provisions, SANS 3000-4, the Hazardous Substances Act, the Driven Machinery Regulations and the Electrical Machinery and Installation Regulations as **verified** through its three checks (August 2026 batches).

4.2 The pack marks the same seven as **catalogue or unverified**, because its rule is stricter: a claim is high confidence only if the instrument's full text is held on disk in the Value Chain Instruments pack.

4.3 Neither is wrong on its own terms, but a File cannot carry both. Recommendation: adopt the pack's rule for HSF FORGE (the text must be held on file before a File cites it), and fetch the seven bodies named in the pack's Watch Bee list (06-GAPS-AND-NEXT, top ten) so both kernels reach the same answer. Until then the website samples show these protocols as "Catalogue, being fetched". (HSF-11)

## 5. What the pack adds that neither kernel yet holds

| Item | Status in pack | Action |
| --- | --- | --- |
| Physical Agents Regulations amendment, GN 7149, GG 54177, 20 February 2026 | Named as a fetch target for table currency | Not in the live kernel or in migration 042. Fetch and verify before the heat and vibration values are relied on (HSF-12) |
| Draft HCA Regulation, GN R4598, GG 50431 | Watch item, draft only | Add to the standing watch; never cite |
| MHSA Amendment Bill B10-2026 | Bill before Parliament | Add to the standing watch; never cite |
| HPCSA Booklet 5 (confidentiality), 4, 9 | URL only | Fetch; supports the POPIA handling element HSF-E-10 |
| CompEasy occupational disease manuals | Linked, not held | Fetch; supports HSF-I-05 |
| SANS 7243:2021 and SANS 2631-5:2024 | Catalogue | Licensed copies needed before citation (extends CR-12.3) |

## 6. Instruments the live kernel holds that the pack does not

Ergonomics Regulations, 2019; Facilities Regulations, 2004; General Machinery Regulations, 1988; MHI Regulations, 2022 (the pack treats MHI as explanatory only); NEM Waste Act; HPCSA Booklets 1, 10 and 11; BCEA night work Code; Food Premises Hygiene Regulations, R638 of 2018. The pack should either add these or record why it leaves them out (HSF-13). The Ergonomics Regulations, 2019 matter most, because two protocols rest on them.

## 7. Naming

The pack titles the HCA instrument "Hazardous Chemical Agents Regulations, 2020 (GN R280)" with a Gazette date of 29 March 2021; the live kernel titles it "HCA Regulations, 2021". The Gazette title decides; confirm and align both (HSF-15).

## 8. Rules adopted into HSF FORGE from the pack

8.1 **No compliance stamps.** No page, template or File says "POPIA compliant", "Lighthouse compliant" or similar. Two website chips that said "POPIA compliant" (shop.html and medical-surveillance-plans.html) now read "Records handled under POPIA".

8.2 **Risk assessment first.** A protocol the pack lists only "if HIRA confirms" never switches on from the industry alone. The sample Files show those protocols as not applicable until the risk assessment confirms exposure.

8.3 **Basis strength shown.** Section E items carry the pack's strength label: strong local basis, practice and agent duty, society guidance and local by law, or catalogue.

8.4 **Sandbox status travels.** The pack is SANDBOX until OMP and attorney review; the sample Files say which kernel they were built from and that it is sandbox.

## 9. The pack's ten templates map onto File elements

| Template | File element it evidences |
| --- | --- |
| HIRA register | HSF-C-01 baseline risk assessment; HSF-C-04 hazard register |
| Legal appointments checklist | HSF-B-03 to HSF-B-06 appointments |
| Induction and training record | HSF-D-03 inductions; HSF-D-06 toolbox talks |
| Contractor OHS file index | HSF-A-09 contractor register; HSF-K-02 contractor Files |
| Incident and OD reporting checklist | HSF-I-01 to HSF-I-06 |
| Medical surveillance plan | HSF-E-01 |
| Certificate of fitness cover note | HSF-E-02 |
| Exit medical checklist | HSF-E-02 exit certificates; HSF-E-06 protocols |
| POPIA records purpose note | HSF-E-10; HSF-O-02 |
| Industry plan cover | HSF-A-02 scope of the File |

In Phase 4 these become engine generated evidence templates (hsf_evidence source engine_generated), after the attorney and OMP review the pack asks for (HSF-16).
