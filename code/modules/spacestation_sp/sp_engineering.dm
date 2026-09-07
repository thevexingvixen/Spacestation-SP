/**
 * Engineering helpers: power monitoring, a scripted supermatter startup that an AI engineer performs
 * once physically in the engine room, and a watchdog that shuts the emitters off if the crystal degrades.
 *
 * The startup follows the standard /tg/ nitrogen cold-loop procedure and only touches machines inside
 * the supermatter areas, matched by the names /tg/ maps give them (MetaStation, DeltaStation, Box...):
 *   1. connect and open the nitrogen canisters on the loop's connector ports
 *   2. turn on the loop pumps ("External Gas to Loop", "Gas to Chamber", "Gas to Filter", cold loop pumps)
 *      at maximum pressure; bypass / mix / atmos pumps are left alone
 *   3. turn on the filters and set the freezers to their minimum temperature
 *   4. max the SMES units and turn on solar tracking
 * Emitters are handled separately and only fire once the chamber holds enough cold nitrogen.
 */

/// TRUE when the station could use an engineer at the engine: main engine inactive, or a fair share of station APCs low.
/proc/sp_station_power_needs_work()
	var/obj/machinery/power/supermatter_crystal/engine = GLOB.main_supermatter_engine
	if(!QDELETED(engine) && !SSspacestation_sp.engine_running && engine.get_status() <= SUPERMATTER_INACTIVE && !SSspacestation_sp.engine_scrammed())
		return TRUE

	var/low = 0
	var/total = 0
	for(var/obj/machinery/power/apc/apc as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/power/apc))
		if(!is_station_level(apc.z))
			continue
		total++
		var/obj/item/stock_parts/power_store/cell = apc.cell
		if(isnull(cell) || cell.maxcharge <= 0 || (cell.charge / cell.maxcharge) < 0.3)
			low++
	return total && (low / total) > 0.2

/// Is this machine inside one of the supermatter engine areas?
/proc/sp_in_engine_area(atom/thing)
	var/area/where = get_area(thing)
	return !isnull(where) && istype(where, /area/station/engineering/supermatter)

/// Pump names (substrings) that belong to the coolant loop and should run at full pressure.
/proc/sp_is_loop_pump(obj/machinery/atmospherics/components/binary/pump/pump)
	var/static/list/wanted = list("External Gas to Loop", "Gas to Chamber", "Gas to Filter", "Cold Loop", "Coolant")
	var/static/list/forbidden = list("Bypass", "Mix", "Atmos to Loop", "Waste")
	for(var/bad in forbidden)
		if(findtext(pump.name, bad))
			return FALSE
	for(var/good in wanted)
		if(findtext(pump.name, good))
			return TRUE
	return FALSE

/**
 * Sets up the coolant loop and the power infrastructure on behalf of `engineer`.
 * Returns a one-line spoken summary. Safe to call repeatedly.
 */
/proc/sp_run_engine_setup(mob/living/engineer)
	var/canisters = 0
	var/pumps = 0
	var/filters = 0
	var/freezers = 0
	var/smes_units = 0
	var/solars = 0

	for(var/obj/machinery/portable_atmospherics/canister/nitrogen/canister as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/portable_atmospherics/canister/nitrogen))
		if(!sp_in_engine_area(canister))
			continue
		if(isnull(canister.connected_port))
			var/obj/machinery/atmospherics/components/unary/portables_connector/port = locate() in get_turf(canister)
			if(port)
				canister.connect(port)
		if(isnull(canister.connected_port))
			continue
		if(!canister.valve_open)
			canister.valve_open = TRUE
			canister.update_appearance()
		canisters++

	for(var/obj/machinery/atmospherics/components/binary/pump/pump as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/atmospherics/components/binary/pump))
		if(!sp_in_engine_area(pump) || !sp_is_loop_pump(pump))
			continue
		pump.target_pressure = MAX_OUTPUT_PRESSURE
		if(!pump.on)
			pump.set_on(TRUE)
		pump.update_appearance()
		pumps++

	for(var/obj/machinery/atmospherics/components/trinary/filter/gas_filter as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/atmospherics/components/trinary/filter))
		if(!sp_in_engine_area(gas_filter))
			continue
		if(!gas_filter.on)
			gas_filter.set_on(TRUE)
		filters++

	for(var/obj/machinery/atmospherics/components/unary/thermomachine/freezer/freezer as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/atmospherics/components/unary/thermomachine/freezer))
		if(!sp_in_engine_area(freezer))
			continue
		freezer.target_temperature = freezer.min_temperature
		if(!freezer.on)
			freezer.set_on(TRUE)
		freezer.update_appearance()
		freezers++

	// Chamber vents stop at one atmosphere by default: raise their bound so the chamber actually fills,
	// and make the chamber scrubbers siphon so the gas cycles through the filters and freezers.
	var/vents = 0
	var/scrubbers = 0
	for(var/obj/machinery/atmospherics/components/unary/vent_pump/vent as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/atmospherics/components/unary/vent_pump))
		if(!istype(get_area(vent), /area/station/engineering/supermatter/engine))
			continue
		vent.pump_direction = ATMOS_DIRECTION_RELEASING
		vent.pressure_checks = ATMOS_EXTERNAL_BOUND
		vent.external_pressure_bound = MAX_OUTPUT_PRESSURE
		if(!vent.on)
			vent.set_on(TRUE)
		vent.update_appearance()
		vents++
	// Phase A: scrub only the waste gases out of the chamber. Siphoning now would empty the chamber before
	// the loop has pressure, and a near-vacuum around an energized crystal superheats instantly.
	for(var/obj/machinery/atmospherics/components/unary/vent_scrubber/scrubber as anything in sp_engine_chamber_scrubbers())
		scrubber.filter_types = list(/datum/gas/oxygen, /datum/gas/carbon_dioxide, /datum/gas/plasma, /datum/gas/water_vapor, /datum/gas/tritium)
		if(!SSspacestation_sp.engine_circulating)
			scrubber.set_scrubbing(ATMOS_DIRECTION_SCRUBBING)
			scrubber.set_widenet(FALSE)
		if(!scrubber.on)
			scrubber.set_on(TRUE)
		scrubbers++

	for(var/obj/machinery/power/smes/smes as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/power/smes))
		if(!is_station_level(smes.z))
			continue
		smes.input_attempt = TRUE
		smes.output_attempt = TRUE
		smes.input_level = smes.input_level_max
		smes.output_level = smes.output_level_max
		smes.update_appearance()
		smes_units++

	for(var/obj/machinery/power/solar_control/control as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/power/solar_control))
		if(!is_station_level(control.z))
			continue
		if(control.track != SOLAR_TRACK_AUTO)
			control.track = SOLAR_TRACK_AUTO
		solars++

	SSspacestation_sp.last_engine_setup = world.time
	log_sp("engine loop setup by [engineer?.real_name]: [canisters] N2 canisters, [pumps] loop pumps, [filters] filters, [freezers] freezers, [vents] chamber vents, [scrubbers] chamber scrubbers, [smes_units] SMES, [solars] solar controllers")

	if(!canisters)
		return "I've set the loop up but I can't find the nitrogen for it. SMES units are on full."
	return "Coolant loop is running: [canisters] nitrogen canister[canisters == 1 ? "" : "s"] open, freezers on, SMES set to full. Waiting for the chamber to fill."

/// Gas mixture on the crystal's tile, or null.
/proc/sp_engine_chamber_air()
	var/obj/machinery/power/supermatter_crystal/engine = GLOB.main_supermatter_engine
	var/turf/open/chamber = get_turf(engine)
	if(QDELETED(engine) || !istype(chamber))
		return null
	return chamber.return_air()

/// Scrubbers inside the crystal chamber.
/proc/sp_engine_chamber_scrubbers()
	var/list/result = list()
	for(var/obj/machinery/atmospherics/components/unary/vent_scrubber/scrubber as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/atmospherics/components/unary/vent_scrubber))
		if(istype(get_area(scrubber), /area/station/engineering/supermatter/engine))
			result += scrubber
	return result

/// Nitrogen fraction of a gas mixture (0..1).
/proc/sp_nitrogen_fraction(datum/gas_mixture/air)
	var/moles = air?.total_moles()
	if(!moles)
		return 0
	return (air.moles[/datum/gas/nitrogen] || 0) / moles

/**
 * Phase B: once the chamber is full of nitrogen, switch the chamber scrubbers to siphon so the gas
 * circulates through the filters and freezers. Returns TRUE if circulation is (now) on.
 */
/proc/sp_engine_enable_circulation()
	if(SSspacestation_sp.engine_circulating)
		return TRUE
	var/datum/gas_mixture/air = sp_engine_chamber_air()
	if(isnull(air) || air.total_moles() < 600 || sp_nitrogen_fraction(air) < 0.9)
		return FALSE
	for(var/obj/machinery/atmospherics/components/unary/vent_scrubber/scrubber as anything in sp_engine_chamber_scrubbers())
		scrubber.set_scrubbing(ATMOS_DIRECTION_SIPHONING)
		scrubber.set_widenet(TRUE)
		if(!scrubber.on)
			scrubber.set_on(TRUE)
	SSspacestation_sp.engine_circulating = TRUE
	log_sp("engine circulation enabled (chamber [round(air.total_moles())] moles at [round(air.temperature)] K)")
	return TRUE

/// Anti-vacuum guard: if the chamber is being emptied, stop siphoning until it refills.
/proc/sp_engine_disable_circulation(reason)
	if(!SSspacestation_sp.engine_circulating)
		return
	for(var/obj/machinery/atmospherics/components/unary/vent_scrubber/scrubber as anything in sp_engine_chamber_scrubbers())
		scrubber.set_scrubbing(ATMOS_DIRECTION_SCRUBBING)
		scrubber.set_widenet(FALSE)
	SSspacestation_sp.engine_circulating = FALSE
	log_sp("engine circulation disabled ([reason])")

/// TRUE when the chamber holds plenty of cold, circulating nitrogen so the emitters are safe.
/proc/sp_engine_chamber_ready()
	if(!SSspacestation_sp.engine_circulating)
		return FALSE
	var/datum/gas_mixture/air = sp_engine_chamber_air()
	if(isnull(air))
		return FALSE
	if(air.total_moles() < 600 || air.temperature > 200)
		return FALSE
	return sp_nitrogen_fraction(air) >= 0.9

/**
 * Turns on up to `max_emitters` welded, powered emitters in the engine areas, but only when the chamber
 * is ready and the watchdog has not scrammed the engine. Returns a spoken summary, or null if nothing happened.
 */
/proc/sp_start_emitters(mob/living/engineer, max_emitters = 2)
	if(SSspacestation_sp.engine_scrammed())
		return "Not touching the emitters, the crystal needs to cool down first."
	var/datum/gas_mixture/air = sp_engine_chamber_air()
	if(!CONFIG_GET(flag/sp_engine_real_emitters))
		// Simulated engine: once the loop is set up and the chamber is full of nitrogen, declare it online.
		if(SSspacestation_sp.engine_running)
			return null
		if(isnull(air) || air.total_moles() < 400 || sp_nitrogen_fraction(air) < 0.9)
			log_sp("engine not brought online: chamber [air ? "[round(air.total_moles())] moles, N2 [round(sp_nitrogen_fraction(air) * 100)]%" : "n/a"]")
			return "Chamber isn't full yet, giving the loop more time."
		SSspacestation_sp.engine_running = TRUE
		log_sp("engine brought online (simulated output) by [engineer?.real_name]: chamber [round(air.total_moles())] moles, N2 [round(sp_nitrogen_fraction(air) * 100)]%")
		return "Engine is online and feeding the SMES. Lights should stay on."
	var/circulation_started = !SSspacestation_sp.engine_circulating && sp_engine_enable_circulation()
	if(!sp_engine_chamber_ready())
		var/why = isnull(air) ? "no engine chamber" : "[round(air.total_moles())] moles at [round(air.temperature)] K, N2 [round(sp_nitrogen_fraction(air) * 100)]%, circulation [SSspacestation_sp.engine_circulating ? "on" : "off"]"
		log_sp("emitters not started: chamber not ready ([why])")
		if(circulation_started)
			return "Chamber's full of nitrogen, I've started circulating it through the freezers. Emitters once it's cold."
		return "Chamber isn't ready yet, giving the loop more time."

	var/started = 0
	var/already = 0
	for(var/obj/machinery/power/emitter/emitter as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/power/emitter))
		if(!sp_in_engine_area(emitter) || !emitter.welded || isnull(emitter.powernet))
			continue
		if(emitter.active)
			already++
			continue
		if(started + already >= max_emitters)
			break
		emitter.active = TRUE
		emitter.shot_number = 0
		emitter.fire_delay = emitter.maximum_fire_delay
		emitter.update_appearance()
		SEND_SIGNAL(emitter, COMSIG_EMITTER_MACHINE_SET_ON, TRUE)
		log_game("[emitter] turned ON by AI engineer [key_name(engineer)] in [AREACOORD(emitter)]")
		started++
	log_sp("emitters: [started] started, [already] already running (chamber [round(air.total_moles())] moles, [round(air.temperature)] K)")
	if(!started && !already)
		return "No emitter I can switch on here."
	if(!started)
		return null
	return "Emitters are on, the engine should be producing power soon."

/// Total charge (joules) across station SMES units.
/proc/sp_station_smes_charge()
	var/total = 0
	for(var/obj/machinery/power/smes/smes as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/power/smes))
		if(is_station_level(smes.z))
			total += smes.charge
	return total

/// Splits `joules` of simulated engine output across the station SMES units (engine room units first).
/proc/sp_feed_smes(joules)
	if(joules <= 0)
		return 0
	var/list/targets = list()
	var/list/fallback = list()
	for(var/obj/machinery/power/smes/smes as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/power/smes))
		if(!is_station_level(smes.z))
			continue
		fallback += smes
		if(istype(get_area(smes), /area/station/engineering/engine_smes))
			targets += smes
	if(!length(targets))
		targets = fallback
	if(!length(targets))
		return 0
	var/given = 0
	var/share = joules / length(targets)
	for(var/obj/machinery/power/smes/smes as anything in targets)
		given += smes.adjust_charge(share)
		smes.charge = smes.total_charge()
	return given

/// Turns off every emitter in the engine areas. Used by the watchdog.
/proc/sp_scram_engine(reason)
	var/count = 0
	for(var/obj/machinery/power/emitter/emitter as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/power/emitter))
		if(!sp_in_engine_area(emitter) || !emitter.active)
			continue
		emitter.active = FALSE
		emitter.update_appearance()
		SEND_SIGNAL(emitter, COMSIG_EMITTER_MACHINE_SET_ON, FALSE)
		count++
	log_sp("engine scram ([reason]): [count] emitters turned off")
	return count
