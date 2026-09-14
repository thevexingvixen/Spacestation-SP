/**
 * Spacestation SP coordinator.
 *
 * Holds SP-wide state (the list of AI crew), hooks round start so the station can be
 * auto-populated with AI crew via the SP_AUTOPOPULATE config entry, and runs the supermatter
 * watchdog that backs up the AI engineers.
 */
SUBSYSTEM_DEF(spacestation_sp)
	name = "Spacestation SP"
	ss_flags = SS_NO_FIRE
	/// Every AI crew member we have spawned this round (cleaned via COMSIG_QDELETING).
	var/list/mob/living/carbon/human/ai_crew = list()
	/// world.time of the last scripted engine setup.
	var/last_engine_setup = 0
	/// Until this world.time the emitters stay off after a watchdog scram.
	var/engine_scram_until = 0
	/// Timer id of the watchdog loop.
	var/watchdog_timer
	/// Timer id of the breach scan loop.
	var/breach_timer
	/// Outstanding supply requests from the rest of the station.
	var/list/datum/sp_supply_request/supply_requests = list()
	/// world.time of the next engine telemetry line.
	var/next_engine_log = 0
	/// TRUE once the chamber scrubbers have been switched to siphon (gas circulating through the freezers).
	var/engine_circulating = FALSE
	/// Space turfs inside the station that AI engineers should patch.
	var/list/turf/breach_turfs = list()
	/// Station areas the breach scanner walks, built once.
	var/list/area/breach_scan_areas
	/// Position in breach_scan_areas for the rolling scan.
	var/breach_scan_index = 1
	/// How many breaches the last completed sweep found.
	var/breach_count_last_sweep = 0
	/// TRUE while an AI engineer has declared the engine online (loop set up, chamber full). Drives the simulated output.
	var/engine_running = FALSE
	/// Tally of everything the AI crew have actually done this round, keyed by event name.
	var/list/event_tally = list()
	/// Timer id of the tally report loop.
	var/tally_timer

/datum/controller/subsystem/spacestation_sp/Initialize()
	SSticker.OnRoundstart(CALLBACK(src, PROC_REF(on_roundstart)))
	watchdog_timer = addtimer(CALLBACK(src, PROC_REF(engine_watchdog)), 10 SECONDS, TIMER_LOOP | TIMER_STOPPABLE)
	breach_timer = addtimer(CALLBACK(src, PROC_REF(scan_breaches)), 5 SECONDS, TIMER_LOOP | TIMER_STOPPABLE)
	tally_timer = addtimer(CALLBACK(src, PROC_REF(report_tally)), SP_TALLY_INTERVAL, TIMER_LOOP | TIMER_STOPPABLE)
	return SS_INIT_SUCCESS

/**
 * Prints what the crew have actually got done, every couple of minutes.
 *
 * Emergent behaviour is miserable to check by reading a log: you grep for a hopeful string, find
 * nothing, and cannot tell a broken behaviour from one that has simply not come up yet. A running
 * count turns that into a scoreboard — "bar.poured=0" after twenty minutes is an answer, and so is
 * "crew.door_tried=11".
 */
/datum/controller/subsystem/spacestation_sp/proc/report_tally()
	if(!length(event_tally))
		log_sp("tally: nothing yet")
		return
	var/list/parts = list()
	for(var/event in sort_list(event_tally))
		parts += "[event]=[event_tally[event]]"
	log_sp("tally: [jointext(parts, " ")]")

/**
 * Rolling hull-breach scan. Walks a slice of the station's areas on every call so a full sweep is
 * spread over roughly a minute and costs almost nothing per tick.
 */
/datum/controller/subsystem/spacestation_sp/proc/scan_breaches()
	if(isnull(breach_scan_areas))
		breach_scan_areas = sp_breach_scan_areas()
		if(!length(breach_scan_areas))
			return
	// Drop entries that are no longer holes (patched, or the area changed under us).
	for(var/turf/known as anything in breach_turfs)
		if(!sp_is_breach_turf(known))
			breach_turfs -= known

	var/areas_per_slice = max(1, round(length(breach_scan_areas) / 12))
	for(var/i in 1 to areas_per_slice)
		if(breach_scan_index > length(breach_scan_areas))
			breach_scan_index = 1
			breach_count_last_sweep = length(breach_turfs)
		var/area/scanning = breach_scan_areas[breach_scan_index++]
		if(QDELETED(scanning))
			continue
		for(var/turf/candidate as anything in scanning.get_turfs_from_all_zlevels())
			if(!isspaceturf(candidate) || (candidate in breach_turfs))
				continue
			if(sp_is_breach_turf(candidate))
				breach_turfs += candidate
		CHECK_TICK

/datum/controller/subsystem/spacestation_sp/stat_entry(msg)
	msg = "AI crew: [length(ai_crew)] | supply reqs: [length(supply_requests)] | scram: [engine_scrammed() ? "ON" : "off"] | breaches: [length(breach_turfs)] | events: [length(event_tally)]"
	return ..()

/// Counts one thing an AI crew member did. See report_tally().
/proc/sp_record(event, amount = 1)
	if(isnull(SSspacestation_sp) || !length(event))
		return
	SSspacestation_sp.event_tally[event] += amount

/// Fires once the round has started and player characters have been placed.
/datum/controller/subsystem/spacestation_sp/proc/on_roundstart()
#ifdef UNIT_TESTS
	// The unit tests run with a round going. Seventeen AI crew getting on with their shift in the background
	// — hurt by the debug helpers, operated on, walking into things — made TG's own tests nondeterministic,
	// and SP's tests build whatever they need themselves.
	return
#endif
	var/count = CONFIG_GET(number/sp_autopopulate)
	if(count <= 0)
		return
	var/spawned = sp_populate_station(count)
	log_sp("auto-populated the station with [spawned]/[count] AI crew")
	// The assistants on top, in the same tick for the same reason as the rest (sp_populate_station).
	var/assistants_min = CONFIG_GET(number/sp_assistants_min)
	var/assistants = rand(assistants_min, max(assistants_min, CONFIG_GET(number/sp_assistants_max)))
	if(assistants > 0)
		log_sp("spawned [sp_spawn_assistants(assistants)]/[assistants] AI assistants")
	var/debug_breaches = CONFIG_GET(number/sp_debug_breach_count)
	if(debug_breaches > 0)
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(sp_debug_make_breach), debug_breaches), 1 MINUTES)
	if(CONFIG_GET(flag/sp_debug_supply_request))
		addtimer(CALLBACK(src, PROC_REF(debug_supply_request)), 2 MINUTES)
	if(CONFIG_GET(flag/sp_debug_kitchen_stock))
		addtimer(CALLBACK(src, PROC_REF(debug_kitchen_stock)), 1 MINUTES)
	if(CONFIG_GET(flag/sp_debug_medical_patients))
		addtimer(CALLBACK(src, PROC_REF(debug_medical_patients)), 90 SECONDS)
	if(CONFIG_GET(flag/sp_debug_medbay_dry))
		addtimer(CALLBACK(src, PROC_REF(debug_empty_medics)), 2 MINUTES)
	if(CONFIG_GET(flag/sp_debug_antagonist))
		addtimer(CALLBACK(src, PROC_REF(debug_make_antagonist)), 90 SECONDS)

/**
 * Debug helper: empties the medics' pockets of treatment supplies, so restocking can be watched without
 * waiting for a shift's worth of patients to use them up.
 */
/datum/controller/subsystem/spacestation_sp/proc/debug_empty_medics()
	var/emptied = 0
	for(var/mob/living/carbon/human/crew as anything in ai_crew)
		if(!istype(crew.ai_controller, /datum/ai_controller/sp_crew/medical) || istype(crew.ai_controller, /datum/ai_controller/sp_crew/medical/chemist))
			continue
		for(var/obj/item/supplies as anything in crew.get_all_contents_type(/obj/item/stack/medical))
			qdel(supplies)
		for(var/obj/item/patch as anything in crew.get_all_contents_type(/obj/item/reagent_containers/applicator/patch))
			qdel(patch)
		emptied++
		log_sp("debug: emptied [crew.real_name] of treatment supplies")
	if(!emptied)
		log_sp("debug: nobody in medical to empty out")

/**
 * Debug helper: spawns one AI crew member with a thief's scheme, so the antagonist path can be watched
 * without an admin doing it by hand. Picks a random non-security job, so they have somewhere to belong
 * and are not the one meant to be catching them.
 */
/// Picking a target asks the pathfinder, which sleeps, and a timer callback is no place to do that.
/datum/controller/subsystem/spacestation_sp/proc/debug_make_antagonist()
	INVOKE_ASYNC(src, PROC_REF(do_debug_make_antagonist))

/datum/controller/subsystem/spacestation_sp/proc/do_debug_make_antagonist()
	var/list/datum/job/pool = sp_get_crew_job_pool()
	for(var/datum/job/job as anything in shuffle(pool))
		if(ispath(sp_controller_for_job(job), /datum/ai_controller/sp_crew/security))
			continue
		var/mob/living/carbon/human/crew = sp_spawn_crew_member(job, controller_type = /datum/ai_controller/sp_crew/antagonist)
		if(isnull(crew))
			continue
		// Spawned this far into the round, the job's own roundstart landmark is long gone and they land on the
		// arrival shuttle, which is a z-level of its own: everything worth stealing is on the station below, so the
		// scheme finds nothing and says so every couple of minutes forever. Put them where the crew actually are.
		if(!is_station_level(crew.z))
			for(var/mob/living/carbon/human/other as anything in shuffle(ai_crew))
				var/turf/somewhere = get_turf(other)
				if(other == crew || isnull(somewhere) || !is_station_level(somewhere.z))
					continue
				crew.forceMove(somewhere)
				log_sp("debug: moved [crew.real_name] onto the station, beside [other.real_name] in [get_area_name(somewhere)]")
				break
		var/datum/sp_scheme/scheme = sp_make_thief(crew.ai_controller)
		if(isnull(scheme))
			log_sp("debug: spawned antagonist [crew.real_name] but found nothing worth stealing")
			return
		log_sp("debug: spawned antagonist [crew.real_name] ([job.title]) with scheme: [scheme.name]")
		return
	log_sp("debug: could not spawn an antagonist")

/// Debug helper: has a random non-cargo crew member ask cargo for something.
/datum/controller/subsystem/spacestation_sp/proc/debug_supply_request()
	for(var/mob/living/carbon/human/crew as anything in shuffle(ai_crew))
		if(istype(crew.ai_controller, /datum/ai_controller/sp_crew/cargo) || crew.stat != STABLE)
			continue
		sp_request_supplies(/datum/supply_pack/organic/food, crew)
		return
	log_sp("debug: nobody available to raise a supply request")

/**
 * Debug helper: lay a set of ready-made components out on the chef's prep table.
 *
 * The kitchen is a tech tree, so a chef starting from raw stock takes a good few minutes to reach
 * anything servable. This skips to the interesting half — a cheese sandwich and a proper sandwich are
 * both craftable from what this drops — so the cook-and-serve path can be watched in one go.
 */
/datum/controller/subsystem/spacestation_sp/proc/debug_kitchen_stock()
	var/static/list/components = list(
		/obj/item/food/breadslice/plain = 4,
		/obj/item/food/cheese/wedge = 3,
		/obj/item/food/meat/steak/plain = 2,
		/obj/item/food/grown/cabbage = 2,
		/obj/item/food/grown/tomato = 2,
		/obj/item/reagent_containers/cup/bowl = 2,
	)
	for(var/mob/living/carbon/human/crew as anything in ai_crew)
		if(!istype(crew.ai_controller, /datum/ai_controller/sp_crew/chef) || crew.stat != STABLE)
			continue
		var/obj/structure/table/prep_table = crew.ai_controller.blackboard[BB_SP_PREP_TABLE] || sp_find_prep_table(crew)
		if(QDELETED(prep_table))
			break
		var/turf/table_turf = get_turf(prep_table)
		var/placed = 0
		for(var/component_type in components)
			for(var/i in 1 to components[component_type])
				new component_type(table_turf)
				placed++
		log_sp("debug: put [placed] ready-made components on [crew.real_name]'s prep table")
		return
	log_sp("debug: no chef to stock a prep table for")

/**
 * Debug helper: hurt four crew members, one of each sort of patient medbay has to handle — a cut arm
 * and a burned leg for the medkit, one bad enough to want the cryo tubes, and a broken arm for the
 * operating table. Random wounds are ruled out so each case stays what it says it is.
 */
/datum/controller/subsystem/spacestation_sp/proc/debug_medical_patients()
	var/list/mob/living/carbon/human/candidates = list()
	for(var/mob/living/carbon/human/crew as anything in shuffle(ai_crew))
		if(crew.stat != STABLE || istype(crew.ai_controller, /datum/ai_controller/sp_crew/medical))
			continue
		candidates += crew
		if(length(candidates) >= 4)
			break
	if(!length(candidates))
		log_sp("debug: nobody to send to medbay")
		return
	var/mob/living/carbon/human/patient = candidates[1]
	patient.apply_damage(25, BRUTE, BODY_ZONE_L_ARM, wound_bonus = CANT_WOUND)
	log_sp("debug: [patient.real_name] cut their arm (25 brute)")
	if(length(candidates) >= 2)
		patient = candidates[2]
		patient.apply_damage(25, BURN, BODY_ZONE_R_LEG, wound_bonus = CANT_WOUND)
		log_sp("debug: [patient.real_name] burned their leg (25 burn)")
	if(length(candidates) >= 3)
		patient = candidates[3]
		patient.apply_damage(40, BRUTE, BODY_ZONE_CHEST, wound_bonus = CANT_WOUND)
		patient.apply_damage(30, BURN, BODY_ZONE_CHEST, wound_bonus = CANT_WOUND)
		log_sp("debug: [patient.real_name] was badly hurt (40 brute, 30 burn)")
	if(length(candidates) >= 4)
		patient = candidates[4]
		var/datum/wound/blunt/bone/severe/fracture = new
		fracture.apply_wound(patient.get_bodypart(BODY_ZONE_L_ARM), wound_source = "a bad fall")
		log_sp("debug: [patient.real_name] broke their arm (hairline fracture)")

/// Registers a spawned AI crew member so we can track and clean it up.
/datum/controller/subsystem/spacestation_sp/proc/register_crew(mob/living/carbon/human/crew)
	ai_crew |= crew
	RegisterSignal(crew, COMSIG_QDELETING, PROC_REF(on_crew_deleted))

/datum/controller/subsystem/spacestation_sp/proc/on_crew_deleted(datum/source)
	SIGNAL_HANDLER
	ai_crew -= source

/// TRUE while the watchdog has the emitters locked off.
/datum/controller/subsystem/spacestation_sp/proc/engine_scrammed()
	return world.time < engine_scram_until

/**
 * Supermatter watchdog. AI engineers only ever perform a conservative startup, but if the crystal
 * still degrades (sabotage, atmos failure) this turns the emitters off and keeps them off for a while,
 * and has an engineer say so over the radio.
 */
/datum/controller/subsystem/spacestation_sp/proc/engine_watchdog()
	var/obj/machinery/power/supermatter_crystal/engine = GLOB.main_supermatter_engine
	if(QDELETED(engine))
		return
	var/status = engine.get_status()
	// Simulated engine: while online, feed the station SMES units as a real crystal would feed the grid.
	if(engine_running)
		if(status >= SUPERMATTER_WARNING)
			engine_running = FALSE
			log_sp("simulated engine taken offline: crystal status [status]")
		else if(!CONFIG_GET(flag/sp_engine_real_emitters))
			sp_feed_smes(CONFIG_GET(number/sp_engine_simulated_output) * 1000 * 10) // 10 s of output, in joules
	// Once-a-minute telemetry while the engine is doing anything, so headless tests can follow it.
	if((engine_running || status != SUPERMATTER_INACTIVE) && world.time >= next_engine_log)
		next_engine_log = world.time + 1 MINUTES
		var/datum/gas_mixture/air = sp_engine_chamber_air()
		log_sp("engine status [status], integrity [round(engine.get_integrity_percent(), 0.1)]%, chamber [air ? "[round(air.total_moles())] moles at [round(air.temperature)] K" : "n/a"], simulated [engine_running ? "ON" : "off"], SMES [round(sp_station_smes_charge() / 1e6)] MJ")
	// Anti-vacuum guard: a siphoned-out chamber around an energized crystal superheats in seconds.
	var/datum/gas_mixture/chamber_air = sp_engine_chamber_air()
	if(engine_circulating && chamber_air && chamber_air.total_moles() < 250)
		sp_engine_disable_circulation("chamber down to [round(chamber_air.total_moles())] moles")
	// Getting warm: pause the emitters, the loop will catch up.
	if(status == SUPERMATTER_NOTIFY && !engine_scrammed())
		if(sp_scram_engine("temperature notify, integrity [round(engine.get_integrity_percent())]%"))
			engine_scram_until = world.time + 2 MINUTES
		return
	if(engine_scrammed() || status < SUPERMATTER_WARNING)
		return
	var/turned_off = sp_scram_engine("status [status], integrity [round(engine.get_integrity_percent())]%")
	engine_scram_until = world.time + 10 MINUTES
	if(!turned_off)
		return
	for(var/mob/living/carbon/human/crew as anything in ai_crew)
		if(istype(crew.ai_controller, /datum/ai_controller/sp_crew/engineer) && crew.stat == STABLE)
			sp_crew_speak(crew, "Crystal integrity is dropping, I'm shutting the emitters down!", RADIO_CHANNEL_ENGINEERING)
			break
