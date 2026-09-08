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

/datum/controller/subsystem/spacestation_sp/Initialize()
	SSticker.OnRoundstart(CALLBACK(src, PROC_REF(on_roundstart)))
	watchdog_timer = addtimer(CALLBACK(src, PROC_REF(engine_watchdog)), 10 SECONDS, TIMER_LOOP | TIMER_STOPPABLE)
	breach_timer = addtimer(CALLBACK(src, PROC_REF(scan_breaches)), 5 SECONDS, TIMER_LOOP | TIMER_STOPPABLE)
	return SS_INIT_SUCCESS

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
	msg = "AI crew: [length(ai_crew)] | supply reqs: [length(supply_requests)] | scram: [engine_scrammed() ? "ON" : "off"] | breaches: [length(breach_turfs)]"
	return ..()

/// Fires once the round has started and player characters have been placed.
/datum/controller/subsystem/spacestation_sp/proc/on_roundstart()
	var/count = CONFIG_GET(number/sp_autopopulate)
	if(count <= 0)
		return
	var/spawned = sp_populate_station(count)
	log_sp("auto-populated the station with [spawned]/[count] AI crew")
	var/debug_breaches = CONFIG_GET(number/sp_debug_breach_count)
	if(debug_breaches > 0)
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(sp_debug_make_breach), debug_breaches), 1 MINUTES)
	if(CONFIG_GET(flag/sp_debug_supply_request))
		addtimer(CALLBACK(src, PROC_REF(debug_supply_request)), 2 MINUTES)

/// Debug helper: has a random non-cargo crew member ask cargo for something.
/datum/controller/subsystem/spacestation_sp/proc/debug_supply_request()
	for(var/mob/living/carbon/human/crew as anything in shuffle(ai_crew))
		if(istype(crew.ai_controller, /datum/ai_controller/sp_crew/cargo) || crew.stat != STABLE)
			continue
		sp_request_supplies(/datum/supply_pack/organic/food, crew)
		return
	log_sp("debug: nobody available to raise a supply request")

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
