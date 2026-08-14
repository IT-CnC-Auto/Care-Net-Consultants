-- CNC MSP FORGE | REG-CLS-01 v1.0.0 | Register closures from documentary verification 14/08/2026
-- Closes CR-13.10, CR-13.8, CR-12.2, CR-12.4; appends findings to CR-12.3. Subject to OMP ratification.

-- 1. Noise Exposure Regulations, 2024: confirmed gazette details and values (closes CR-13.10)

update msp_legal_instrument
   set gazette_reference = 'GN 5953, GG 52226, 6 March 2025; NIHL Regulations, 2003 repealed 18 months from publication (06/09/2026)',
       amendment_history = coalesce(amendment_history, '') || ' Confirmed 14/08/2026: published with the Physical Agents Regulations, 2024 and the Code of Practice for Audiometry with explanatory notes. The 85 dB(A) noise rating limit is retained, and a new action level of 82 dB(A) for continuous noise and 135 dB(C) for impulse noise applies where there is concomitant exposure to ototoxic chemical agents or whole body vibration. An exemption notice process under regulation 8(3) is recorded in 2025 to 2026 practice.'
 where short_name = 'Noise Exposure Regulations, 2024';

update msp_hazard
   set oel_instrument = 'Noise-Induced Hearing Loss Regulations, 2003, GN R.307, in force to 05/09/2026; from 06/09/2026 the Noise Exposure Regulations, 2024 (GN 5953, GG 52226) retain the 85 dB(A) noise rating limit and add an action level of 82 dB(A) continuous and 135 dB(C) impulse where ototoxic chemical or whole body vibration co exposure exists'
 where code = 'A';

update msp_kernel_rule
   set description = 'From 06/09/2026 noise citations swap from the NIHL Regulations, 2003 to the Noise Exposure Regulations, 2024. The 85 dB(A) noise rating limit carries over unchanged; the 2024 Regulations add an 82 dB(A) continuous and 135 dB(C) impulse action level for co exposure with ototoxic chemical agents or whole body vibration, which tightens surveillance triggers and never loosens them. The Code of Practice for Audiometry published with the 2024 Regulations governs audiometric method from the transition date.'
 where rule_code = 'RULE-NOISE-TRANSITION';

update msp_confirmation_item
   set description = description || ' Resolved 14/08/2026: the Noise Exposure Regulations, 2024 (GN 5953, GG 52226, 6 March 2025) retain the 85 dB(A) noise rating limit and add an 82 dB(A) continuous and 135 dB(C) impulse action level for ototoxic or vibration co exposure. Hazard A citation, transition rule, and audiometry code references updated.',
       status = 'resolved',
       resolution = 'NER 2024 values confirmed from the gazetted text and legal commentaries; 85 dB(A) retained, 82 dB(A) and 135 dB(C) co exposure action level added; kernel updated.',
       resolved_by = 'Claude Code build agent, documentary verification, subject to OMP ratification',
       resolved_on = '2026-08-14'
 where item_code = 'CR-13.10';

-- 2. PrDP medical provision (closes CR-13.8)

update msp_legal_instrument
   set full_citation = 'National Road Traffic Act 93 of 1996, Chapter 13 professional driving permits, read with the National Road Traffic Regulations, 2000 (GNR 225 of 17 March 2000), regulations 115 to 117: regulation 115 sets the categories of drivers requiring a professional driving permit, and regulation 117(b) disqualifies an applicant who is not medically fit, evidenced by the prescribed medical certificate form completed by a registered health practitioner.'
 where short_name = 'NRTA PrDP medical';

update msp_confirmation_item
   set description = description || ' Resolved 14/08/2026: the PrDP medical requirement sits in the National Road Traffic Regulations, 2000 (GNR 225 of 17 March 2000), regulations 115 to 117, with regulation 117(b) as the medical fitness disqualification and the prescribed medical certificate form as the evidence instrument.',
       status = 'resolved',
       resolution = 'NRTR 2000 regulations 115 to 117 confirmed from the published regulation text, the official medical certificate form, and the official PrDP service description.',
       resolved_by = 'Claude Code build agent, documentary verification, subject to OMP ratification',
       resolved_on = '2026-08-14'
 where item_code = 'CR-13.8';

-- 3. COIDA circular instructions (closes CR-12.2)

update msp_confirmation_item
   set description = description || ' Resolved 14/08/2026: Circular Instruction 171 (determination of permanent disablement from noise induced hearing loss, 2001) and Circular Instruction 172 (post traumatic stress disorder, in effect 1 April 2003) verified from the full instruction texts. The occupational disease series is recorded as CI 173 mesothelioma, CI 174 occupational lung cancer, CI 175 byssinosis, CI 176 occupational asthma, CI 177 irritant induced asthma, CI 178 pulmonary tuberculosis in healthcare workers, CI 179 pulmonary tuberculosis with silica dust exposure, and CI 180 work related upper limb disorders. Current version status per instruction remains subject to Compensation Fund publication practice and is checked at citation time.',
       status = 'resolved',
       resolution = 'CI 171 and CI 172 verified from full texts; CI 173 to 180 series recorded from corroborating academic and practice sources; per citation currency check retained.',
       resolved_by = 'Claude Code build agent, documentary verification, subject to OMP ratification',
       resolved_on = '2026-08-14'
 where item_code = 'CR-12.2';

-- 4. Retention periods (closes CR-12.4 with the documented per class framework)

update msp_confirmation_item
   set description = description || ' Resolved 14/08/2026 per record class: the HCA Regulations, 2021 require air monitoring records kept 30 years and investigation records 3 years, and removed the explicit medical surveillance retention clause of the 1995 Regulations; the HBA Regulations, 2022 require records including the risk assessment kept a minimum of 40 years. Care Net house policy therefore retains all medical surveillance records for 40 years, adopting the longest applicable statutory period as the floor per the tighten never loosen principle. ODMWA and MHSA record classes follow the Medical Bureau for Occupational Diseases and mine code of practice requirements where those apply.',
       status = 'resolved',
       resolution = 'HCA 30 year air monitoring and HBA 40 year record duties verified; 40 year house floor adopted for medical surveillance records pending OMP ratification.',
       resolved_by = 'Claude Code build agent, documentary verification, subject to OMP ratification',
       resolved_on = '2026-08-14'
 where item_code = 'CR-12.4';

-- 5. SANS item: append the audiometry code finding, item stays open for licensed editions

update msp_confirmation_item
   set description = description || ' Update 14/08/2026: the Code of Practice for Audiometry with explanatory notes is published with the Noise Exposure Regulations, 2024 by the Department of Employment and Labour and governs audiometric method from 06/09/2026. SANS edition numbers themselves still require licensed copies and this item stays open for them.'
 where item_code = 'CR-12.3';
