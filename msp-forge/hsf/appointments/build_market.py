import json

import os
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "market.json")
R = "retrieved 24/09/2026"


def P(basis, low, high, source, as_at, read, working):
    return {"basis": basis, "low": low, "high": high, "currency": "ZAR",
            "source": source, "as_at": as_at, "read": read, "working": working}


def Q(name, critical, body, source):
    return {"name": name, "critical": critical, "body": body, "source": source}


def E(typical, options, note):
    return {"typical": typical, "options": options, "note": note}


NS = "not sourced in this pass; confirm"

# Frequently used sources
AH = "https://absolutehealth.co.za"
SS = "https://safetysupplier.co.za"
IND = "https://za.indeed.com"
SACPCMP_CAT = "https://mychs.sacpcmp.org.za/Register-Categories"
SACPCMP_FEES = "https://sacpcmp.org.za/registration/registration-fees/"
ORIC = "https://blog.oric.network/index.php/how-much-does-it-cost-to-register-a-sacpcmp-as-a-safety-officer/"

ann = "Monthly figure multiplied by 12 gives an annual basic salary, not a full cost to company; add employer costs (UIF, SDL, COIDA, benefits) separately."

A = {}

A["APP-00"] = {
    "engagement": E("duty added to an existing employee",
                    ["duty added to an existing employee"],
                    "Assigned by the CEO to a senior manager or director. Not a hire; the cost is the manager's time plus a short legal liability briefing."),
    "pricing": [
        P("course fee", 575, 595, f"{AH}/health-safety-training/16-2-workshop/", R, "snippet",
          "2 hour 16.2 workshop: R595 ex VAT in person, R575 ex VAT online, per delegate."),
    ],
    "qualifications": [
        Q("Legal liability or 16.2 workshop (short course, not a registration)", False, "Accredited training provider (no statutory registration)", f"{AH}/health-safety-training/16-2-workshop/"),
        Q("Seniority and authority to act for the CEO", True, "Employer (internal appointment)", NS),
    ],
    "notes": "No salary benchmark applies because the role is always a delegated duty. Section 16(2) of the OHS Act is the lead; confirm wording."
}

A["APP-01"] = {
    "engagement": E("permanent hire",
                    ["permanent hire", "fixed term contract", "per site or per project"],
                    "Principal contractors usually employ construction managers permanently and deploy them per project; smaller contractors use the owner or a contracts manager."),
    "pricing": [
        P("per month", 34399, 34399, f"{IND}/career/construction-manager/salaries", "2026", "snippet",
          f"Indeed national average R34,399 per month; x12 = R412,788 per year. {ann}"),
        P("annual cost to company", 180757, 1056231, "https://www.payscale.com/research/ZA/Job=Construction_Manager/Salary", "2026", "snippet",
          "PayScale average R363,785 per year; entry level average R180,757 (low); a snippet also gave senior level R1,056,231, but that senior figure may come from SalaryExpert, so confirm. Salary, not full cost to company."),
        P("annual cost to company", 919522, 919522, "https://www.salaryexpert.com/salary/job/construction-manager/south-africa", "2026", "snippet",
          "SalaryExpert (ERI) average R919,522 per year. Modelled estimate, much higher than Indeed and PayScale."),
    ],
    "qualifications": [
        Q("Registration as Professional Construction Manager (PrCM) or Construction Manager candidate", True, "SACPCMP", SACPCMP_CAT),
        Q("Construction management degree or diploma (NQF 6 to 7)", False, "Higher education institution; SAQA recognised", NS),
    ],
    "notes": "The published salary figures vary widely by source (R363k to R920k per year). Treat Indeed and PayScale as mid market and SalaryExpert as a modelled upper figure."
}

A["APP-02"] = {
    "engagement": E("permanent hire",
                    ["permanent hire", "per site or per project", "duty added to an existing employee"],
                    "Usually a site agent or senior foreman appointed in writing for the project."),
    "pricing": [
        P("per month", 27387, 39615, f"{IND}/career/site-agent/salaries", "2026", "snippet",
          f"Proxy: Indeed site agent national average R36,115 per month (x12 = R433,380). Range shown: R27,387 (one employer) to R39,615 (Cape Town). {ann}"),
    ],
    "qualifications": [
        Q("SACPCMP Construction Manager candidate or Construction Health and Safety registration (lead)", False, "SACPCMP", SACPCMP_CAT),
    ],
    "notes": "No salary data is published under the title assistant construction manager; site agent is used as the closest proxy."
}

A["APP-03"] = {
    "engagement": E("permanent hire",
                    ["permanent hire", "fixed term contract", "per site or per project", "outsourced service"],
                    "Principal contractors hire CHSOs on project contracts; smaller contractors outsource to consultancies that bill per visit or per month."),
    "pricing": [
        P("per month", 17252, 17252, f"{IND}/career/safety-officer/salaries", "Feb 2026", "snippet",
          f"Indeed safety officer (not construction specific) R17,252 per month; x12 = R207,024 per year. Figure from PRICING-RESEARCH.md row 52. {ann}"),
        P("annual cost to company", 180000, 450000, "https://firstaidfiresafety.co.za/blog/career-insight-health-and-safety-officer-salary-in-south-africa/", "undated, retrieved 24/09/2026", "snippet",
          "Training provider blog: R180,000 to R350,000 per year on average; up to R450,000 for experienced officers in high risk industries. Salary, not full cost to company."),
        P("per month", 25000, 30000, "https://jobrato.co.za/samtrac-safety-officer-salary-in-south-africa-health-safety-pay-scales-corporate-benchmarks-2026-guide/", "2026", "snippet",
          "CHSO range R25,000 to R30,000 per month (x12 = R300,000 to R360,000). Attribution to this page comes from a combined search summary; confirm. The same guide says SACPCMP registration adds a 20% to 35% premium."),
        P("per hour", 750, 750, "https://firstaidfiresafety.co.za/ohs-management-services/", "retrieved 23/09/2026", "snippet",
          "Outsourced consultancy charge out rate R750 per hour ex VAT (PRICING-RESEARCH.md row 45). x8 = R6,000 per day."),
        P("course fee", 6850, 6850, ORIC, "undated", "snippet",
          "SACPCMP first year registration (application, assessment and initial registration fees combined), about R6,850. Undated blog; confirm against the gazetted 2026/27 fees."),
    ],
    "qualifications": [
        Q("Registration as Construction Health and Safety Officer (CHSO)", True, "SACPCMP", SACPCMP_CAT),
        Q("SAMTRAC or equivalent NQF 5 OHS qualification", False, "NOSA (SAMTRAC R19,940 incl VAT classroom, https://nosa.co.za/courses/SAMTRAC/)", "https://nosa.co.za/courses/SAMTRAC/"),
        Q("SAIOSH designation such as TechSaiosh (NQF 5 plus 2 years)", False, "SAIOSH (SAQA recognised professional body)", "https://www.saiosh.co.za/page/About_membership"),
        Q("First aid level 1 or higher", False, "QCTO or HWSETA accredited provider", f"{AH}/first-aid-training-courses/first-aid-level-1/"),
    ],
    "notes": "The Construction Regulations 2014 make SACPCMP CHSO registration the norm for construction appointments; confirm the regulation number. Gazetted SACPCMP 2026/27 fees exist but could not be read (site blocked)."
}

A["APP-04"] = {
    "engagement": E("permanent hire",
                    ["permanent hire", "duty added to an existing employee", "per site or per project"],
                    "Foremen and site supervisors are appointed in writing per project, usually from existing staff."),
    "pricing": [
        P("per month", 13575, 20790, f"{IND}/career/construction-supervisor/salaries", "Feb 2026", "snippet",
          f"Indeed construction supervisor R20,790 per month (x12 = R249,480); site supervisor R13,575 per month (x12 = R162,900), from https://za.indeed.com/career/site-supervisor/salaries. {ann}"),
        P("per hour", 80, 80, "https://www.payscale.com/research/ZA/Job=Construction_Supervisor/Hourly_Rate", "2025", "snippet",
          "PayScale construction supervisor average R80 per hour; x8 = R640 per day."),
        P("course fee", 900, 900, f"{SS}/product/25-construction-supervision-1-day-r900-p-p-excl-vat-minimum-5-x-people-per-course/", R, "snippet",
          "Construction Supervision course, 1 day, R900 per person ex VAT, minimum 5 people."),
    ],
    "qualifications": [
        Q("Construction supervisor or SHE supervisor short course (SAQA unit standards)", False, "QCTO or CETA accredited provider", f"{SS}/product/25-construction-supervision-1-day-r900-p-p-excl-vat-minimum-5-x-people-per-course/"),
        Q("Trade or experience in the relevant work", True, "Employer (competence assessment)", NS),
    ],
    "notes": ""
}

A["APP-05"] = {
    "engagement": E("duty added to an existing employee",
                    ["duty added to an existing employee", "outsourced service"],
                    "Usually the safety officer or a trained supervisor; consultancies sell risk assessments per site or per day."),
    "pricing": [
        P("course fee", 825, 975, f"{AH}/health-safety-training/hazard-identification-risk-assessment-hira/", R, "snippet",
          "HIRA 1 day: R975 ex VAT in person, R825 ex VAT online."),
        P("per day", 5500, 6000, "https://accesspd.co.za/health-safety-ohs-risk-assessment", "retrieved 23/09/2026", "snippet",
          "Outsourced: AccessPD implied R5,500 per day for a risk assessment with report; Absolute Health R6,000 for a 1 day site assessment (PRICING-RESEARCH.md rows 47 and 48). Both ex VAT."),
    ],
    "qualifications": [
        Q("HIRA or risk assessment course (SAQA unit standard based)", True, "QCTO or HWSETA accredited provider", f"{AH}/health-safety-training/hazard-identification-risk-assessment-hira/"),
        Q("For construction: SACPCMP CHSO or CHSM registration where the client requires it", False, "SACPCMP", SACPCMP_CAT),
    ],
    "notes": ""
}

A["APP-06"] = {
    "engagement": E("duty added to an existing employee",
                    ["duty added to an existing employee", "outsourced service"],
                    "Usually the safety officer or a supervisor who has done the fall protection planner course; small contractors outsource the plan."),
    "pricing": [
        P("course fee", 2795, 3815, "https://gravitytraining.co.za/fall-protection-plan-development/", R, "snippet",
          "Gravity Training Fall Protection Plan Development: R3,815 incl VAT classroom, R2,795 online."),
        P("course fee", 3500, 3500, "https://www.swiftskillsacademy.com/working-at-heights-training-cape-town-saqa-229998", R, "snippet",
          "Fall protection planner, 3 days, R3,500 ex VAT. Melior Rope Access also lists R3,500 ex VAT (https://melioraccess.com/iwh-fall-arrest-training-cape-town/)."),
        P("course fee", 8500, 8500, "https://cdn.ymaws.com/www.masterbuilders.co.za/resource/resmgr/docs/training/Fall_protection_planner.pdf", "undated", "snippet",
          "Master Builders KZN Institute of Learning, 4 day course, R8,500 per person. VAT status not stated."),
    ],
    "qualifications": [
        Q("Fall protection planner course (SAQA unit standard based, working at heights)", True, "QCTO or CETA accredited provider", "https://gravitytraining.co.za/fall-protection-plan-development/"),
        Q("Fall arrest user training (SAQA 229998 is quoted by one provider)", False, "QCTO accredited provider", "https://www.swiftskillsacademy.com/working-at-heights-training-cape-town-saqa-229998"),
    ],
    "notes": "No published salary; this is a competence attached to an existing role."
}

A["APP-07"] = {
    "engagement": E("duty added to an existing employee",
                    ["duty added to an existing employee", "outsourced service"],
                    "Usually a scaffold team leader or the scaffold hire company's supervisor."),
    "pricing": [
        P("per month", 20790, 20790, f"{IND}/career/construction-supervisor/salaries", "Feb 2026", "snippet",
          f"Proxy only: construction supervisor R20,790 per month. No scaffold supervisor salary was published. {ann}"),
        P("course fee", 800, 4500, "https://coursetakers.com/south-africa/professional/health-and-safety/occupational/scaffolding", R, "snippet",
          "Scaffolding courses: FTS Training from R800 per person (https://ftssafety.co.za/safety-training/scaffold-training); Cranes Training R4,500 for 1 week (https://cranestraining.com/scaffoldingcourse.php); aggregator range R1,100 to R7,000."),
    ],
    "qualifications": [
        Q("Scaffold supervisor or erector training to SANS 10085", True, "CETA or QCTO accredited provider", "https://lopterraservices.com/hs-courses/scaffold-inspector/"),
    ],
    "notes": ""
}

A["APP-08"] = {
    "engagement": E("duty added to an existing employee",
                    ["duty added to an existing employee", "outsourced service"],
                    "An existing supervisor or safety officer who has done the inspector course; scaffold hire firms often provide inspection."),
    "pricing": [
        P("course fee", 950, 950, f"{SS}/product/10-scaffold-inspector-1-day-r950-p-p-excl-vat-minimum-5-x-people-per-course/", R, "snippet",
          "Scaffold Inspector, 1 day, R950 per person ex VAT, minimum 5."),
        P("course fee", 400, 400, "https://lopterraservices.com/hs-courses/scaffold-inspector/", R, "snippet",
          "Add on only: CETA statement of results certificate R400 ex VAT, issued 6 to 8 months later. Course fee itself not shown."),
    ],
    "qualifications": [
        Q("Scaffold inspector unit standard SAQA 263205 (inspect access scaffolding)", True, "CETA or QCTO accredited provider", "https://www.swiftskillsacademy.com/post/scaffold-inspector-course-south-africa-saqa-263205"),
    ],
    "notes": ""
}

A["APP-09"] = {
    "engagement": E("duty added to an existing employee",
                    ["duty added to an existing employee", "per site or per project"],
                    "A foreman or supervisor appointed for the excavation work."),
    "pricing": [
        P("course fee", 950, 950, f"{SS}/product/28-excavation-supervisor-1-day-r950-p-p-excl-vat-minimum-5-x-people-per-course/", R, "snippet",
          "Excavation supervisor, 1 day, R950 per person ex VAT, minimum 5. Excavation inspector course same price."),
    ],
    "qualifications": [
        Q("Excavation supervisor or inspection training", True, "Accredited training provider", f"{SS}/product/28-excavation-supervisor-1-day-r950-p-p-excl-vat-minimum-5-x-people-per-course/"),
        Q("Geotechnical or engineering input where the design requires it", False, "ECSA registered person", NS),
    ],
    "notes": ""
}

A["APP-10"] = {
    "engagement": E("per site or per project",
                    ["per site or per project", "outsourced service"],
                    "Usually supplied by the specialist demolition subcontractor."),
    "pricing": [],
    "qualifications": [
        Q("Demolition supervisor competence (no published course price found)", True, "Accredited training provider", "https://www.mysafetyshop.co.za/Products/Demolition-Work-Supervisor-Appointment"),
    ],
    "notes": "No South African price was published for a demolition supervisor course or salary. MySafetyShop lists the appointment, but the page showed no price."
}

A["APP-11"] = {
    "engagement": E("outsourced service",
                    ["outsourced service", "per site or per project"],
                    "A consulting engineer or the formwork or falsework supplier's engineer, engaged per project."),
    "pricing": [
        P("per month", 17799, 69636, f"{IND}/career/structural-engineer/salaries", "2026", "snippet",
          f"Proxy: Indeed structural engineer average R43,684 per month (x12 = R524,208); junior R17,799 per month; senior R835,630 per year (/12 = R69,636). {ann}"),
    ],
    "qualifications": [
        Q("Professional registration (Pr Eng or Pr Tech Eng) in civil or structural engineering", True, "ECSA", "https://www.ecsa.co.za/"),
    ],
    "notes": "ECSA gazetted a Guideline Scope of Services and Professional Fees on 16 May 2025 (https://www.gov.za/sites/default/files/gcis_document/202505/52691bn783.pdf) with time based fees, but the hourly rates could not be read. Consulting charge out rates remain unsourced."
}

A["APP-12"] = {
    "engagement": E("duty added to an existing employee",
                    ["duty added to an existing employee", "per site or per project"],
                    "Usually the formwork foreman or site agent."),
    "pricing": [
        P("per month", 20790, 20790, f"{IND}/career/construction-supervisor/salaries", "Feb 2026", "snippet",
          f"Proxy only: construction supervisor R20,790 per month. No temporary works supervisor data was published. {ann}"),
    ],
    "qualifications": [
        Q("Competence in formwork and support work; experience based", True, "Employer (competence assessment)", NS),
    ],
    "notes": "No role specific price or course was found."
}

A["APP-13"] = {
    "engagement": E("permanent hire",
                    ["permanent hire", "fixed term contract", "outsourced service"],
                    "Operators are employed, or supplied with the machine under plant hire (wet hire)."),
    "pricing": [
        P("per month", 14727, 17578, f"{IND}/career/plant-operator/salaries", "2026", "snippet",
          f"Indeed plant operator R17,578 per month (x12 = R210,936); excavator operator R14,727 per month (https://za.indeed.com/career/excavator-operator/salaries). {ann}"),
        P("course fee", 1600, 5000, "https://cranestraining.com/price.php", R, "snippet",
          "Operator courses: forklift R1,600 (5 days), TLB R4,500 (7 days), mobile crane R5,000 (7 to 10 days). VAT status not stated."),
    ],
    "qualifications": [
        Q("Operator certificate of competence for each machine type (SAQA unit standards)", True, "TETA or QCTO accredited provider", "https://cranestraining.com/price.php"),
        Q("Annual medical certificate of fitness", True, "Occupational medical practitioner", NS),
        Q("Driving licence where the machine uses public roads", False, "DLTC (provincial)", NS),
    ],
    "notes": ""
}

A["APP-14"] = {
    "engagement": E("duty added to an existing employee",
                    ["duty added to an existing employee", "permanent hire"],
                    "A plant foreman or supervisor appointed in writing."),
    "pricing": [
        P("per month", 20790, 20790, f"{IND}/career/construction-supervisor/salaries", "Feb 2026", "snippet",
          f"Proxy only: construction supervisor R20,790 per month. {ann}"),
    ],
    "qualifications": [
        Q("Plant supervision competence, usually a former operator", True, "Employer (competence assessment)", NS),
    ],
    "notes": "No role specific salary or course price was found."
}

A["APP-15"] = {
    "engagement": E("outsourced service",
                    ["outsourced service", "permanent hire"],
                    "Usually the registered electrical contractor's installation electrician."),
    "pricing": [
        P("per month", 17442, 22919, f"{IND}/career/electrician/salaries", "2026", "snippet",
          f"Indeed electrician R17,442 per month; industrial electrician R22,919 (https://za.indeed.com/career/industrial-electrician/salaries). x12 = R209,304 to R275,028. {ann}"),
        P("course fee", 240, 240, "https://ecasa.co.za/member-support/electrical-contractor-registration-fees-go-up-to-r240-00-per-year/", "undated", "snippet",
          "Electrical contractor registration fee R240 per year (Department of Employment and Labour). Company registration, not a course."),
    ],
    "qualifications": [
        Q("Registration as Installation Electrician or Master Installation Electrician (Wireman's Licence)", True, "Department of Employment and Labour (Chief Inspector)", "https://renkalec.com/wiremans-licence/"),
        Q("Electrician trade test (Red Seal)", True, "QCTO, NAMB trade test centre", NS),
        Q("Electrical contractor registration of the employer", True, "Department of Employment and Labour", "https://ecasa.co.za/member-support/electrical-contractor-registration-fees-go-up-to-r240-00-per-year/"),
    ],
    "notes": "The Electrical Installation Regulations are the lead; confirm the regulation numbers."
}

A["APP-16"] = {
    "engagement": E("duty added to an existing employee",
                    ["duty added to an existing employee", "outsourced service"],
                    "A competent electrician on site appointed to control temporary construction supply."),
    "pricing": [
        P("per month", 17442, 18718, f"{IND}/career/electrician/salaries", "2026", "snippet",
          f"Indeed electrician R17,442; maintenance electrician R18,718 per month. {ann}"),
    ],
    "qualifications": [
        Q("Qualified electrician (trade test)", True, "QCTO, NAMB", NS),
        Q("Installation Electrician registration where a CoC is required", False, "Department of Employment and Labour", "https://renkalec.com/wiremans-licence/"),
    ],
    "notes": ""
}

A["APP-17"] = {
    "engagement": E("outsourced service",
                    ["outsourced service", "permanent hire"],
                    "Almost always a registered Lifting Machinery Entity (LME) sending an LMI per inspection; large users sometimes employ one."),
    "pricing": [
        P("per month", 30860, 30860, f"{IND}/cmp/Lifting-Machine-Inspector/salaries", "2026", "snippet",
          f"Indeed: LMI average R30,860 per month (5 data points); x12 = R370,320. {ann}"),
        P("per month", 35000, 45000, "https://www.executiveplacements.com/Jobs/L/LIFTING-MACHINE-INSPECTOR-LMI-with-valid-ECSA-Cert-1145220-Job-Search-1-8-2025-12-58-54-PM.asp", "Aug 2025", "snippet",
          "Advert: LMI with valid ECSA certificate, R35,000 to R45,000 per month (x12 = R420,000 to R540,000)."),
        P("per day", 14250, 14250, "https://shutterlock.co.za/wp-content/uploads/2017/08/Shutterlock-loadtesting-A5-leaflet-web.pdf", "about 2017 (from file path)", "snippet",
          "Outsourced LMI daily rate including mobile test rig R14,250 per day. Likely dated; confirm."),
        P("per inspection", 800, 2500, "https://gpforklifts.co.za/forklift-load-testing-cape-town/", R, "snippet",
          "Forklift load test and inspection R800 to R2,500 per unit."),
    ],
    "qualifications": [
        Q("Registration as Lifting Machinery Inspector (LMI)", True, "ECSA", "https://verlinde.co.za/about-us/machinery-inspector/"),
        Q("Employer registered as a Lifting Machinery Entity (LME)", True, "Department of Employment and Labour (Chief Inspector)", "https://leeasa.co.za/about-leeasa/"),
    ],
    "notes": "A search snippet cites the Driven Machinery Regulations inspection intervals (6 months for lifting machines, 3 months for tackle) as a lead; confirm."
}

A["APP-18"] = {
    "engagement": E("permanent hire",
                    ["permanent hire", "duty added to an existing employee", "outsourced service"],
                    "Crane operators are employed or supplied with hired cranes; overhead crane and hoist operation is often a duty of production staff."),
    "pricing": [
        P("per month", 15239, 15239, f"{IND}/career/crane-operator/salaries", "2026", "snippet",
          f"Indeed crane operator R15,239 per month (x12 = R182,868); regional averages R5,807 to R30,825. {ann}"),
        P("course fee", 1800, 1800, f"{SS}/product/11-overhead-crane-r1-800-p-p-excl-vat/", R, "snippet",
          "Overhead crane operator course R1,800 per person ex VAT."),
        P("course fee", 5000, 5000, "https://cranestraining.com/mobile.php", R, "snippet",
          "Mobile crane course R5,000, 7 to 10 days. VAT status not stated."),
    ],
    "qualifications": [
        Q("Operator certificate for the specific lifting machine (SAQA unit standards)", True, "TETA or QCTO accredited provider", f"{SS}/product/11-overhead-crane-r1-800-p-p-excl-vat/"),
        Q("Medical certificate of fitness", True, "Occupational medical practitioner", NS),
    ],
    "notes": ""
}

A["APP-19"] = {
    "engagement": E("permanent hire",
                    ["permanent hire", "duty added to an existing employee", "outsourced service"],
                    "Usually the engineering or maintenance manager; a full time appointment where machinery exceeds the regulation thresholds."),
    "pricing": [
        P("course fee", 1530, 1530, "https://nosa.co.za/courses/gmr21-supervisor-machinery-webinar/", R, "snippet",
          "NOSA GMR 2(1) Supervisor for Machinery webinar, 1 day, R1,530."),
    ],
    "qualifications": [
        Q("Government Certificate of Competency (GCC) Factories where total machinery power exceeds 3,000 kW", True, "Department of Employment and Labour", "https://www.palucraft-gccstudy.com/post/what-is-a-gmr-2-1-appointment"),
        Q("Engineering qualification (N6, diploma or degree) plus experience below that threshold", False, "Employer, with ECSA registration where held", "https://westcoast.worksafe.org.za/the-role-and-functions-of-the-gmr21-appointee/"),
    ],
    "notes": "General Machinery Regulation 2(1) and the 3,000 kW threshold are stated by sources; treat as leads to confirm. No salary figure was published for the GMR 2(1) title."
}

A["APP-20"] = {
    "engagement": E("duty added to an existing employee",
                    ["duty added to an existing employee", "outsourced service"],
                    "The user's engineer or maintenance manager supervises; statutory inspection is outsourced to an Approved Inspection Authority (AIA)."),
    "pricing": [
        P("course fee", 37630, 40704, "https://www.saiw.co.za/saiw/welding-courses/competent-persons-training/pressure-vessels/", "2026", "snippet",
          "SAIW Competent Person (Pressure Vessels) course, 15 days, R37,630 (corporate members) to R40,704 incl VAT. The figure may come from the SAIW 2026 Competent Persons PDF; confirm."),
        P("per inspection", 12000, 12000, "https://powertooltraders.co.za/products/aia-pressure-vessel-inspection-report-certificate", R, "snippet",
          "AIA pressure vessel inspection report and certificate listed at R12,000. One retailer listing only."),
    ],
    "qualifications": [
        Q("Competent Person (CP) certification for pressure equipment", True, "SAQCC CP (administered through SAIW)", "https://www.saiw.co.za/saiw-certification/certifications/individuals/competent-person-pressure-vessels/"),
        Q("Inspections by an Approved Inspection Authority", True, "Department of Employment and Labour (accredits AIAs; SANAS accreditation)", "https://www.sgs.com/en-za/services/pressure-equipment-certification"),
    ],
    "notes": "Pressure Equipment Regulations are the lead; a snippet states a 3 yearly test for air receivers outside mines. Confirm."
}

A["APP-21"] = {
    "engagement": E("duty added to an existing employee",
                    ["duty added to an existing employee", "outsourced service"],
                    "Usually the safety officer or stores supervisor; air monitoring is outsourced to an occupational hygiene AIA."),
    "pricing": [
        P("course fee", 955, 955, "https://www.iefa.co.za/hazmat.php", R, "snippet",
          "HAZMAT awareness, 8 hours, R955 per person. Attribution from a combined search summary; confirm. No HCS specific course price found."),
    ],
    "qualifications": [
        Q("Hazardous chemical substances or HAZMAT training", True, "Accredited training provider", "https://www.saflii.org/za/legis/consol_reg/rfhcs429/"),
        Q("Occupational hygiene monitoring by an Approved Inspection Authority", False, "Department of Employment and Labour; SAIOH for hygienists", NS),
    ],
    "notes": "The Regulations for Hazardous Chemical Substances (saflii) are the lead; newer Hazardous Chemical Agents Regulations 2021 should be confirmed."
}

A["APP-22"] = {
    "engagement": E("duty added to an existing employee",
                    ["duty added to an existing employee"],
                    "A storeman or supervisor who checks ladders; no hire."),
    "pricing": [
        P("course fee", 950, 950, f"{SS}/product/19-ladder-inspector-1-day-r950-p-p-excl-vat-minimum-5-x-people-per-course/", R, "snippet",
          "Ladder Inspector, 1 day, R950 per person ex VAT, minimum 5."),
    ],
    "qualifications": [
        Q("Ladder inspection or safety short course", False, "Accredited training provider", f"{SS}/product/19-ladder-inspector-1-day-r950-p-p-excl-vat-minimum-5-x-people-per-course/"),
    ],
    "notes": ""
}

A["APP-23"] = {
    "engagement": E("duty added to an existing employee",
                    ["duty added to an existing employee"],
                    "Warehouse or stores supervisor."),
    "pricing": [
        P("course fee", 825, 825, f"{AH}/specialised-health-safety-training-courses/stacking-storage/", R, "snippet",
          "Stacking and Storage, 1 day, R825 ex VAT."),
    ],
    "qualifications": [
        Q("Stacking and storage short course", False, "Accredited training provider", f"{AH}/specialised-health-safety-training-courses/stacking-storage/"),
    ],
    "notes": ""
}

A["APP-24"] = {
    "engagement": E("duty added to an existing employee",
                    ["duty added to an existing employee"],
                    "Existing employees are trained; the statutory ratio drives how many."),
    "pricing": [
        P("course fee", 975, 975, f"{AH}/first-aid-training-courses/first-aid-level-1/", R, "snippet",
          "First Aid NQF Level 1, 2 days, R975 ex VAT."),
        P("course fee", 1815, 1815, "https://stjohn.org.za/first-aid-training-level-1/", R, "snippet",
          "St John First Aid Level 1, 2 days, R1,815. VAT status not stated."),
        P("course fee", 925, 1955, f"{AH}/first-aid-training-courses/", R, "snippet",
          "Basic Emergency First Aid Responder 2 days R925 ex VAT; Advanced Emergency First Aid Responder 5 days R1,955 ex VAT."),
    ],
    "qualifications": [
        Q("Valid first aid certificate (level 1 minimum; higher levels for high risk sites)", True, "Provider approved by the Department of Employment and Labour; HWSETA or QCTO accreditation", "https://absolutehealth.co.za/blog/department-of-labour-first-aid-training-requirements/"),
    ],
    "notes": "Sources state General Safety Regulation 3: a first aider where more than 10 employees, one per 50 employees (one per 100 in shops and offices). Lead to confirm (https://labourguide.co.za/health-and-safety/update-first-aid-and-aid-boxes)."
}

A["APP-25"] = {
    "engagement": E("outsourced service",
                    ["outsourced service", "duty added to an existing employee"],
                    "Monthly visual checks are an internal duty; annual servicing is outsourced to a SAQCC Fire registered company."),
    "pricing": [
        P("per inspection", 120, 250, "https://www.altrafire.co.za/fire-compliance-costs-in-south-africa-what-businesses-actually-pay-2026/", "June 2026", "snippet",
          "Annual SANS 1475-1 service per portable extinguisher R120 to R250 ex VAT, Gauteng. Five yearly overhaul R350 to R700 per unit."),
        P("course fee", 4450, 4450, f"{AH}/fire-fighting-training-courses/", R, "snippet",
          "Firefighting Equipment Servicing Technician (SAQCC 1475), 5 days, R4,450 ex VAT."),
    ],
    "qualifications": [
        Q("Technician registration with SAQCC Fire; company SANS 1475 permit", True, "SAQCC Fire; SABS permit", "https://www.altrafire.co.za/fire-compliance-costs-in-south-africa-what-businesses-actually-pay-2026/"),
    ],
    "notes": ""
}

A["APP-26"] = {
    "engagement": E("duty added to an existing employee",
                    ["duty added to an existing employee"],
                    "Volunteers from the workforce, trained and drilled."),
    "pricing": [
        P("course fee", 825, 1750, f"{AH}/fire-fighting-training-courses/", R, "snippet",
          "Basic firefighting 1 day R825 ex VAT; advanced firefighting 2 days R1,750 ex VAT."),
        P("course fee", 700, 850, "https://www.ddigroup.co.za/blog/basic-fire-fighting-course-prices-explained", R, "snippet",
          "Basic fire fighting R700 to R850 per delegate."),
    ],
    "qualifications": [
        Q("Basic or advanced firefighting (SAQA unit standards)", True, "QCTO or SETA accredited provider", f"{AH}/fire-fighting-training-courses/fire-fighting-1/"),
    ],
    "notes": ""
}

A["APP-27"] = {
    "engagement": E("duty added to an existing employee",
                    ["duty added to an existing employee"],
                    "Usually the safety officer, facilities manager or site manager."),
    "pricing": [
        P("course fee", 825, 825, f"{AH}/specialised-health-safety-training-courses/evacuation-planning/", R, "snippet",
          "Evacuation Planning, 1 day, R825 ex VAT."),
        P("course fee", 3950, 3950, f"{AH}/specialised-health-safety-training-courses/first-aid-fire-and-evacuation-skills-program/", R, "snippet",
          "First Aid, Fire and Evacuation Skills Program, 5 days, R3,950 ex VAT."),
    ],
    "qualifications": [
        Q("Emergency or evacuation planning course", True, "Accredited training provider", f"{AH}/specialised-health-safety-training-courses/evacuation-planning/"),
        Q("First aid and firefighting certificates", False, "Accredited training provider", NS),
    ],
    "notes": ""
}

A["APP-28"] = {
    "engagement": E("duty added to an existing employee",
                    ["duty added to an existing employee"],
                    "One warden per floor or area, drawn from existing staff."),
    "pricing": [
        P("course fee", 450, 550, "https://www.heandshedrivingschool.co.za/courses/fire-marshal-course/", R, "snippet",
          "Fire marshal or firefighting level 1 R450, level 2 R550, ex VAT, 1 day each. Attribution from a combined search summary; confirm."),
        P("course fee", 825, 825, f"{AH}/specialised-health-safety-training-courses/evacuation-planning/", R, "snippet",
          "Evacuation Planning, 1 day, R825 ex VAT."),
    ],
    "qualifications": [
        Q("Fire marshal or evacuation warden training", False, "Accredited training provider", "https://www.hretd.co.za/fem.html"),
    ],
    "notes": ""
}

A["APP-29"] = {
    "engagement": E("duty added to an existing employee",
                    ["duty added to an existing employee", "outsourced service"],
                    "Supervisors and the safety officer; serious incidents may be outsourced."),
    "pricing": [
        P("course fee", 825, 925, f"{AH}/health-safety-training/incident-investigation/", R, "snippet",
          "Incident Investigation 1 day: R825 to R925 ex VAT depending on format."),
        P("course fee", 2518.50, 3979.00, "https://safetycloud.co.za/course/incident-investigation-level-3-2/", "2026 price list", "snippet",
          "SafetyCloud (NOSA) Incident Investigation Level 3, 3 days: R2,518.50 e learning to R3,979.00 classroom; mining version R6,641.25."),
    ],
    "qualifications": [
        Q("Incident investigation course (for example ICAM or root cause methods)", True, "Accredited training provider", f"{AH}/health-safety-training/incident-investigation/"),
    ],
    "notes": ""
}

A["APP-30"] = {
    "engagement": E("duty added to an existing employee",
                    ["duty added to an existing employee", "outsourced service"],
                    "A trained supervisor; specialist contractors supply supervisors and rescue teams for major entries."),
    "pricing": [
        P("course fee", 1000, 1500, "https://www.swiftskillsacademy.com/confined-spaces-course-cape-town-saqa-15034", R, "snippet",
          "Confined space refresher R1,000 to R1,500 ex VAT. Initial course fee not shown."),
        P("course fee", 700, 4500, "https://coursetakers.com/south-africa/professional/health-and-safety/occupational/confined-space-entry", R, "snippet",
          "Aggregator range: R700 (1 day) to R4,500 (3 days, confined spaces on construction sites)."),
    ],
    "qualifications": [
        Q("Confined space entry and supervision (SAQA 15034 quoted by one provider)", True, "QCTO or SETA accredited provider", "https://www.swiftskillsacademy.com/confined-spaces-course-cape-town-saqa-15034"),
        Q("Gas testing competence and medical fitness", True, "Accredited training provider; occupational medical practitioner", NS),
    ],
    "notes": ""
}

A["APP-31"] = {
    "engagement": E("duty added to an existing employee",
                    ["duty added to an existing employee"],
                    "Tradespeople trained by the tool supplier."),
    "pricing": [],
    "qualifications": [
        Q("Explosive powered tool operator card from the manufacturer's training", True, "Tool manufacturer (for example Hilti)", "https://www.hilti.co.za/c/CLS_SERVICES/CLS_S_TRAINING/r4164921"),
    ],
    "notes": "Hilti South Africa offers operator training and a card, but no price is published. No other South African price was found."
}

A["APP-32"] = {
    "engagement": E("duty added to an existing employee",
                    ["duty added to an existing employee"],
                    "Usually the storeman who controls issue and cartridges."),
    "pricing": [],
    "qualifications": [
        Q("Operator training plus stores control procedure", False, "Tool manufacturer or accredited provider", "https://www.hilti.co.za/c/CLS_SERVICES/CLS_S_TRAINING"),
    ],
    "notes": "No published price. Cost is internal time."
}

A["APP-33"] = {
    "engagement": E("duty added to an existing employee",
                    ["duty added to an existing employee"],
                    "A supervisor issues the hot work permit; a fire watcher is assigned."),
    "pricing": [
        P("course fee", 1063.75, 1063.75, "https://safetycloud.co.za/wp-content/uploads/2025/12/safetycloud-student-course-pricelist-2026.pdf", "2026 price list", "snippet",
          "Proxy: Permit to Work workshop, 1 day, R1,063.75 (in house day rate R21,545.25). No hot work specific price found."),
    ],
    "qualifications": [
        Q("Permit to work or hot work training; fire watcher training", True, "Accredited training provider", "https://www.hretd.co.za/hw.html"),
        Q("Basic firefighting", False, "Accredited training provider", f"{AH}/fire-fighting-training-courses/fire-fighting-1/"),
    ],
    "notes": ""
}

A["APP-34"] = {
    "engagement": E("outsourced service",
                    ["outsourced service"],
                    "Asbestos work is done by a registered asbestos contractor that supplies its own supervisor."),
    "pricing": [
        P("course fee", 400, 400, "https://ecasa.co.za/wpc/wp-content/uploads/2022/08/OHS-Directive-Schedule-of-Fees-to-Register-Entities-Annexure-A.pdf", "about 2022", "snippet",
          "Department of Employment and Labour registration fee for an asbestos contractor R400 (R600 duplicate). Company registration fee, not a course."),
    ],
    "qualifications": [
        Q("Registered asbestos contractor (Type 2 or Type 3 work)", True, "Department of Employment and Labour (Chief Inspector)", "https://www.labour.gov.za/DocumentCenter/Publications/Occupational%20Health%20and%20Safety/Criteria%20for%20Contractor%20registration%20type%202%20and%203%20asbestos%20work%20(February%202023).pdf"),
        Q("Asbestos supervisor training as required by the registration criteria", True, "Accredited provider", "https://www.labour.gov.za/DocumentCenter/Publications/Occupational%20Health%20and%20Safety/Criteria%20for%20Contractor%20registration%20type%202%20and%203%20asbestos%20work%20(February%202023).pdf"),
    ],
    "notes": "The Asbestos Abatement Regulations 2020 are the lead. No South African asbestos supervisor course price or salary was found."
}

A["APP-35"] = {
    "engagement": E("duty added to an existing employee",
                    ["duty added to an existing employee", "outsourced service"],
                    "A supervisor; exposure monitoring is outsourced to an occupational hygiene AIA and medical surveillance to an occupational health practitioner."),
    "pricing": [],
    "qualifications": [
        Q("Lead awareness training, refreshed at least yearly (per the Lead Regulations)", True, "Competent trainer", "https://www.saflii.org/za/legis/consol_reg/lr2001148/"),
    ],
    "notes": "Lead Regulations 2001 are the lead. No South African price was found for lead supervisor training."
}

A["APP-36"] = {
    "engagement": E("duty added to an existing employee",
                    ["duty added to an existing employee", "outsourced service"],
                    "A supervisor controls the zone; noise surveys are outsourced to an AIA."),
    "pricing": [],
    "qualifications": [
        Q("Noise and hearing conservation awareness", False, "Accredited provider or PPE supplier", "https://www.3m.co.za/3M/en_ZA/safety-centers-of-expertise-za/center-for-hearing-conservation/train/"),
        Q("Noise surveys by an Approved Inspection Authority", True, "Department of Employment and Labour", "https://www.dashservices.co.za/noise-surveys/"),
    ],
    "notes": "The Noise Induced Hearing Loss Regulations, 2003 were repealed from 6 September 2026 and replaced by the Noise Exposure Regulations, 2024; the survey interval in the older rules is not relied on. No price was published for a noise zone controller course or for a noise survey."
}

A["APP-37"] = {
    "engagement": E("duty added to an existing employee",
                    ["duty added to an existing employee", "permanent hire", "outsourced service"],
                    "Often a radiographer, NDT technician or engineer with RPO duties; large users employ a dedicated RPO; consultants act as RPO for small users."),
    "pricing": [
        P("annual cost to company", 254415, 440335, "https://www.salaryexpert.com/salary/job/radiation-safety-officer/south-africa", "2026", "snippet",
          "SalaryExpert radiation safety officer average R353,205 per year; entry R254,415; senior R440,335. /12 = R21,201 to R36,695 per month. Modelled salary, not full cost to company."),
    ],
    "qualifications": [
        Q("RPO training and competence per SAHPRA guideline", True, "SAHPRA (Radiation Control)", "https://www.sahpra.org.za/document/rpo-competence-and-training-requirements/"),
        Q("For nuclear installations or NORM: NNR requirements", False, "National Nuclear Regulator", NS),
    ],
    "notes": "RPO course providers (Protocor, Radiation Dosimetry and Protection cc, SGS) do not publish prices."
}

A["APP-38"] = {
    "engagement": E("duty added to an existing employee",
                    ["duty added to an existing employee"],
                    "Kitchen or canteen manager, appointed as person in charge."),
    "pricing": [
        P("course fee", 249, 649, "https://ascfoodsafetytraining.com/courses/basic-food-safety-practices-for-food-handlers-course/", R, "snippet",
          "Food handler training from R249; Basic Food Hygiene Awareness R420; Basic Food Safety Practices R649 per person (online)."),
        P("course fee", 2730, 3950, "https://ascfoodsafetytraining.com/which-haccp-course-do-you-need-introduction-supervisors-or-advanced/", R, "snippet",
          "HACCP for supervisors R2,730; advanced HACCP R3,950. Attribution from a combined search summary; confirm."),
    ],
    "qualifications": [
        Q("Food safety training for persons in charge (R638 aligned)", True, "Accredited training provider", "https://ascfoodsafetytraining.com/product/food-safety-for-persons-in-charge-of-food-premises-course/"),
        Q("Certificate of Acceptability for the premises", True, "Municipal environmental health", "https://ascfoodsafetytraining.com/2026-guide-certificate-of-acceptability-for-sa-municipalities/"),
    ],
    "notes": "Regulation R638 is the lead; confirm."
}

A["APP-39"] = {
    "engagement": E("permanent hire",
                    ["permanent hire", "outsourced service"],
                    "Drivers are employed or supplied through transport contractors."),
    "pricing": [
        P("per month", 12791, 20000, f"{IND}/career/truck-driver/salaries", "2026", "snippet",
          f"Indeed truck driver R12,791 per month (x12 = R153,492); Code 14 adverts R15,000 to R20,000 per month (https://za.indeed.com/Code-14-Driver-jobs). {ann}"),
        P("course fee", 518, 518, "https://k-53.co.za/prdp", R, "snippet",
          "PrDP fees: application R324 + Afiswitch R110 + temporary permit R84 = R518; medical certificate R300 to R600 extra. Provincial fees vary."),
    ],
    "qualifications": [
        Q("Driving licence of the right code plus Professional Driving Permit (PrDP)", True, "Driving Licence Testing Centre (provincial), National Road Traffic Act", "https://www.gov.za/services/driving-licence/professional-driving-permit"),
        Q("Medical certificate for PrDP", True, "Registered medical practitioner", "https://k-53.co.za/prdp"),
        Q("Dangerous goods training for PrDP category D", False, "Accredited provider", NS),
    ],
    "notes": ""
}

A["APP-40"] = {
    "engagement": E("permanent hire",
                    ["permanent hire"],
                    "Mine managers and MHSA statutory appointees are permanent employees; legal appointments cannot be outsourced in practice."),
    "pricing": [
        P("annual cost to company", 415674, 715195, "https://www.salaryexpert.com/salary/job/mine-manager/south-africa", "2026", "snippet",
          "SalaryExpert mine manager average R574,624 per year; entry R415,674; senior R715,195; bonus about R15,228. Mine operations manager averages R944,188 (https://www.salaryexpert.com/salary/job/mine-operations-manager/south-africa)."),
    ],
    "qualifications": [
        Q("Mine Manager's Certificate of Competency", True, "Department of Mineral and Petroleum Resources, Mine Health and Safety Inspectorate", "https://www.dmr.gov.za/mine-health-and-safety/gcc-examinations/certifications?id=2635"),
        Q("Engineer's GCC (Mines and Works) for engineering appointees", True, "Department of Mineral and Petroleum Resources", "https://www.gccmineshub.com/post/gcc-mines-a-comprehensive-step-by-step-guide-to-obtaining-the-gcc-mines-in-south-africa"),
    ],
    "notes": "Mine Health and Safety Act 1996 is the lead; appointment section numbers not confirmed. Care Net's OHS Act based offering may not cover mines."
}

assert len(A) == 41, len(A)
for i in range(41):
    assert f"APP-{i:02d}" in A

doc = {
    "meta": {
        "as_at": "24/09/2026",
        "method": ("Desk research on 24/09/2026 by web search. Page fetches to payscale.com, sacpcmp.org.za and safetycloud.co.za were blocked by the "
                   "network proxy, so every figure comes from search engine snippets of the cited page (read = snippet); none were read directly. "
                   "A few figures are carried over from PRICING-RESEARCH.md (retrieved 23/09/2026). Salaries are employee pay, not consultancy charge out. "
                   "Monthly figures are converted to annual by x12 and hourly to daily by x8 where shown. Course fees are per delegate. "
                   "Where a role is a duty added to an existing employee, a course fee is given instead of a salary. Proxies are labelled in 'working'. "
                   "Regulation references are leads to confirm."),
        "status": "indicative, desk research, to be confirmed by Care Net",
    },
    "appointments": A,
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2, ensure_ascii=False)

priced = [k for k, v in A.items() if v["pricing"]]
none = [k for k, v in A.items() if not v["pricing"]]
print("priced", len(priced), "none", none)
