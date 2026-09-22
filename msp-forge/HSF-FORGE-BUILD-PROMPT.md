# CNC HSF FORGE: MASTER BUILD PROMPT

Document Reference: CNC-HSF-FORGE-V1.0-2026 | Version 1.0 | Date of Issue: 22/09/2026 | Classification: INTERNAL

Prepared for Care Net Consultants (Pty) Ltd on the Director's instruction of 22/09/2026. This prompt commissions a sibling of CNC MSP FORGE: an engine that builds a full, auditable Health and Safety File for any of the seventeen industries the Cognitive Kernel already maps, and that links the medicals and the training a client has done with Care Net straight out of MyClinicOnline (MCO) into the File as evidence.

Read this prompt to the end before doing anything. It is written to be handed to a build agent as its opening instruction. Everything the MSP FORGE build established still stands; this prompt extends it and never contradicts it.

---

## 1. WHO YOU ARE AND HOW YOU WORK

1.1 You are Claude Code acting as occupational health and safety systems architect and document engineer for Care Net Consultants (Pty) Ltd, under the direction of the Director. You build on the existing CNC MSP FORGE repository (msp-forge), its Supabase project, its Cognitive Kernel and its SOP for the kernel agent. You do not start a new stack.

1.2 Governance boundaries, restated as build constraints.
1.2.1 Care Net screens fitness for work and provides preventive care. Care Net does not diagnose. The engine drafts; a registered professional approves. Nothing is released without a recorded approval, and that rule lives at the database layer, not in prose.
1.2.2 The Occupational Medical Practitioner signs the medical surveillance content of the File and nothing else. The safety content of the File is signed by the person the law names for it: the employer's section 16(2) appointee, and for construction work the client's agent or the registered construction health and safety professional. Who at Care Net countersigns safety content, and in what professional capacity, is a decision for the Director before Phase 6. Record it as an open confirmation item; do not assume it.
1.2.3 The employer is always the payer. HPCSA perverse incentive rules apply to every medical element.
1.2.4 Mining follows the Mine Health and Safety Act and the ODMWA route for lung disease. Every other industry follows the Occupational Health and Safety Act and COIDA. That routing is a kernel rule.
1.2.5 The limitation of liability block, the POPIA blocks and the sign off blocks are inserted verbatim from locked templates and never paraphrased.
1.2.6 WARDEN ring fence: no AutoHive, Glass Castle or Think Tank SA content, branding, agents or copy anywhere in this system. The CRM, where referenced, is AutoHive CRM by name only.

1.3 Register. SA British English. Rand written as R4 250,00. No dash or hyphen punctuation in prose; official instrument names keep their natural form. Staff are sales executives, never consultants; the word consultant appears only inside the company name. Numbering starts at 1, never at 0. Secrets never in the repository or the database; references only.

1.4 The kernel discipline applies to every legal instrument you touch. An instrument is cited only after it passes three checks: the primary text, an independent corroborating source, and a currency check that confirms it is in force today. An instrument that fails a check is recorded as pending and is never cited in a File. You do not guess a gazette number, a regulation number or a commencement date. Where this prompt names an instrument it does not yet hold verified, it names it as a candidate for verification, and you treat it that way.

1.5 Never fabricate a pending input. Where a decision, a credential, an MCO endpoint or a template is not yet in hand, leave the marked placeholder and say so in the build state.

---

## 2. WHAT YOU ARE BUILDING

2.1 The product. A Health and Safety File is the employer's organised, evidenced record that the duties the law places on it are identified, assigned, carried out and kept current. In construction it is a statutory object: the Construction Regulations, 2014 require the contractor to keep a health and safety file on site, open to inspection, and to hand it to the client on completion. For every other industry it is the practical proof of section 8 of the Occupational Health and Safety Act, and the first thing an inspector, an auditor, a principal contractor or an insurer asks for. CNC HSF FORGE builds that File, complete for the client's industry, with every element listed, every element carrying its legal basis, and every element carrying its evidence or its gap.

2.2 What "auditable" means here, and what the engine must therefore do.
2.2.1 Every element in the File carries: the duty in plain words, the instrument and the provision it rests on, who is responsible, the evidence required, the review interval, and the current status.
2.2.2 Status is one of exactly five values: linked from MCO, uploaded by the client, outstanding, not applicable with a written reason, or expired. Nothing else.
2.2.3 Every piece of evidence is versioned, hashed on receipt, dated, and attributed to the person who supplied it. Replacing evidence never deletes the earlier version.
2.2.4 The File carries a revision number and a change log. A revision is triggered by a change notification, an updated risk assessment, a new appointment, an expiry, or a kernel legislation release.
2.2.5 The File produces a gap report and a compliance figure per section and overall, and an audit pack export (PDF plus the evidence index) that an inspector can read without the system.
2.2.6 Every action is written to the append only audit table.

2.3 The link to MCO. Where a client has done its medicals or its training with Care Net, MyClinicOnline holds the record. The File must pull those records in as evidence rather than ask the client to upload what Care Net already has.
2.3.1 Medicals: certificates of fitness per employee per protocol, with issue date, expiry, restrictions, and the practitioner who signed. These populate the medical surveillance section, the Construction Regulations Annexure 3 requirements where construction work applies, the professional driving permit medicals where driving applies, and the mine certificate of fitness where mining applies.
2.3.2 Training: every training record MCO holds per employee, with provider, unit standard or course name, date, expiry and certificate reference. These populate the training matrix and the competency evidence of every appointment.
2.3.3 Linking is by client account. msp_client_account gains an MCO company reference; employees are matched on MCO's own person identifier, never on name alone. Where MCO has no record, the element shows outstanding and offers upload. Where MCO has a record that has expired, the element shows expired and the renewal path.
2.3.4 The MCO interface contract is not yet in hand (register item CR-13.12 is open). Phase 5 begins with that contract. Until then, build against a documented adapter interface with a fixture, and mark every MCO path as pending integration in the build state. Do not invent MCO endpoints.

2.4 What the engine is not. It does not decide that a workplace is safe. It does not certify a person as competent. It does not determine fitness for duty. It does not adjudicate under labour law. It assembles, evidences, flags and reports; the people the law names decide and sign.

---

## 3. WHAT YOU START WITH

3.1 The Cognitive Kernel already holds, verified and live: 17 industries, 56 subindustries, 316 job roles with their hazard profiles, 30 medical protocols each with a legal basis, and 31 verified legal instruments with full citation, gazette reference, verification date and next review. It also holds the kernel rules (including the noise transition executed in release 1.1.0), the exclusions, the precedent store, the parameter store, the monthly audit agent and the assistant connection. Read SOP-KERNEL-AGENT.md, SPEC.md, BUILD-STATE.md and backup/MANIFEST.md before Phase 0.

3.2 The 31 instruments the kernel holds today, all verified, are: Asbestos Abatement Regulations, 2020; BCEA night work Code; COIDA; Construction Regulations, 2014; Driven Machinery Regulations; EEA section 7; Electrical Machinery and Installation Regulations; Environmental Regulations for Workplaces, 1987; Ergonomics Regulations, 2019; Facilities Regulations, 2004; Fitness to Perform Work Guideline (MHSA); Food Premises Hygiene Regulations, R638 of 2018; General Administrative Regulations, 2003; General Machinery Regulations, 1988; General Safety Regulations, 1986; Hazardous Substances Act (radiation control); HBA Regulations, 2022; HCA Regulations, 2021; HPCSA Booklet 1; HPCSA Booklet 10; HPCSA Booklet 11; Lead Regulations, 2001; MHI Regulations, 2022; MHSA; NEM Waste Act; NIHL Regulations, 2003 (superseded 06/09/2026, retained for history); Noise Exposure Regulations, 2024; NRTA PrDP medical; ODMWA; OHS Act; SANS 3000-4 (RSR). Their full citations are in msp_public_instrument_register and in vercel/downloads/CNC-Legislation-Register-v1.0.0.pdf.

3.3 Those 31 were verified for medical surveillance. A Health and Safety File needs them in their full scope, and it needs instruments the kernel does not yet hold. Section 5 lists the candidates. Each one enters the kernel as pending and is cited only once it passes the three checks.

3.4 The site, the shell and the journey exist: the shared Care Net header, hero, section navigator and footer under vercel/css and vercel/js; the sign in journey on the landing page; the assessment page; the sample viewer; the Build your Plan page with its calculator and the public legislation register. HSF FORGE uses the same shell and the same account.

---

## 4. THE UNIVERSAL ELEMENT LIBRARY

Every File, in every industry, contains the sections below. Each section lists its elements. Each element becomes a row in the element library (Section 7) with its legal basis, evidence type, responsible role, review interval and industry applicability. The list is written to be complete for what a File could ever need; the industry overlays in Section 6 switch elements on, add to them, and never remove a universal one silently. Where an element does not apply, the File says so, with the reason, and the auditor sees it.

### 4.1 Section A: Legal and administrative
1. Company legal identity, registration, VAT, physical addresses of every site.
2. Scope of the File: sites, activities, dates, contract or project reference where applicable.
3. Letter of good standing under COIDA, with expiry.
4. Copy of the Occupational Health and Safety Act and its regulations available at the workplace, as the Act requires, and the mining equivalent.
5. Notification of construction work to the Department of Employment and Labour where the Construction Regulations require it, with acknowledgement.
6. Client health and safety specification and the contractor's health and safety plan where construction work applies, with the client's written approval.
7. Section 37(2) agreements with every mandatary and every contractor.
8. Contractor register: every contractor, its File, its letter of good standing, its appointments.
9. Legal register for the industry: every instrument that applies, with its provision, drawn from the kernel and dated.
10. Document control procedure and the File's own revision history.

### 4.2 Section B: Policy, organisation and appointments
1. Health and safety policy signed by the chief executive, dated, displayed, reviewed annually.
2. Section 16(1) chief executive responsibility and section 16(2) assignment, in writing, accepted in writing, with the scope of assignment.
3. Section 17 health and safety representatives, designated in writing after consultation, one per the ratios the Act sets, with training evidence.
4. Section 19 health and safety committee where the Act requires one, with its constitution, membership and minutes.
5. Every statutory appointment for the industry, in writing, signed and accepted, with the competence evidence the appointment requires. The universal set: construction manager and assistant construction manager; construction health and safety officer; construction supervisor; risk assessor; fall protection planner; scaffold supervisor and scaffold inspector; excavation supervisor; demolition supervisor; temporary works designer and supervisor; construction vehicle and mobile plant operator and supervisor; electrical installation supervisor and construction electrical appointee; lifting machine and lifting tackle inspector and operator; general machinery supervisor; pressure equipment supervisor; hazardous chemical agent controller; ladder inspector; stacking and storage supervisor; first aiders in the ratios the General Safety Regulations set; fire equipment inspector and fire team; emergency coordinator and evacuation wardens; incident investigator; confined space supervisor; explosive powered tool operator and issuer; hot work supervisor; asbestos work supervisor; lead work supervisor; noise zone controller; radiation protection officer; food safety and hygiene supervisor; driver and professional driving permit holder; and the industry specific appointments in Section 6.
6. Organogram of the health and safety structure with every appointee in post.
7. Roles and responsibilities per appointment, and per job role from the kernel's role library.

### 4.3 Section C: Risk management
1. Baseline hazard identification and risk assessment per site, per activity, signed by the risk assessor, dated, with the review date.
2. Issue based risk assessments for every change, incident, new task or new substance.
3. Continuous and task based risk assessments, and the daily or shift pre task assessments where the industry uses them.
4. Hazard register mapped to the kernel's hazard taxonomy per job role.
5. Hierarchy of control evidence: what was eliminated, substituted, engineered, administered, and only then protected against.
6. Safe work procedures and method statements for every routine and every high risk task.
7. Fall protection plan where work at height occurs.
8. Traffic management plan where vehicles and people share space.
9. Lifting plans for every lifting operation that requires one.
10. Excavation, demolition, confined space and hot work plans where those activities occur.
11. Ergonomic risk assessment under the Ergonomics Regulations.
12. Noise zoning and noise risk assessment under the Noise Exposure Regulations.
13. Hazardous chemical agent risk assessment and exposure assessment under the HCA Regulations, including asbestos and lead where present.
14. Hazardous biological agent risk assessment under the HBA Regulations where it applies.
15. Psychosocial and fatigue risk assessment where shift work, night work or violence exposure exists.
16. Major hazard installation risk assessment and emergency plan where the MHI Regulations apply.

### 4.4 Section D: Training and competence
1. Training needs analysis per job role, drawn from the kernel's statutory competency requirements per role.
2. Training matrix: every person, every requirement, date done, expiry, evidence. Populated from MCO where Care Net delivered the training.
3. Induction: site, company and visitor induction records.
4. Statutory and safety critical training records: health and safety representative, first aid, fire fighting, working at height and fall arrest, scaffold erection and inspection, confined space entry, lifting machine and lifting tackle operation, forklift and mobile plant, hazard identification and risk assessment, incident investigation, hazardous chemical handling, asbestos and lead awareness, hearing conservation, ergonomics, emergency evacuation, food handler hygiene, and every industry specific competency in Section 6.
5. Licences and permits held by persons: professional driving permit, plant and machinery licences, electrical wireman and installation registrations, gas practitioner registration, explosives, firearms competency where security work applies, and every industry specific licence in Section 6.
6. Toolbox talk register and attendance.
7. Competency assessment records where a role requires assessment rather than attendance.

### 4.5 Section E: Medical surveillance and fitness
1. The Medical Surveillance Plan for the company, from MSP FORGE, signed by the practitioner where the client has bought the signature.
2. Certificates of fitness per employee per protocol, with expiry, populated from MCO where Care Net did the medicals: baseline, periodic and exit.
3. Construction Regulations Annexure 3 medical certificates of fitness for every person on a construction site where the Regulations require them.
4. Professional driving permit medicals where driving applies.
5. Mine certificate of fitness per the mandatory Code of Practice where mining applies.
6. Statutory examinations that specific regulations require: lead, asbestos, hazardous chemical agents, hazardous biological agents, noise, radiation, heights, confined space, night work, food handling.
7. Fitness restrictions and their reflection in job placement, without disclosing clinical detail beyond what the law allows the employer to hold.
8. Occupational disease reporting and referral records under COIDA and ODMWA.
9. First aid records: first aid box contents and inspection, first aider list, treatment register.
10. Confidentiality and POPIA handling of every medical record in the File: what the employer holds, what Care Net holds, and the lawful basis for each.

### 4.6 Section F: Registers and inspections
1. Scaffold register and inspection records.
2. Ladder register and inspections.
3. Lifting machines and lifting tackle register with load tests and inspections.
4. Portable electrical tools and equipment register with inspections.
5. Electrical installation certificate of compliance and the installation inspection register.
6. Fire equipment register: extinguishers, hose reels, hydrants, detection, with service dates.
7. Emergency lighting and signage inspections.
8. Pressure equipment register with inspections and certificates.
9. Vehicle and mobile plant register with daily checks and maintenance.
10. Excavation inspection register.
11. Personal protective equipment issue register and inspection.
12. Hazardous chemical agent register with safety data sheets, quantities and storage.
13. Asbestos inventory and register where asbestos is present.
14. Machine guarding inspection register.
15. Housekeeping and walkabout inspection records.
16. Stacking and storage inspections.
17. Fall arrest equipment register and inspections.
18. Confined space register.
19. Explosive powered tool register.
20. Welfare facilities inspection under the Facilities Regulations.
21. Lighting, ventilation and thermal environment measurements under the Environmental Regulations for Workplaces.
22. Waste register where waste is generated, stored or transported.

### 4.7 Section G: Permits and controls
1. Permit to work system and the permit register.
2. Hot work permits.
3. Confined space entry permits.
4. Excavation permits and service clearances.
5. Working at height permits.
6. Electrical isolation, lockout and tagout records.
7. Lifting operation permits.
8. Demolition permits.
9. Road closure and traffic accommodation approvals.
10. Radiation work authorisations where they apply.

### 4.8 Section H: Emergency preparedness
1. Emergency plan per site, with roles, assembly points, contact list and evacuation routes.
2. Emergency drills: schedule, records, findings and corrective actions.
3. Fire risk assessment and fire plan.
4. Medical emergency arrangements and nearest facilities.
5. Spill response where chemicals are held.
6. Major hazard installation emergency plan and the public information duty where the MHI Regulations apply.
7. Security emergency procedures where security work applies.

### 4.9 Section I: Incident management
1. Incident and near miss reporting procedure.
2. Incident register.
3. Section 24 reporting to the Department of Employment and Labour and the Annexure 1 recording under the General Administrative Regulations.
4. Investigation reports under the General Administrative Regulations, with root cause and corrective action.
5. COIDA claim records and employer's reports of accidents and diseases.
6. Occupational disease notifications.
7. Corrective and preventive action register with closure evidence.

### 4.10 Section J: Occupational hygiene
1. Occupational hygiene survey programme.
2. Noise survey by an approved inspection authority and the noise zone map.
3. Hazardous chemical agent exposure monitoring by an approved inspection authority.
4. Illumination survey.
5. Ventilation and thermal survey.
6. Asbestos and lead air monitoring where those regulations apply.
7. Biological monitoring results as they bear on controls, held under medical confidentiality.

### 4.11 Section K: Contractors, visitors and the public
1. Contractor selection criteria and evaluation.
2. Section 37(2) agreements and contractor files (also in Section A).
3. Contractor inductions, permits and daily coordination records.
4. Visitor control and induction.
5. Public protection: hoarding, signage, public liability evidence.

### 4.12 Section L: Communication and consultation
1. Health and safety committee minutes and action tracking.
2. Health and safety representative inspection reports and recommendations.
3. Toolbox talks (also in Section D).
4. Notices displayed: Act and regulations, appointments, emergency numbers, policy.
5. Change notification records to Care Net for medical surveillance and to the client for construction work.

### 4.13 Section M: Environment, welfare and facilities
1. Facilities Regulations compliance: sanitation, drinking water, change rooms, eating places, in the ratios the Regulations set.
2. Environmental Regulations for Workplaces compliance: lighting, ventilation, thermal, housekeeping.
3. Environmental management where the NEM Waste Act or other environmental law applies.
4. Waste manifests and licensed disposal evidence.

### 4.14 Section N: Audit, review and improvement
1. Internal audit schedule and reports.
2. External audit reports (client, principal contractor, certification body, inspector).
3. Management review records.
4. Objectives and targets with measurement.
5. Non conformance and corrective action log with closure evidence.
6. Kernel legislation release notes applied to this File, with the date and what changed.

### 4.15 Section O: Records and retention
1. Retention schedule per record type, from the instrument that sets it, including the 40 year retention for medical surveillance records of hazardous exposure.
2. Storage location and access control for every record type.
3. POPIA operator agreement between the client and Care Net for the records Care Net holds.

---

## 5. INSTRUMENTS TO VERIFY BEFORE THEY MAY BE CITED

5.1 The kernel's 31 instruments are re verified in their full scope, because a File cites provisions well beyond the medical ones: for example the Construction Regulations for appointments, plans and the File itself; the General Safety Regulations for first aid, personal protective equipment, confined spaces and ladders; the General Machinery Regulations for guarding and supervision; the Driven Machinery Regulations for lifting equipment; the Electrical Machinery and Installation Regulations for certificates of compliance; the General Administrative Regulations for incident recording and investigation; the Facilities Regulations in full; the Environmental Regulations for Workplaces in full; the MHI Regulations in full; the NEM Waste Act for waste duties.

5.2 Candidate instruments the kernel does not yet hold. Each is a name to verify, not a citation. You find the primary text, corroborate it, check currency, and only then enter it with its gazette reference and dates. Any that fail stay pending.
1. Occupational Health and Safety Act sections in full: 7 (policy), 8 (general duties), 9 (persons other than employees), 13 (information), 14 (employee duties), 16 (chief executive), 17 to 20 (representatives and committees), 24 and 25 (reporting), 37 (acts of mandataries), 38 (offences).
2. Pressure Equipment Regulations, 2009.
3. Lift, Escalator and Passenger Conveyor Regulations, 2010.
4. Explosives Regulations under the Explosives Act, and the Regulations on the use of explosive powered tools.
5. Diving Regulations, 2009, where diving work occurs.
6. Regulations on Hazardous Work by Children, 2010.
7. Electrical Installation Regulations, 2009, and the wireman registration provisions, read with SANS 10142.
8. National Building Regulations and Building Standards Act 103 of 1977 and SANS 10400 (fire, T part).
9. Fire Brigade Services Act 99 of 1987 and local fire by laws.
10. Disaster Management Act 57 of 2002 where it bears on emergency planning.
11. Basic Conditions of Employment Act in full for hours, overtime, rest and the night work Code already held.
12. Labour Relations Act as it bears on health and safety disputes and dismissals for safety breaches (reference only, never adjudicated).
13. Protection of Personal Information Act 4 of 2013 in full, including the operator provisions.
14. National Road Traffic Act in full for dangerous goods (SANS 10231, SANS 10232), operator cards and vehicle roadworthiness.
15. Railway Safety Regulator Act 16 of 2002 and the SANS 3000 series beyond part 4.
16. Civil Aviation Act 13 of 2009 and its regulations for aviation ground handling.
17. Merchant Shipping Act and the Ports Act for port work.
18. Private Security Industry Regulation Act 56 of 2001 and PSIRA training regulations.
19. Firearms Control Act 60 of 2000 for armed security and cash in transit.
20. National Health Act 61 of 2003 and the Health Care Waste regulations for healthcare.
21. Nursing Act, Health Professions Act and SAHPRA provisions as they bear on clinical workplaces (reference only).
22. Foodstuffs, Cosmetics and Disinfectants Act 54 of 1972 and the Food Premises Hygiene Regulations already held, in full.
23. National Environmental Management Act 107 of 1998 and the air quality, water and hazardous waste instruments that follow from it.
24. Mine Health and Safety Act in full with its regulations and the mandatory Codes of Practice per guideline, including the DMRE guidelines for fitness, noise, dust, thermal stress and fatigue.
25. Occupational Diseases in Mines and Works Act in full for the mining File.
26. Skills Development Act and the SETA unit standards that the safety critical training in Section D rests on.
27. Compensation for Occupational Injuries and Diseases Act in full, including the reporting forms and the letter of good standing provisions.
28. Tobacco Products Control Act as it bears on workplace smoking.
29. Regulations on Hazardous Biological Agents, Hazardous Chemical Agents, Asbestos Abatement, Lead, Noise Exposure and Ergonomics in full scope (already held, re verified for the File's provisions).
30. Employment Equity Act section 7 and the Code of Good Practice on Employment of Persons with Disabilities as they bear on placement after a fitness restriction.

5.3 Every instrument, held or candidate, carries a review date. The monthly kernel audit agent takes the File's instruments into its currency check from Phase 2 onward.

---

## 6. THE SEVENTEEN INDUSTRY OVERLAYS

For each industry the overlay states what it adds. The kernel's role library, hazards and protocols for that industry are already loaded and drive Sections C, D and E. Elements listed here are additions or emphases; the universal library still applies in full.

1. Agriculture and forestry. Pesticide and organophosphate handling and cholinesterase surveillance; tractor and implement guarding; chainsaw and forestry harvesting competencies; zoonosis controls; child labour prohibition on hazardous work; seasonal worker induction; heat exposure; remote site emergency response; firearms where game and stock protection applies.
2. Cleaning and hygiene services. Chemical handling with safety data sheets at every site; working at height for facade and high level cleaning; confined space for tank and duct work; biological agent exposure in healthcare and sanitation cleaning; lone worker and night work controls; multi site client induction records.
3. Construction. The full Construction Regulations, 2014 apply: notification, client specification, contractor plan, the health and safety file itself, every appointment in regulation 8 and onward, fall protection plan, structures, temporary works, excavation, demolition, scaffolding, suspended platforms, construction vehicles and mobile plant, electrical installations, use and temporary storage of flammables, water environments, housekeeping, stacking, fire precautions, and Annexure 3 medicals for every person on site. Principal contractor and contractor layering is modelled explicitly.
4. Education. Laboratory and workshop chemicals; playground and sports equipment inspections; learner transport and professional driving permits; food service hygiene where meals are served; biological agents and immunisation in early childhood settings; emergency plans that account for learners; child protection interfaces referenced, not adjudicated.
5. Government and municipal. Public works and roads (construction overlay applies to works); water and wastewater confined spaces; emergency and traffic services fitness; fleet management; public facility fire and evacuation; multi department appointment structures; procurement of contractors under section 37(2).
6. Healthcare and laboratories. Hazardous biological agents in full, immunisation and post exposure protocols, sharps and healthcare risk waste, ionising radiation under the Hazardous Substances Act with a radiation protection officer and dose records, cytotoxic and anaesthetic gas controls, patient handling ergonomics, violence and psychosocial controls, night work, laboratory biosafety levels, Health Care Waste regulations.
7. Hospitality and food service. Food Premises Hygiene Regulations in full, food handler fitness, kitchen fire and gas installation certificates, liquefied petroleum gas practitioner registration, slips and burns controls, night work, alcohol and violence exposure, pool and lifeguard requirements where applicable, housekeeping chemical handling.
8. Manufacturing. General Machinery Regulations and guarding in full, pressure equipment, lifting equipment, electrical certificates of compliance, hazardous chemical agents and process specific controls (lead, asbestos where legacy plant exists, solvents, welding fume, isocyanates), noise zoning, ergonomics on lines, confined space in vessels, forklift competencies, food safety where food is manufactured, dangerous goods storage and transport.
9. Mining. The Mine Health and Safety Act regime replaces the OHS Act: section 2A employer duties, mandatory Codes of Practice per DMRE guideline (fitness to perform work, noise, airborne pollutants, thermal stress, fatigue, trackless mobile machinery, fall of ground, emergency preparedness), the certificate of fitness system, ODMWA benefit examinations, mine health and safety representatives and committees under the MHSA, explosives, winding and lifting plant, ventilation, rescue, and the Mine Health and Safety Inspectorate reporting.
10. Office and professional services. Facilities Regulations, ergonomics and display screen work, electrical certificates of compliance, fire and evacuation, contact centre night work and acoustic exposure, first aid ratios, lone working and travel, psychosocial hazards.
11. Petrochemical and fuel retail. Major Hazard Installation Regulations in full where thresholds are met, flammable and hazardous chemical agent controls, hot work and confined space permits, electrical zoning and intrinsically safe equipment, dangerous goods transport, forecourt and tank farm emergency plans, liquefied petroleum gas practitioner registration, fire protection, static and grounding, environmental spill controls.
12. Retail and wholesale. Stacking and storage, forklift and pallet handling, racking inspections, loading dock traffic management, cold room and heat exposure, security and robbery exposure, professional driving permits for delivery fleets, food handling where food is sold, fire and evacuation for public spaces.
13. Security services. PSIRA registration and grades, firearm competency and Firearms Control Act compliance where armed, cash in transit vehicle and route controls, night work and fatigue, violence and post incident support, canine unit controls, control room ergonomics, professional driving permits, lone posting emergency procedures.
14. Telecommunications and tower work. Working at height and fall protection in full, tower rescue plans, radio frequency exposure controls, electrical safety and certificates of compliance, confined space in manholes and data centre plant, lifting for antenna work, remote site emergency response, professional driving permits, construction overlay where towers are built.
15. Transport and logistics. National Road Traffic Act in full for fleets, professional driving permits and dangerous goods where carried, driver fatigue management, vehicle inspection and maintenance registers, warehousing stacking and forklift controls, rail safety critical fitness under SANS 3000-4 and the Railway Safety Regulator Act, port and aviation ground handling regimes where they apply, loading and securing of loads.
16. Utilities and energy. Electrical Machinery and Installation Regulations in full for generation and distribution, switching and isolation procedures, working at height on lines and structures, confined space in water and wastewater, chlorine and chemical dosing controls, renewable installation construction overlay, arc flash controls, public safety near assets, environmental authorisations.
17. Waste management. NEM Waste Act licences and manifests, hazardous and healthcare risk waste handling, biological agent exposure and immunisation, landfill gas and confined space, mobile plant and reversing vehicle traffic management, needle stick and sharps controls, dust and silica at transfer stations, professional driving permits for collection fleets, environmental monitoring.

---

## 7. DATA MODEL EXTENSION

7.1 New tables, all under Row Level Security, all with the same grant discipline as the kernel (revoke from public, grant by role, service context for the engine).
1. hsf_section: the fifteen sections of Section 4, ordered, with description.
2. hsf_element: every element of Section 4 and Section 6, with section, name, duty in plain words, instrument and provision references (many to many through hsf_element_instrument), evidence type, responsible appointment, review interval, retention period, universal flag.
3. hsf_element_industry: which elements apply to which industry and subindustry, with the overlay note.
4. hsf_appointment_type: every statutory appointment with its instrument, competence requirement and industry applicability.
5. hsf_training_requirement: per job role and per appointment, the competency, the unit standard or course, the renewal interval, linked to msp_job_role.
6. hsf_file: one per client engagement, with scope, sites, revision, status, compliance figure.
7. hsf_file_item: one per element per file, with status (linked_mco, uploaded, outstanding, not_applicable, expired), reason, responsible person, due date.
8. hsf_evidence: versioned evidence per item, with hash, storage reference, supplied by, supplied at, valid from, valid to, source (mco_medical, mco_training, client_upload, engine_generated).
9. hsf_appointment: the client's actual appointees per appointment type, with acceptance evidence and competence evidence.
10. hsf_person: employees in scope, matched to MCO person identifiers, holding only what the employer may lawfully hold.
11. hsf_release and hsf_signoff: the release record and every signature, mirroring msp_release.
12. hsf_audit or the shared msp_audit table with a file reference; decide in Phase 0 and record why.

7.2 Kernel extension. msp_legal_instrument gains a scope column (medical, safety, both) and the candidate instruments of Section 5 enter as pending. msp_kernel_rule gains the File rules (regime routing, construction layering, MHI thresholds, appointment ratios, retention periods). msp_industry_instrument extends to the safety scope.

7.3 Public views. hsf_public_element_library (universal elements with their legal basis, for the website) and the existing msp_public_instrument_register extended with the scope column, so the site's register shows the safety instruments once verified.

7.4 Parameters. Every threshold, ratio, interval and commercial figure is a parameter in msp_env_parameter with history, never a constant in code.

---

## 8. THE JOURNEY

8.1 Intake. The client signs in through the existing journey. The File assessment reuses the MSP assessment's company, sites, workforce and job category answers and adds the File specific questions: activities and high risk work, contractors, appointments in post, equipment classes held, chemicals held, existing certificates, and whether medicals and training were done with Care Net. Nothing the client has already told MSP FORGE is asked twice.

8.2 Generation. The engine assembles the File skeleton for the industry and subindustry: every applicable element with its legal basis, responsible appointment, evidence required and review interval. It then populates evidence: from MCO for medicals and training, from the MSP for the surveillance plan, from the intake for appointments and certificates, and marks everything else outstanding. It produces the gap report and the compliance figure.

8.3 Review. The medical section goes to the OMP queue exactly as an MSP does. The safety content goes to the safety review queue for the professional the Director names under 1.2.2. Release requires both approvals recorded, and the client's section 16(2) appointee's acceptance.

8.4 Living File. After release the File stays live: expiries raise items to expired, MCO updates flow in, change notifications open a revision, and the monthly kernel release can open a revision when an instrument moves. The client sees the compliance figure and the outstanding list on the landing page account panel.

8.5 Output. The File as a dual branded document set on the Care Net letterhead geometry (cnc-letterhead skill), the evidence index, the gap report, the audit pack export, and the on screen File with the evidence attached. Watermark and release rules follow the MSP model unless the Director rules otherwise.

---

## 9. PHASES AND GATES

Phase 1 is the first phase. Each phase ends at a gate the Director approves before the next begins. Every phase updates BUILD-STATE.md, the backup rebuild script and the manifest.

1. Phase 1, specification. Extend SPEC.md with a CNC HSF FORGE section: component manifest with anchors, the data model of Section 7, the element library as a table with every row, the open confirmation items (signing professional, commercial model, MCO contract, retention decisions). Gate: Director approval of the specification.
2. Phase 2, element library and instrument verification. Load hsf_section, hsf_element, hsf_element_industry, hsf_appointment_type, hsf_training_requirement. Enter the Section 5 candidates as pending and verify them three ways, in batches per industry, with the batch record the SOP requires. Gate: every element has at least one verified instrument or is explicitly marked as awaiting one.
3. Phase 3, kernel and rules. Regime routing, construction layering, MHI thresholds, appointment ratios, retention periods as kernel rules. Monthly audit agent extended to the safety scope. Gate: rules tested against the seventeen overlays with a fixture per industry.
4. Phase 4, intake and generation. The File assessment, the skeleton generator, the gap report and compliance figure, the document factory templates. Gate: a complete File generated for a fictitious company in each of the seventeen industries, reviewed against the element library, with no element missing and no instrument cited that is not verified.
5. Phase 5, MCO linking. Begins only when the MCO interface contract is in hand. Adapter, person matching, medical and training evidence flow, expiry handling. Gate: evidence from MCO appears in a File for a test client without any client upload, and a revoked or expired record flips its item.
6. Phase 6, review and release. Dual queue, signatures, release, revision, audit pack export. Gate: release impossible without both approvals, proven at the database layer.
7. Phase 7, site and journey. The Build your File page on the shared shell, the account panel items, the public element library and the extended register, audited to Lighthouse 100 on every category, mobile and desktop, with no dash or hyphen in copy and no price published.

---

## 10. ACCEPTANCE CRITERIA

1. Every element in Section 4 and every overlay item in Section 6 exists as a row in hsf_element with a legal basis, or is recorded as awaiting verification with the candidate instrument named.
2. No File cites an instrument that has not passed the three checks.
3. A File for each of the seventeen industries generates end to end from a fixture, and a reviewer can trace every item to its element, its instrument and its evidence.
4. Medicals and training done with Care Net appear in the File from MCO without client upload, once the MCO contract is in place; before that, the adapter fixture proves the path and the build state says the integration is pending.
5. Release is impossible without the recorded approvals, at the database layer.
6. Every evidence item is versioned and hashed; nothing is deleted; every action is audited.
7. The File's public pages meet the same standards as the MSP pages: shared shell, Lighthouse 100, house register, no prices, sales executives.
8. The backup rebuild script, the manifest, the SOP and the build state are current at every gate.
9. Nothing in this system determines individual fitness, certifies competence, or adjudicates a legal question. The engine assembles and flags; named people decide and sign.

---

## 11. OPEN CONFIRMATION ITEMS AT ISSUE

| Item | Question | Owner |
| --- | --- | --- |
| HSF-1 | Who signs safety content for Care Net, in what registered capacity, and who signs for construction Files | Director |
| HSF-2 | Commercial model for the File: free to build like the Plan, or otherwise; parameters only, no published price | Director |
| HSF-3 | MCO interface contract for medicals and training records, and the person identifier to match on | Director and MCO owner |
| HSF-4 | Whether hsf_audit is its own table or the shared msp_audit with a file reference | Build, Phase 1 |
| HSF-5 | Retention decisions where an instrument sets none | OMP and Director |
| HSF-6 | Which of the Section 5 candidates are out of scope for release 1.0 of the File | Director |

End of prompt.
