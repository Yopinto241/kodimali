# KODIMALI Sherehe na Matukio — hali ya sasa

## Dhamira

Events ni module maalumu ndani ya marketplace ileile ya KODIMALI. Inafuata category discovery, stored location preferences, hierarchy filters, sorting na navigation zinazotumiwa na Nyumba, Magari, Ofisi na Kumbi. Mteja anaweza kuvinjari bila kuingia, kuona vifaa na wataalamu halisi, kuomba huduma moja au kukusanya huduma kadhaa kupitia **Panga Tukio**.

Hakuna AI Advisor, chatbot au dodoso refu kwenye customer website na Customer Mobile App. Tables na records za Advisor zimeachwa kwenye database kwa compatibility na historia; hazionekani kwa mteja.

## Safari ya mteja

### 1. Kuingia Events

Website `/events` na Customer Mobile huonyesha hero fupi, search/filter za marketplace, category tiles na listings mapema. Login haihitajiki kwa browsing na location si sharti.

### 2. Kuchagua eneo

Hierarchy iliyopo hutumika:

`Mkoa → Wilaya → Kata → Eneo`

Mteja halazimishwi kuchagua location wala kufika mwisho wa hierarchy. Anaweza kuvinjari kwa default, au kuishia mkoa, wilaya, kata au eneo. Chaguo la mwisho huwa `location_id`. Website hurejesha shared browser preference; mobile hupokea shared app preference kutoka navigation ya kawaida. Events haina location onboarding yake tofauti.

`location_is_within` huwezesha region/district kurudisha listings za descendants. Professional anayehudumia parent area anaweza kupatikana ndani ya child area yake.

### 3. Categories

Website husoma `event_equipment_categories`; haitengenezi duplicate taxonomy. Category tiles huchuja catalog mara moja huku location ikibaki. Tile ya Wataalamu hubadilisha catalog kwenda professional services. Mobile hutengeneza category chips kutoka category IDs zinazorudishwa na public equipment search.

### 4. Public catalog

Equipment hutumia `search_public_event_equipment`. Inaonyesha published + verified records pekee na huheshimu location, price, date range na allocations.

Professional services hutumia `search_public_event_services`. Inaonyesha offerings za providers waliothibitishwa na huheshimu service areas, unavailability na confirmed/held bookings.

Bila tarehe, listings muhimu zinaonekana lakini UI haidai kuwa availability ya muda fulani imehakikishwa.

### 5. Booking moja

Equipment/service detail inaweza kufunguliwa bila login. Wakati wa kutuma request, authentication inahitajika. `create_individual_event_booking` huunda event plan nyepesi na plan item moja, kisha provider huendelea na approval, quotation na agreement zilizopo.

Equipment huomba period na quantity. Professional huomba period/duration. Server bado hufanya validation; UI rahisi haiondoi overlap na inventory checks.

### 6. Panga Tukio

Panga Tukio ni option tofauti kwenye route `/events/plan`; hailazimishi wala kuchelewesha mtu anayevinjari catalog. Huomba taarifa za lazima tu:

- aina ya tukio;
- jina la hiari;
- tarehe/muda;
- location;
- vifaa, quantities na wataalamu halisi.

Guest count, budget, venue status, accessibility questionnaire na weather questionnaire hazipo kwenye customer flow. Kwa compatibility ya schema, plan hutumwa na internal attendance placeholder ya `1`; hii si claim ya idadi ya wageni na haionyeshwi kwa mteja.

Mteja huchagua vifaa na professional offerings halisi zilizochapishwa kwenye portal ya Events, hubadilisha quantities, kisha anatuma. `create_event_plan` huunda draft. `add_event_plan_item` huongeza selected equipment/offerings. `request_event_quote` hutuma ombi moja la quotation kwa mpango wenye providers wengi. Existing notifications, provider confirmation, quote revisions na agreements zimehifadhiwa.

## Usalama wa booking

- Public catalog huonyesha verified/published data tu.
- Equipment allocation hutumia transaction/advisory locks, quantity na overlapping ranges.
- Service booking hukagua provider unavailability na overlapping bookings.
- Availability hukaguliwa tena provider anapothibitisha.
- Quotation ina revisions na expiry.
- Agreement flow imehifadhiwa.
- Baada ya quotation kukubaliwa na agreement kuthibitishwa, plan huingia `payment_pending`. Mteja hulipa deposit iliyokokotolewa na server kupitia SonicPesa; inventory na huduma huthibitishwa tu baada ya provider kuthibitisha malipo kupitia webhook au status check.
- `event_payments_enabled` ni kill switch ya dharura. Kiasi cha deposit hutoka `event_payment_deposit_percent` (default 30%); client haiwezi kutuma au kubadilisha kiasi kinachotozwa.
- Balance ya Events hutumia order tofauti na deposit, huku `event_payment_obligations` ikihifadhi audit trail ya deposit/balance.

## Manage App na Supabase

Owner huongeza kifaa kwenye Events workspace na huchagua eneo kupitia hierarchy ileile ya `locations`. App huhifadhi `location_id` pamoja na public label kwenye `event_equipment_items`, hukandamiza picha kuwa JPEG, kisha huiweka kwenye private `listing-media` path ya account hiyo. Record huanza kama pending/draft; haiwezi kuonekana public mpaka admin aithibitishe na kuichapisha.

Mtaalamu hujisajili kwenye `event_service_profiles`, huchagua eneo la kwanza kwenye `event_service_areas`, na anaweza kuongeza maeneo mengine baadaye. Portfolio image hutumia pipeline ileile ya compression/storage. Baada ya profile kuthibitishwa, offerings mpya bado husubiri admin kuzichapisha kwenye coordinator workspace.

Coordinator/admin workspace ina hatua tofauti za kuthibitisha equipment, kuthibitisha professional profile na kuchapisha service offering. Public RPCs husoma verified + published records tu; kwa hiyo website na Customer Mobile App hupokea catalog ileile moja kwa moja kutoka Supabase bila duplicate data.

## Files muhimu

- `apps/web/src/components/events-marketplace.tsx`
- `apps/web/src/components/events-public-catalog.tsx`
- `apps/web/src/components/event-location-fields.tsx`
- `apps/customer_mobile/lib/features/events/events_marketplace_screen.dart`
- `apps/customer_mobile/lib/features/events/event_location_picker.dart`
- `apps/customer_mobile/lib/core/data/customer_public_repository.dart`
- `apps/manage_mobile/lib/features/events/presentation/events_provider_workspace_screen.dart`
- `apps/manage_mobile/lib/features/events/presentation/event_coordinator_screen.dart`
- `supabase/migrations/20261025150000_event_location_hierarchy_search.sql`
- `supabase/migrations/20261025213000_unified_sonicpesa_checkout.sql`
- `supabase/functions/create-platform-payment/index.ts`
- `supabase/functions/check-platform-payment/index.ts`
- `supabase/functions/sonicpesa-payment-webhook/index.ts`

## Limitations

- Package selection ya website bado hutumia published selection list iliyo kwenye page; cart ya cross-device haipo.
- Draft recovery hutegemea saved event plans baada ya plan kuundwa; local anonymous cart haijahifadhiwa.
- Delivery fee/radius hutegemea provider configuration na quotation; UI haibuni gharama.
- Live confirmation bado hutegemea SonicPesa kutuma webhook kwenye deployed endpoint; polling ya app/web ni fallback salama.
