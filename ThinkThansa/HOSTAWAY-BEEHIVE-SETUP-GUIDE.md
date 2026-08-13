# CNC Implementation Guide — Hostaway Setup for the ThinkThansa BeeHive

**Document ID:** CNC-TT-HOSTAWAY-001
**Version:** 1.0
**Date:** 13 August 2026
**Author:** Care Net Consultants (prepared for Barteldt)
**Entity:** The Think Tank SA ("ThinkThansa") — BeeHive Apartment, High Riding Country Estate, Somerset West
**Standard:** CNC Implementation Guide Standard v1.0.0 (all 12 sections)

---

## URGENT FIXES FIRST — errors currently in the draft listing

Before anything else, correct these five items in the existing draft. Each one either blocks publishing or will actively cost bookings:

| # | Problem in current draft | Why it matters | Fix |
|---|---|---|---|
| 1 | **Map pin is in Brooklyn, New York.** The Address tab shows the pin on the Williamsburg Bridge because "Barteld" was typed into the Address field and never geocoded. | Every channel (Airbnb, Booking.com, Vrbo) places the listing where the pin is. Guests would be shown a New York apartment. Listing cannot go live like this. | Use the **"Enter your address"** search box (top-left of the Address tab), type `50 High Riding Drive, Somerset West, 7135, South Africa`, and select the Google suggestion. The pin must land on High Riding Country Estate. Then correct the fields per Section 7.2. |
| 2 | **State = "Sir Lowry's Pass".** Sir Lowry's Pass is a neighbouring suburb, not a province. | Channels validate province/state; Booking.com will reject or mis-region the listing. | Set State to **Western Cape**. |
| 3 | **Check-in time start = 11:00pm, check-out = 9:00am.** | An 11pm earliest check-in means channels tell guests they may not arrive before 23:00 — this reads as an error and kills conversions. | Check-in start **3:00pm**, check-in end **9:00pm**, check-out **10:00am** (see 7.6). |
| 4 | **Red banner: "Please fill the details or mark the listing as suitable for children/infants."** | Hostaway blocks a complete channel sync until child/infant suitability is set. | In Booking settings → guest suitability, mark **not suitable for children under 12 and infants** (broadcast equipment, open staircase, quiet-hours recording environment) and state the reason in House Rules (see 7.6). |
| 5 | **Room type = "Private room"** while Bathroom type = "Private" and the description sells a self-contained open-plan apartment. | "Private room" drops the listing out of Airbnb's "entire place" filter — the filter most travellers use — and suppresses nightly rate. | If guests get the whole upstairs apartment with their own bathroom and kitchenette (they do, per the description), set Room type = **Entire home/apartment**. The shared element (studio downstairs) is an add-on service, not shared living space. |

---

## Section 1: Software/Platform Explainer

### 1.1 What is Hostaway?

Hostaway is a property management platform for short-term rentals. You build one "master listing" for the BeeHive inside Hostaway, and Hostaway pushes that listing — photos, description, pricing, calendar, house rules — out to the booking channels (Airbnb, Booking.com, Vrbo). When a guest books on any channel, the booking flows back into Hostaway, which instantly closes those dates on all the other channels so you can never be double-booked. It also gives you one shared inbox for all guest messages regardless of which site the guest booked on.

### 1.2 How does it work?

Think of Hostaway as the single source of truth. You never edit the Airbnb listing on Airbnb or the Booking.com listing on Booking.com — you edit the master listing in Hostaway and it syncs outward. Three mechanics matter:

1. **The listing** — everything in the "Create new listing" screen you are on now. Each tab feeds specific fields on each channel.
2. **The channel connection** — the "Channel connections" tab links the master listing to your channel accounts. Until a channel is connected, the listing is a draft ("Channels: 0 of 3, Live: 0 of 3" in your header).
3. **The calendar and pricing sync** — one calendar, one price table, distributed everywhere. A "markup" can be added per channel (e.g. +15% on Booking.com to absorb its higher commission).

An **API** (a direct machine-to-machine connection between Hostaway and each channel) does the syncing — this is why field validation matters: a channel will silently reject a listing with an invalid province or missing suitability flags.

### 1.3 What does the interface look like?

The "Create new listing" screen has a header strip (DRAFT badge, channel counts, location, type, guests, bedrooms, owner) and below it a grid of tabs in five columns: **Basic info, Address, Media, Amenities, Price & fees** on row one; **Additional info & Policies, Booking settings, Channel specific, Owner Contact and Invoicing, Attachment** on row two; then **Custom fields, Bed types, Bathroom types, License info, Financial settings**; then **Payment accounts, Guest portal, Channel connections**. The active tab is highlighted dark. The green **Save** button is top-right — Hostaway does not autosave; save after every tab.

### 1.4 How difficult is the setup?

| Task | Difficulty (1–5) | Who |
|---|---|---|
| Filling listing tabs (this guide) | Level 2 — follow steps carefully | Barteldt |
| Photo upload and ordering | Level 1 | Barteldt |
| Channel connections (Airbnb/Booking.com/Vrbo OAuth) | Level 3 — some technical knowledge | Barteldt, following Section 7.13 exactly |
| Make.com automations (Section 8) | Level 4 — developer skills | CNC/AutoHive automation resource |

No task in the go-live path exceeds Level 3, so Barteldt can complete go-live alone; Section 8 automations can follow later without blocking launch.

### 1.5 What does it cost?

Hostaway is sold as a per-property annual subscription, priced by quote (it is not published on their site). The cost lives in **Settings → Billing** in your Hostaway dashboard — record the plan name and per-unit fee there into the Custom fields tab (7.11) so the number is never lost. Channel commissions are separate: Airbnb ~3% host fee (split-fee model), Booking.com ~15%, Vrbo ~8% — these come off payouts, not from Hostaway.

### 1.6 Alternatives and why Hostaway

Guesty (heavier, enterprise-priced), Lodgify (website-first, weaker channel manager), and Uplisting (good but thinner guest-portal/upsell features) were the realistic alternatives. Hostaway was chosen because the BeeHive's model — a room night plus a **paid studio add-on** — needs Hostaway's Guest Portal upsells and custom fields, and because one platform must serve all three target channels from day one.

### 1.7 Glossary

- **Master listing** — the single Hostaway record that feeds all channels.
- **Channel** — a booking site (Airbnb, Booking.com, Vrbo).
- **Markup** — a per-channel % added to your base rate to absorb that channel's commission.
- **Lead time** — minimum days between booking and arrival (yours is 1 day, deliberately, for studio-handover coordination).
- **Instant bookable** — guest can book without your approval. Yours is "No" for launch.
- **Guest Portal** — the branded web page guests get after booking (directions, house manual, upsells like studio hours).
- **iCal** — a shareable calendar feed; used to show BeeHive bookings inside the studio's own booking calendar.
- **Geocoding** — turning a typed address into a map pin. This is what failed in the current draft.

---

## Section 2: Strategic Alignment

The BeeHive converts dead space above the ThinkThansa podcast studio into a second revenue line and a customer-acquisition channel for the studio itself. It aligns with:

- **Project Nexus 2.0 automation targets** — the booking-to-invoice-to-CRM flow (Section 8) is built on the existing CNC Make.com + Xero + AutoHive CRM stack; no new middleware.
- **The 5-Year Scaling Plan (R45M → R93.3M)** — accommodation revenue is incremental and near-zero marginal cost; more importantly, every guest who books studio time becomes a ThinkThansa content client, feeding the services pipeline.
- **The Hive brand family** — AutoHive (bee icon, honey gold) and the BeeHive share the hexagon/hive identity; the listing copy and Guest Portal must visibly carry it (Section 7 brand spec).

One number to watch: **studio attach rate** — the % of stays that also book studio hours. That is the strategic KPI, not occupancy alone (Section 12).

---

## Section 3: Parallel Timeline

| Week | Hostaway track | Parallel CNC activity | Dependency notes |
|---|---|---|---|
| Week 1: 13–19 Aug 2026 | Fix draft errors; complete all listing tabs; photo shoot | Studio operating normally — schedule shoot around recordings | Photo shoot blocks Media tab; Media tab blocks channel publish |
| Week 2: 20–26 Aug 2026 | Photos live; pricing set; connect Airbnb first; test booking | AutoHive CRM pipeline stage for "BeeHive guest" created | Airbnb connection blocks first live test |
| Week 3: 27 Aug–2 Sep 2026 | Connect Booking.com + Vrbo; Guest Portal branded; go live all channels | Make.com scenarios built (reservation → Xero, → CRM) | Automations depend on live webhook data from a real test booking |
| Week 4: 3–9 Sep 2026 | First-guest readiness; review-request templates; monitor | Studio add-on booking workflow rehearsed with operator | Nothing downstream blocked |

---

## Section 4: Role Assignment Matrix

| Task | Owner | Deliverable | Date | Depends on | Blocks |
|---|---|---|---|---|---|
| Fix the 5 urgent draft errors | Barteldt | Address geocoded to High Riding; times, room type, suitability corrected; saved | 14 Aug 2026 | Nothing | Everything |
| Complete tabs 7.1–7.12 per this guide | Barteldt | All tabs saved, no red validation banners | 15 Aug 2026 | Urgent fixes | Channel connect |
| Photo shoot (apartment + studio) | Barteldt (arrange) | ≥25 photos per the shot list in 7.3 | 18 Aug 2026 | Studio schedule | Media tab |
| Upload + order photos | Barteldt | Media tab complete, hero image set | 19 Aug 2026 | Photo shoot | Channel publish |
| Confirm studio operator name + handover SOP | Barteldt | Operator named in Custom fields; cleaning/handover SOP agreed | 15 Aug 2026 | Nothing | Guest Portal content |
| Connect Airbnb channel | Barteldt | Listing live on Airbnb, test reservation completed | 21 Aug 2026 | All tabs + media | Booking.com/Vrbo connect |
| Connect Booking.com + Vrbo | Barteldt | Live on 3 of 3 channels | 28 Aug 2026 | Airbnb test passed | Full revenue |
| Build Make.com automations (Section 8) | CNC/AutoHive automation resource (assigned by Barteldt by 20 Aug) | Reservation → Xero invoice + CRM contact scenarios active | 2 Sep 2026 | One real test booking | Reporting |

---

## Section 5: Day-by-Day Operational Plan (first two weeks)

| Day | Person | Task | Deliverable / proof | Handoff |
|---|---|---|---|---|
| Thu 14 Aug | Barteldt | Urgent fixes 1–5 (top of this guide) | Map pin on High Riding; header banner gone | None |
| Fri 15 Aug | Barteldt | Tabs 7.1, 7.2, 7.4 (Basic info, Address, Amenities); confirm studio operator name | Tabs saved; operator named | Operator receives handover SOP draft |
| Sat 16 Aug | Barteldt | Tabs 7.5–7.7 (Price & fees, Additional info & Policies, Booking settings); draft House Rules from 7.6 | Tabs saved | None |
| Mon 18 Aug | Barteldt | Photo shoot per 7.3 shot list | ≥25 usable photos in a shared folder | Folder link to self for upload |
| Tue 19 Aug | Barteldt | Upload/order photos; tabs 7.8–7.12 (Bed types, Bathroom types, Custom fields, Financial, Guest Portal) | Media complete; DRAFT badge ready to publish | None |
| Wed 20 Aug | Barteldt | Assign automation resource for Section 8; brief them with this guide | Named person confirmed | Automation resource receives guide |
| Thu 21 Aug | Barteldt | Connect Airbnb (7.13); create a R1 test reservation; walk the full guest flow | Test reservation visible in Hostaway inbox | Test data to automation resource |
| Fri 22 Aug | Barteldt | Fix anything the test surfaced; write guest message templates in Hostaway | Templates saved | None |
| Mon 25–Tue 26 Aug | Barteldt | Guest Portal branding + house manual content (7.12) | Portal preview matches brand spec | Operator reviews studio add-on copy |
| Wed 27–Thu 28 Aug | Barteldt | Connect Booking.com and Vrbo with +17.65% / +8.7% markups (7.5) | 3 of 3 channels live | None |

---

## Section 6: Training Requirements

| Who | Learns | Trainer | Duration | Method | Competency check |
|---|---|---|---|---|---|
| Studio operator | Hostaway mobile app: viewing arrivals, marking cleans done, guest chat | Barteldt | 1 hour | Live walkthrough on the operator's phone | Operator finds tomorrow's arrival and sends a test message unaided |
| Barteldt | Channel connection flows | Self-guided | 2 hours | Hostaway Help Centre articles for each channel + Section 7.13 | Airbnb test booking completes end-to-end |
| Studio operator | Inspection/offboarding SOP: the studio is walk-in, walk-out — the operator's only two touchpoints are a pre-shoot equipment inspection (state check, signed off with the guest) and post-shoot offboarding (same checklist in reverse) plus apartment turnover | Barteldt | 1 hour | Written one-page SOP with the equipment checklist + one dry run | Dry-run inspection + offboarding + turnover done in under 90 minutes |

Rule applied: the operator's daily workflow must never exceed 5 clicks — arrivals list → today → guest name → message/clean-status. No listing-editing rights for the operator.

---

## Section 7: Platform Configuration (Step-by-Step)

> Work top-left to bottom-right through the tab grid. Click **Save** after every tab. If Save produces a red field outline, the message names the offending field — fix and re-save.

### Brand spec used throughout this section

- **Voice:** confident, maker-to-maker, short declarative sentences. Lead with the studio, not the bed. Pattern sentence (keep it — it is the brand's best line): *"Shoot late, sleep ten steps away, edit the next morning."*
- **Naming:** always "The BeeHive" (capital B, capital H, one word), "The Think Tank SA" in full on first mention, "the studio" after.
- **Palette (Hive family):** Think Tank crimson-pink (from the hexagon lightbulb-brain icon in Canva — design "Think Tank SA hexagon service icon 2"; sample the exact hex from that file before Guest Portal setup), honey gold `#F5A623`, deep navy `#0A1F44`, teal `#009688`, white. Type: headings Montserrat, body Arial (CNC standard).
- **Motif:** hexagon. Use the hexagon icon as the Guest Portal logo and as a watermark on the photo cover if one is composited.

### 7.1 Basic info

1. **External Listing Name:** replace the current text with **`The BeeHive · Stay Above a Real Podcast Studio`** (46 characters — Airbnb truncates at 50). Expected result: header strip still shows DRAFT with the new name after Save. If a channel later rejects the "·", fall back to a hyphen.
2. **Tags:** add `thinkthansa`, `beehive`, `somerset-west`, `studio-stay`. Tags are internal only — they never reach guests.
3. **Description:** paste the brand-voice version below (your current draft is 90% there; this tightens it and fixes "facing a TV facing it"):

   > Sleep above a real broadcast studio. The BeeHive is an open-plan apartment upstairs at The Think Tank SA's podcast studio in High Riding Country Estate, Somerset West: queen bed facing the TV, lit dressing mirror, garment rail and steamer, blackout curtains, fast uncapped fibre, and a kitchenette with air-fryer, microwave, fridge and proper coffee.
   >
   > One flight down: the coffee bar, and a three-camera podcast and video studio with treated sound and solar backup that holds through load-shedding. **Every night booked includes a full studio day** — and the studio is walk-in, walk-out: everything is set up and ready to record. The operator runs a quick equipment inspection with you before your shoot, then the space is yours; they offboard you on the way out. Shoot late, sleep ten steps away, edit the next morning.
   >
   > 45 minutes from Cape Town International. Estate security, free parking on site.

4. **Person capacity:** 2. **Property type:** Apartment. **Room type:** **Entire home/apartment** (urgent fix #5). **Bedrooms:** 1. **Beds:** 1. **Bathrooms:** 1. **Bathroom type:** Private. **Guest bathrooms:** leave 1 only if there is genuinely a second guest-accessible toilet downstairs; otherwise clear it to 0 — overstating bathrooms is the #1 source of bad reviews.

### 7.2 Address

1. In **"Enter your address"** type `50 High Riding Drive, Somerset West` and pick the Google suggestion. Expected result: the map re-centres to Somerset West and the pin sits on the estate. If Google cannot find house-level, pick the street-level result and drag the pin onto the correct building.
2. **Address:** `50 High Riding Drive, High Riding Country Estate` (replace "Barteld"). **Public address:** `High Riding Country Estate, Somerset West` (this is what guests see before booking — estate-level is deliberate). **Country:** South Africa. **State:** `Western Cape` (urgent fix #2). **City:** Somerset West. **Street:** 50 High Riding Drive. **Zip:** 7135.
3. **Timezone name:** `Africa/Johannesburg`. If the field stays greyed out, it auto-fills from the map pin after step 1 — re-check after Save.
4. **Show exact location in Vrbo/HomeAway:** set **No** (estate security prefers gate-level directions in the Guest Portal, not a public exact pin).

### 7.3 Media

Shot list (minimum 25 photos, landscape, 4:3, no filters — natural light, brand accent items in gold/navy where possible):

1–3. **Hero candidates:** the one image that says "bed + studio" — e.g. the queen bed with a framed view toward the studio stairwell, or a split-lit shot of the apartment with studio glow below. The hero decides the click-through rate; shoot ten options.
4–10. Apartment: bed both angles, dressing mirror lit, garment rail/steamer, kitchenette (air-fryer visible), coffee setup, blackout curtains drawn vs open, workspace.
11–18. Studio: three-camera floor wide shot, host chair POV, control/edit position, coffee bar, acoustic treatment close-up, solar/inverter (guests genuinely care — caption it "keeps recording through load-shedding").
19–25. Estate + exterior: entrance, parking, gate, mountain views, evening exterior.

Upload in that order; Hostaway's first image is the channel hero. Caption every photo in brand voice ("Edit desk. Fibre is uncapped.").

### 7.4 Amenities

Tick everything true — channels filter hard on amenities. Non-negotiables for this listing: Wireless internet / fast wifi, Dedicated workspace, Kitchenette (fridge, microwave, coffee machine), Iron/steamer, Hair dryer if present, Heating (winter Somerset West is cold), Free parking on premises, Private entrance, Smoke alarm + CO alarm (install before go-live if missing — Airbnb flags listings without them), Backup power / generator (list under "Other" if no explicit option). Do NOT tick pool/gym unless estate facilities are contractually guest-accessible.

### 7.5 Price & fees — priced off the ThinkThansa studio rate card

**The product on the channels is the 1-Night Sleepover package** (1 studio day + 1 night, R4,999 excl. VAT). A guest booking 1 night on Airbnb is buying that package; a guest booking N nights is buying N nights + N studio days. The other rate-card products map as follows:

| Rate-card product | Rate (excl. VAT) | On the channels? |
|---|---|---|
| Full Day (8h studio, no stay) | R3,999 | No — studio-diary product only. It still blocks the Hostaway calendar via iCal (Section 8). |
| **1-Night Sleepover** | **R4,999** | **Yes — this IS the nightly rate.** |
| 2-Day Sleepover (2 studio days + 1 night) | R8,999 | No — direct/quote only (channels cannot sell 2 studio days against 1 night). Offer it as a Guest Portal upgrade after booking. |
| Midweek Special (3 studio days + 2 nights) | R12,999 | No — direct/quote only; ~R1,000 cheaper than the per-night equivalent, so keep it direct. |
| Weekend Special (Fri 17:00–Sun 17:00) | R9,999 | Effectively yes: 2 weekend nights at the standard nightly rate ≈ R9,998, so channel pricing already matches — no special setup needed. |
| Special Shoot (first hour free, then R999/h) | R999/h | No — studio-diary product between bookings. |

**Step 1 — VAT gross-up.** The rate card is excl. VAT; consumer channels must show VAT-inclusive prices. R4,999 × 1.15 = **R5,749 incl. VAT**. This is the **base rate** you enter in Hostaway. (If the entity is not VAT-registered, use R4,999 as the base and scale every channel price below by ÷1.15.)

**Step 2 — commission gross-up per channel.** Yes, the fee must absorb each channel's commission — but a markup equal to the commission % under-recovers, because commission is charged on the *marked-up* price. The correct markup is `commission ÷ (1 − commission)`:

| Channel | Commission | Hostaway markup to enter | Guest sees / night | You net after commission |
|---|---|---|---|---|
| Airbnb (split fee) | ~3% | **+3.1%** | R5,927 | R5,749 |
| Vrbo | ~8% | **+8.7%** | R6,249 | R5,749 |
| Booking.com | ~15% | **+17.65%** | R6,764 | R5,749 |
| Direct / quote page | 0% | — | R5,749 | R5,749 |

Sanity check after connecting each channel: open the live listing, divide the displayed nightly price by (1 − commission), and confirm it lands back on R5,749. If Airbnb shows a ~15.5% "host-only fee" instead of the 3% split fee (Hostaway API listings are sometimes moved to host-only pricing), the markup becomes **+18.3%** — check which fee model the connected account is on before trusting the 3.1%.

1. **Base rate:** R5,749 (from Step 1).
2. **Cleaning fee:** R0 — the package price already includes the operator's equipment inspection, offboarding and turnover. Adding a cleaning fee on top double-charges what the rate card presents as included.
3. **Extra person fee:** none (capacity is 2).
4. **Security deposit:** R1,500 flat — the apartment sits above broadcast equipment; a modest deposit filters party bookings without hurting conversion.
5. **Weekly/monthly discounts: OFF.** The rate card has no long-stay economics — every night carries a studio day. Multi-night value seekers belong on the direct Midweek Special, offered via the Guest Portal after booking (never in the listing copy — steering guests off-platform pre-booking violates Airbnb/Booking.com policy).

### 7.6 Additional info & Policies

1. **Check-out time:** 10:00am. **Check-in time start:** 3:00pm. **Check-in time end:** 9:00pm (urgent fix #3). If the studio needs same-day turnover slack, keep check-in at 4:00pm rather than moving check-out earlier.
2. **Airbnb check-in instructions (category):** select **Smart lock** or **Lockbox** — whichever is installed; if neither, install a lockbox before go-live so 9pm arrivals never need the operator.
3. **House rules** (paste):
   > The BeeHive sits above a working broadcast studio. Recording happens downstairs — noise travels both ways, so: no parties or events, quiet hours 22:00–07:00, shoes off on the studio stairs during sessions. No smoking anywhere (treated acoustic surfaces absorb smoke permanently). The studio is walk-in, walk-out: access opens after the pre-shoot equipment inspection with the operator and closes at offboarding — do not move, re-patch or re-rig equipment; everything is pre-configured, and the offboarding inspection checks it against the pre-shoot state. Not suitable for children under 12 or infants: open staircase and broadcast equipment. Estate rules apply: 40 km/h, guests must be registered at the gate.
4. **Square meters:** 60 (already set). **Language:** English. **Wi-fi username/password:** fill both — they print onto the Guest Portal and Airbnb's wifi card; guests uploading podcast footage will judge the whole stay on this working first try.
5. **Cleaning instruction:** keep "Onboarding and Offboarding with the Podcasting Studio Operator", and add the operator's name and phone once confirmed (Section 4).
6. **Guest suitability / children flags:** mark not suitable for children and infants, with the staircase/equipment reason (urgent fix #4 — this clears the red banner).
7. **Cancellation policy:** Moderate (full refund to 5 days out). Strict punishes the spontaneous creator bookings this listing is designed to attract.

### 7.7 Booking settings

**Instant bookable: No** is correct for launch — every stay may include studio coordination. Revisit after 10 stays; Airbnb ranks instant-book listings higher. **Lead times:** keep 1 day on all three channels and Airbnb advance notice "At least 1 day" (already set, consistent — good). Leave "requests without advance notice" unticked.

### 7.8 Bed types

Bedroom 1: **1 × Queen bed**. Nothing else. This tab feeds the "1 queen bed" line on Airbnb — if left empty, Airbnb shows "1 bed" generically.

### 7.9 Bathroom types

1 × Full bathroom, private (shower — per the description "the bathroom and shower" downstairs; if the guest bathroom is downstairs by the coffee bar, say so honestly in the description: "bathroom one flight down" — misrepresenting this is the single likeliest bad-review trigger, so check this detail before publishing).

### 7.10 Channel specific

Set Booking.com room name to "Apartment" default mapping; add the channel markups from the 7.5 table here (or under channel connection settings depending on account version): **Booking.com +17.65%, Vrbo +8.7%, Airbnb +3.1%** — so every channel nets the same R5,749 sleepover rate after commission.

### 7.11 Custom fields

Create four fields (internal): `studio_operator_name_phone`, `studio_hourly_rate_ZAR`, `studio_booking_link`, `hostaway_plan_cost` (from 1.5). These merge into message templates — e.g. the pre-arrival template pulls `studio_booking_link`.

### 7.12 Guest portal

This is where the ThinkThansa brand lives after booking:

1. Upload the hexagon lightbulb-brain icon (export PNG from Canva design "Think Tank SA hexagon service icon 2") as the portal logo.
2. Set portal accent colour to the Think Tank crimson-pink sampled from that icon; if the portal only takes one colour and legibility suffers, use deep navy `#0A1F44` with the icon carrying the crimson.
3. House manual sections: Getting in (gate + lockbox), Wifi (auto-filled), The studio ("walk in, walk out — everything is pre-configured; your operator meets you for a short equipment inspection before you shoot and offboards you after; nothing gets re-rigged in between", plus rates and the operator's name), Coffee bar, Load-shedding ("you won't notice — solar holds the studio and the apartment essentials"), Check-out (10:00, three steps max).
4. **Upsell:** the base night already includes a studio day, so the portal sells **upgrades**: "2-Day Sleepover upgrade" (rate-card difference R4,000 excl. VAT over the sleepover night), "Extra studio hours — R999/h excl. VAT", and the Midweek Special for the next visit. This is the highest-leverage config on the whole platform for this business.

### 7.13 Channel connections (last — only after every tab above is saved and media is up)

1. Airbnb first: Channel connections → Airbnb → Connect → log into the Airbnb account → import/map → publish. Expected result: header shows "Channels: 1 of 3, Live: 1 of 3". If mapping fails on "suitability", revisit 7.6 step 6.
2. Make a R1-adjusted test reservation from a friend's account; verify it lands in the Hostaway inbox, the calendar blocks, and the Guest Portal link arrives.
3. Booking.com, then Vrbo, each with their markup. Booking.com will ask to verify the address by mail or call — this is why urgent fix #1 had to happen first.

---

## Section 8: Integration Architecture — iCal is the backbone

The studio diary and the accommodation calendar sell the **same physical space** (a Full Day studio booking makes a sleepover impossible, and every sleepover consumes a studio day). So the non-negotiable integration is a **two-way iCal sync** between Hostaway and the studio booking calendar:

```
STUDIO BOOKING CALENDAR (Full Day / Special Shoot diary)
        │  export iCal URL                    ▲  import Hostaway iCal URL
        ▼                                     │
HOSTAWAY master calendar ── blocks nights when the studio is sold ── blocks studio days when a night is sold
        ▲
        │ channel API sync (real-time)
Airbnb / Booking.com / Vrbo
```

**Setup (Level 2):**
1. In Hostaway: Listing → Calendar → **Export iCal** — copy the URL and add it as a subscribed/imported calendar in the studio booking system. A confirmed sleepover now blocks the studio diary for that day.
2. From the studio booking system: copy its iCal export URL and add it in Hostaway under Listing → Calendar → **Import iCal**. A Full Day studio booking now blocks that night on all three channels.
3. Expected result: create a dummy studio booking; within the refresh window the Hostaway calendar shows the date blocked. If it never appears, the studio system's iCal URL is private/expired — regenerate it.

**iCal limitation you must design around:** iCal is polling, not real-time — Hostaway refreshes imported feeds roughly every 30–60 minutes, and channels add their own delay. In that window a double-booking is possible. Three settings already in this guide are the mitigation: **Instant bookable = No** (7.7), **1-day lead time** (7.7), and the operator checking tomorrow's arrivals daily (Section 6). Never relax all three at once while iCal is the bridge.

**Second layer (optional, Level 4, after go-live):** Hostaway webhooks → Make.com → Xero invoice per reservation, AutoHive CRM contact on the "BeeHive guest" pipeline, and the pre-arrival operator email. Credentials: Hostaway API key + webhook secret (Settings → API); Xero, CRM and Outlook connections already exist in the CNC Make.com stack. Data format: JSON per reservation event. Build only after one real test booking exists (Section 5, 21 Aug).

---

## Section 9: Tracking, Analytics, and Monitoring

Channel bookings happen on the channels' own sites, so most pixel-level tracking is **not applicable at launch** — Airbnb/Booking.com/Vrbo do not allow your tags on their pages. Applicable now:

| Platform | Owner | What / where | Events | Maintainer |
|---|---|---|---|---|
| Google Business Profile | ThinkThansa GBP account | "The Think Tank SA — Podcast Studio & BeeHive Stay", pin at estate gate | Calls, direction requests | Barteldt |
| Hostaway analytics | Hostaway dashboard | Occupancy, ADR, channel mix — built in | Reservations | Barteldt |
| UTM standards | CNC standard | Every social/bio link to the listing: `utm_source=instagram&utm_medium=bio&utm_campaign=beehive-launch` | Click attribution (visible in Airbnb's own stats only as views — log links anyway for the future direct site) | Barteldt |
| AutoHive CRM attribution | AutoHive | Lead source "BeeHive stay" on every guest contact created by Make.com | Pipeline conversion to studio clients | Automation resource |

GA4, GTM, Meta Pixel, Search Console, Clarity, schema.org, sitemaps, consent banner: **Not applicable for this deployment** — there is no owned booking website yet. The moment a Hostaway direct booking site or WordPress page is stood up, this section must be revisited and the full CNC tracking standard applied.

POPIA note: guest personal data flows Hostaway → Make.com → Xero/CRM. All three are existing CNC processors; add the BeeHive guest flow to the CNC POPIA processing register.

---

## Section 10: Approval and Quality Control Workflow

- **Who reviews:** Barteldt reviews the full listing preview per channel before each "publish" click (Hostaway shows a channel preview per connection).
- **What is checked:** the 12-point checklist in Section 11, plus a phone-screen read of the description (most guests book on mobile).
- **How approved:** publish click is the approval. For copy changes after go-live, edit in Hostaway only — never on-channel.
- **Turnaround:** same day. **If a channel rejects the listing:** the rejection reason appears in Channel connections → status; fix the named field, re-sync, allow 24h. **Escalation:** Hostaway support chat (in-dashboard) if a sync stays pending >48h.

---

## Section 11: Completion Checklists

**Barteldt — go-live checklist**

| # | Task | Target | Status | Verified by |
|---|---|---|---|---|
| 1 | Urgent fixes 1–5 done, red banner gone | 14 Aug 2026 | Pending | Self — banner absent |
| 2 | Map pin on High Riding Country Estate | 14 Aug 2026 | Pending | Screenshot in project folder |
| 3 | State = Western Cape, timezone = Africa/Johannesburg | 14 Aug 2026 | Pending | Self |
| 4 | Room type = Entire home/apartment | 14 Aug 2026 | Pending | Self |
| 5 | Check-in 15:00–21:00, check-out 10:00 | 14 Aug 2026 | Pending | Self |
| 6 | Description + house rules in brand voice (7.1, 7.6) | 15 Aug 2026 | Pending | Read-aloud test |
| 7 | Operator named; SOP agreed; custom fields filled | 15 Aug 2026 | Pending | Operator confirms |
| 8 | ≥25 photos uploaded, hero chosen, captions done | 19 Aug 2026 | Pending | Self on mobile preview |
| 9 | Smoke + CO alarms installed and ticked | 19 Aug 2026 | Pending | Photo proof |
| 10 | Airbnb connected, test booking completed end-to-end | 21 Aug 2026 | Pending | Test guest confirms portal link |
| 11 | Booking.com + Vrbo live with markups | 28 Aug 2026 | Pending | Header shows 3 of 3 |
| 12 | Guest Portal branded (hexagon logo, palette, studio upsell) | 26 Aug 2026 | Pending | Portal preview screenshot |

**Studio operator — per-stay checklist:** arrivals checked daily in app; pre-shoot equipment inspection signed off with the guest; post-shoot offboarding inspection against the same checklist; apartment turnover ≤90 min; equipment discrepancies photographed and messaged to Barteldt same day (before the deposit release window closes).

---

## Section 12: Performance Measurement

| KPI | Target (first 90 days) | Measured | Where | Reviewed by |
|---|---|---|---|---|
| Occupancy | ≥45% by month 3 | Weekly | Hostaway dashboard | Barteldt, Monday review |
| ADR (average daily rate) | Net ≥R5,749 incl. VAT per night after commission (the sleepover floor — if ADR drops below this, a channel markup is wrong) | Weekly | Hostaway | Barteldt |
| **Package upgrade rate** | ≥25% of channel stays upgrade (2-Day Sleepover, extra studio hours, or a repeat direct booking) | Per stay | Guest Portal upsell log + operator log | Barteldt |
| Review score | ≥4.8 across channels | Per review | Channel dashboards via Hostaway | Barteldt |
| Response time | <1 hour, 08:00–21:00 | Weekly | Hostaway inbox stats | Barteldt |
| Guest → studio client conversion | ≥2 retainer conversations per quarter | Monthly | AutoHive CRM pipeline | Barteldt |

Decision rule: if attach rate is under 15% after 60 days, the studio offer is invisible — fix the hero photo and pre-arrival message before touching price.

---

*End of guide — CNC-TT-HOSTAWAY-001 v1.0, prepared 13 August 2026.*
