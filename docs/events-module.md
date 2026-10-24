# KODIMALI Events — jinsi mfumo unavyofanya kazi

Hati hii inaeleza hali ya sasa ya sehemu ya **Sherehe na Matukio** kwenye website, mobile customer app, Manage app na Supabase.

## Njia kuu za mteja

Mteja ana njia tatu:

1. **Kukodisha kifaa kimoja** — anatafuta kifaa, anaweka tarehe, eneo na idadi, kisha anatuma ombi kwa mmiliki.
2. **Kuhifadhi mtaalamu mmoja** — anatafuta DJ, mpiga picha, mpambaji au mtoa huduma mwingine na kutuma ombi la muda maalumu.
3. **Kupanga tukio kamili** — anachagua aina ya tukio, eneo, tarehe, vifaa na wataalamu; mfumo unatengeneza mpango mmoja na ombi la quotation.

`Event Advisor` (kwa Kiswahili, **Mshauri wa Tukio**) ni njia ya kusaidia mteja ambaye hajui aanzie wapi. Anachagua mfumo wa tukio na kutoa maelezo muhimu. Mfumo huunda mapendekezo yanayoelezeka; haubuni bei wala kudai kuwa mtoa huduma yupo bila ukaguzi.

## Eneo linavyofanya kazi

Eneo haliandikwi kama maandishi huru. UI hutumia mpangilio huu:

`Mkoa → Wilaya → Kata → Eneo`

- Mkoa na wilaya zinahitajika wakati wa kuunda mpango.
- Kata na eneo dogo ni za hiari ikiwa taarifa hizo hazipo au mteja hataki kwenda chini zaidi.
- Chaguo la mwisho lililo sahihi huhifadhiwa kama `location_id` kwenye `event_plans`.
- Website husoma eneo lililohifadhiwa kwenye kifaa na kulijaza kwenye fomu za Events.
- Utafutaji wa vifaa hutumia `location_is_within`: ukichagua mkoa, vifaa vya wilaya/kata/maeneo ndani ya mkoa huo vinaweza kuonekana; ukichagua kata, matokeo yanakuwa finyu zaidi.
- Mtaalamu aliyeweka eneo kubwa la huduma, kwa mfano wilaya, anaweza kupatikana na mteja aliyechagua kata ndani ya wilaya hiyo.

## Catalog ya vifaa na wataalamu

Component ya website ni `EventsPublicCatalog`.

Vichujio ni:

- jina au maelezo;
- aina ya kifaa au aina ya mtaalamu;
- mkoa, wilaya, kata na eneo;
- muda wa kuanza na kumaliza;
- bei ya chini na ya juu;
- mpangilio wa matokeo.

Vifaa hutafutwa kupitia RPC `search_public_event_equipment`. RPC hukagua publication status, verification, eneo, bei na stock iliyoshikiliwa au kuthibitishwa kwenye muda uliochaguliwa.

Wataalamu hutafutwa kupitia `search_public_event_services`. RPC hukagua verification, maeneo wanayohudumia, ratiba walizozuia na booking nyingine zilizoshikiliwa au kuthibitishwa.

## Mpango kamili wa tukio

Fomu ya “Mpango wa tukio” hufanya yafuatayo:

1. Inahakikisha mteja ameingia.
2. Inaita `create_event_plan` na kuhifadhi aina, jina, muda, `location_id`, wageni na bajeti.
3. Kila kifaa kilichochaguliwa kinaongezwa kwa `add_event_plan_item` pamoja na idadi.
4. Kila mtaalamu aliyechaguliwa huunganishwa na offering yake na kuongezwa kama plan item.
5. `request_event_quote` hubadilisha mpango kutoka draft kwenda `quote_requested`.
6. Notifications hutumwa kwa watoa huduma husika kupitia trigger ya plan item.

Mpango haukusanyi malipo moja kwa moja kwa sasa. Availability, quotation na makubaliano lazima yakamilike kwanza.

## Mshauri wa Tukio

Mshauri hutumia `event_templates` zilizoidhinishwa. Baada ya mteja kujaza tarehe, wageni, eneo, bajeti, venue status na mahitaji maalumu:

1. `create_event_plan` huunda mpango unaomilikiwa na mteja.
2. `run_event_advisor` hutumia template kutengeneza checklist na mapendekezo.
3. Mapendekezo huonyesha sababu na chanzo cha estimate.
4. Mpango unabaki kwenye akaunti ya mteja kwa hatua zinazofuata.

## Provider, owner na coordinator

- Mmiliki wa vifaa huona maombi yanayohusu vifaa vyake kwenye Manage.
- Mtoa huduma huona maombi yanayohusu offering yake.
- Provider anaweza kukubali au kukataa ombi.
- Kukubali kifaa hutumia allocation yenye time range, quantity na hold expiry.
- Kukubali huduma hutumia service booking yenye muda na travel buffer.
- Database hutumia transaction locks na overlap checks kuzuia double booking.
- Coordinator/admin mwenye ruhusa za Events anaweza kusimamia mpango, quotation na escalation.

## Quotation na makubaliano

Quotation ni revisioned: quotation mpya husupersede draft/sent ya zamani. Kila quotation ina itemized lines, subtotal, additional costs na expiry. Mteja anaweza kukubali quotation halali tu baada ya providers wanaohitajika kuthibitisha availability. Baada ya hapo mpango huenda `agreement_pending`; makubaliano yakikubaliwa booking inaweza kuthibitishwa.

## UI ya website

Mpangilio wa ukurasa sasa ni:

1. Hero fupi yenye kitendo kikuu.
2. Navigation ya sehemu, inayoweza kuscroll kwenye simu.
3. Catalog yenye tabs mbili na filters zilizogawanywa kwa majina yanayoonekana.
4. Mshauri wa Tukio kwenye panel yenye intro tofauti na fomu.
5. Aina za matukio.
6. Muhtasari wa vifaa na wataalamu waliothibitishwa.
7. Fomu ya mpango kamili yenye groups tofauti za eneo, muda, vifaa na wataalamu.

Desktop hutumia columns zenye upana unaolingana. Simu hubadilika kuwa column moja; navigation hubaki horizontal ili buttons zisibanane.

## Mambo ambayo bado hayajawashwa

- Malipo ya moja kwa moja ya Events hayajawashwa.
- Result count inaweza kuwa sifuri mpaka owners/providers wachapishe vifaa na offerings zilizothibitishwa katika eneo husika.
- GPS ya rental discovery ipo, lakini Events form kwa sasa hutumia hierarchy iliyohifadhiwa au uchaguzi wa mteja ili kuepuka kuchagua eneo lisilo sahihi kimya kimya.

## Files muhimu

- `apps/web/src/components/events-marketplace.tsx`
- `apps/web/src/components/events-public-catalog.tsx`
- `apps/web/src/components/event-advisor.tsx`
- `apps/web/src/components/event-location-fields.tsx`
- `apps/customer_mobile/lib/features/events/events_marketplace_screen.dart`
- `apps/manage_mobile/lib/features/events/events_workspace_screen.dart`
- `supabase/migrations/20261024160000_kodimali_events_foundation.sql`
- `supabase/migrations/20261024170000_event_public_catalog_individual_bookings.sql`
- `supabase/migrations/20261025150000_event_location_hierarchy_search.sql`
