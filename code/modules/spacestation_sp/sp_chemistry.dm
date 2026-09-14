/**
 * Spacestation SP — chemistry.
 *
 * A medicine is a chemical reaction, like one of the bartender's cocktails, but chemistry does not let you
 * pour everything in at once. The reactions here run over time and they compete: libital is phenol, oxygen
 * and nitrogen; phenol is water, chlorine and oil; oil is fuel, carbon and hydrogen — and hydrogen that meets
 * nitrogen makes ammonia instead. So a medicine is planned as stages, each adding what the dispenser holds
 * for one reaction and letting it finish before the next goes in (sp_plan_brew), then brewed with the heater
 * holding each stage at the temperature it wants and its buffers keeping the pH in range (sp_run_brew).
 */

/// Areas the chemist works in.
/proc/sp_chem_areas()
	var/static/list/areas = list(
		/area/station/medical/chemistry,
		/area/station/medical/pharmacy,
		/area/station/medical/chem_storage,
	)
	return areas

/// Whether something is in the chemistry lab, the pharmacy or chem storage.
/proc/sp_in_chem_lab(atom/thing)
	var/area/here = get_area(thing)
	return !isnull(here) && (here.type in sp_chem_areas())

/// The plain chemistry dispenser, as opposed to the bar's taps and the debug synthesizers that share its type.
/proc/sp_is_chem_dispenser(obj/machinery/chem_dispenser/dispenser)
	return dispenser.type == /obj/machinery/chem_dispenser || istype(dispenser, /obj/machinery/chem_dispenser/fullupgrade)

/// How pure one reagent in a container is, or 0 if it is not there.
/proc/sp_reagent_purity(obj/item/reagent_containers/container, reagent_type)
	for(var/datum/reagent/reagent as anything in container?.reagents?.reagent_list)
		if(reagent.type == reagent_type)
			return reagent.purity
	return 0

// --- Planning ---------------------------------------------------------------------------------------

/// One stage of a brew: what goes in from the dispenser, and the reaction that should follow.
/datum/sp_brew_stage
	/// The reaction this stage sets off.
	var/datum/chemical_reaction/reaction
	/// What it makes, and how many units of it.
	var/product
	var/amount
	/// How many times the reaction runs; each run uses its required reagents once.
	var/runs
	/// Dispenser reagent -> units that go in for this stage.
	var/list/additions
	/// Temperature the heater holds the beaker at while it reacts.
	var/heat_to

/datum/sp_brew_stage/New(datum/chemical_reaction/reaction, product, runs, list/additions, heat_to)
	src.reaction = reaction
	src.product = product
	src.runs = runs
	src.amount = reaction.results[product] * runs
	src.additions = additions
	src.heat_to = heat_to

/// Scales a stage: every run, and so every unit going in and coming out.
/datum/sp_brew_stage/proc/scale(factor)
	runs *= factor
	amount *= factor
	for(var/reagent in additions)
		additions[reagent] *= factor

/// A medicine planned from the dispenser up: the stages in the order they have to happen.
/datum/sp_brew
	var/product
	/// Units of the medicine it makes.
	var/amount
	var/list/datum/sp_brew_stage/stages
	/// The most the beaker holds at any point during the brew.
	var/peak_volume = 0

/datum/sp_brew/New(product, list/stages)
	src.product = product
	src.stages = stages
	measure()

/// Works out how much comes out at the end, and how full the beaker gets on the way.
/datum/sp_brew/proc/measure()
	var/datum/sp_brew_stage/last = stages[length(stages)]
	amount = last.amount
	peak_volume = 0
	var/volume = 0
	for(var/datum/sp_brew_stage/stage as anything in stages)
		for(var/reagent in stage.additions)
			volume += stage.additions[reagent]
		peak_volume = max(peak_volume, volume)
		for(var/ingredient in stage.reaction.required_reagents)
			volume -= stage.reaction.required_reagents[ingredient] * stage.runs
		for(var/result in stage.reaction.results)
			volume += stage.reaction.results[result] * stage.runs
		// Some reactions make more than goes into them: nine units of the makings of basic buffer come out as ten.
		peak_volume = max(peak_volume, volume)

/datum/sp_brew/proc/scale(factor)
	for(var/datum/sp_brew_stage/stage as anything in stages)
		stage.scale(factor)
	measure()

/// Rounds every addition to the whole unit it is meant to be, now the scaling has made it one.
/datum/sp_brew/proc/round_off()
	for(var/datum/sp_brew_stage/stage as anything in stages)
		for(var/reagent in stage.additions)
			stage.additions[reagent] = round(stage.additions[reagent], 1)
		stage.runs = round(stage.runs, 0.001)
		stage.amount = round(stage.amount, 0.001)
	measure()

/**
 * The reactions that make this reagent which a chemistry dispenser could feed: a single result, no special
 * container, no catalyst to find, and not one that only goes when frozen.
 */
/proc/sp_reactions_making(product)
	var/list/datum/chemical_reaction/found = list()
	for(var/reaction_type in GLOB.chemical_reactions_list)
		var/datum/chemical_reaction/reaction = GLOB.chemical_reactions_list[reaction_type]
		if(length(reaction.results) != 1 || !(product in reaction.results))
			continue
		if(reaction.is_cold_recipe || reaction.required_container || length(reaction.required_catalysts))
			continue
		found += reaction
	return found

/// Units a second a reaction makes at this temperature, by /tg/'s own curve.
/proc/sp_reaction_rate(datum/chemical_reaction/reaction, temperature)
	if(temperature < reaction.required_temp)
		return 0
	if(temperature >= reaction.optimal_temp)
		return reaction.rate_up_lim
	var/fraction = (temperature - reaction.required_temp) / (reaction.optimal_temp - reaction.required_temp)
	return reaction.rate_up_lim * (fraction ** reaction.temp_exponent_factor)

/**
 * How warm a stage should be held. Room temperature when the reaction goes happily there; otherwise as close
 * to its best as it can get with a margin under the point where it overheats. Aiuri's best is 300 and it
 * overheats — flash, bang — at 315, so that margin is not a formality.
 */
/proc/sp_brew_temperature(datum/chemical_reaction/reaction, room_temp)
	var/margin = max(10, min(100, (reaction.overheat_temp - reaction.optimal_temp) / 2))
	var/ceiling = reaction.overheat_temp - margin
	if(room_temp < reaction.required_temp || sp_reaction_rate(reaction, room_temp) < SP_BREW_SLOW_RATE)
		return max(reaction.required_temp + 5, min(reaction.optimal_temp, ceiling))
	return min(room_temp, ceiling)

/**
 * Plans the stages that make `want` units of `product`, deepest first, onto the end of `stages`. Returns FALSE
 * if some part of it cannot be got to from what the dispenser pours.
 */
/proc/sp_plan_stages(product, want, list/base, room_temp, list/stages, list/seen, depth)
	if(depth > SP_BREW_MAX_DEPTH || (product in seen))
		return FALSE
	for(var/datum/chemical_reaction/reaction as anything in sp_reactions_making(product))
		var/runs = want / reaction.results[product]
		var/list/datum/sp_brew_stage/sub_stages = list()
		var/list/additions = list()
		var/possible = TRUE
		for(var/ingredient in reaction.required_reagents)
			var/units = reaction.required_reagents[ingredient] * runs
			if(ingredient in base)
				additions[ingredient] += units
			else if(!sp_plan_stages(ingredient, units, base, room_temp, sub_stages, seen + product, depth + 1))
				possible = FALSE
				break
		if(!possible)
			continue
		stages += sub_stages
		stages += new /datum/sp_brew_stage(reaction, product, runs, additions, sp_brew_temperature(reaction, room_temp))
		return TRUE
	return FALSE

/**
 * The first reaction, other than the one a stage is for, that the beaker's contents would satisfy at some
 * point in the brew, or null if there is none. Everything goes into one beaker and the reagent system fires
 * whatever it can, so a stage that also satisfies some other reaction might make a different medicine — or
 * smoke powder, or thermite; the dispenser pours the makings of both.
 */
/proc/sp_brew_conflict(datum/sp_brew/brew, room_temp)
	var/list/contents = list()
	for(var/datum/sp_brew_stage/stage as anything in brew.stages)
		for(var/reagent in stage.additions)
			contents[reagent] += stage.additions[reagent]
		// The heater holds each stage at its temperature; only a reaction that cools or warms itself strays far
		// from it. Allowing fifty degrees either way for every stage had water freezing into ice in phenol's.
		var/coolest = min(room_temp, stage.heat_to) - (stage.reaction.thermic_constant < 0 ? 50 : 5)
		var/warmest = max(room_temp, stage.heat_to) + (stage.reaction.thermic_constant > 0 ? 50 : 5)
		for(var/reaction_type in GLOB.chemical_reactions_list)
			var/datum/chemical_reaction/other = GLOB.chemical_reactions_list[reaction_type]
			if(other == stage.reaction || (stage.product in other.results) || other.required_container || !length(other.required_reagents))
				continue
			if(other.is_cold_recipe ? other.required_temp < coolest : other.required_temp > warmest)
				continue
			var/satisfied = TRUE
			for(var/ingredient in other.required_reagents + other.required_catalysts)
				if(contents[ingredient] <= 0.0001)
					satisfied = FALSE
					break
			if(satisfied)
				return other
		for(var/ingredient in stage.reaction.required_reagents)
			contents[ingredient] -= stage.reaction.required_reagents[ingredient] * stage.runs
			if(contents[ingredient] <= 0.0001)
				contents -= ingredient
		for(var/result in stage.reaction.results)
			contents[result] += stage.reaction.results[result] * stage.runs
	return null

/**
 * A way to make a medicine from what the dispenser pours, in the biggest batch that fits the beaker and comes
 * out in whole units at every addition — the dispenser pours whole units, so a plan wanting a third of a unit
 * of carbon is not one a chemist could follow. Null when it cannot be made, or when some stage would give
 * another reaction the chance to go instead.
 */
/proc/sp_plan_brew(product, list/base, max_volume, room_temp = DEFAULT_REAGENT_TEMPERATURE)
	var/list/datum/sp_brew_stage/stages = list()
	if(!sp_plan_stages(product, 1, base, room_temp, stages, list(), 0))
		return null
	var/datum/sp_brew/brew = new(product, stages)
	if(!isnull(sp_brew_conflict(brew, room_temp)))
		return null
	var/whole = 0
	for(var/factor in 1 to 216)
		if(sp_brew_whole_at(brew, factor))
			whole = factor
			break
	if(!whole)
		return null
	brew.scale(whole)
	brew.round_off()
	if(brew.peak_volume > max_volume)
		return null
	var/times = round(max_volume / brew.peak_volume)
	if(times > 1)
		brew.scale(times)
	return brew

/// Whether every addition comes out a whole number of units at this scale.
/proc/sp_brew_whole_at(datum/sp_brew/brew, factor)
	for(var/datum/sp_brew_stage/stage as anything in brew.stages)
		for(var/reagent in stage.additions)
			var/units = stage.additions[reagent] * factor
			if(abs(units - round(units, 1)) > 0.001)
				return FALSE
	return TRUE

/// Why a medicine could not be planned, for a test failure or a log line.
/proc/sp_explain_brew(product, list/base, room_temp = DEFAULT_REAGENT_TEMPERATURE)
	var/list/datum/sp_brew_stage/stages = list()
	if(!sp_plan_stages(product, 1, base, room_temp, stages, list(), 0))
		return "no recipe for it comes back to the dispenser"
	var/datum/sp_brew/brew = new(product, stages)
	var/datum/chemical_reaction/conflict = sp_brew_conflict(brew, room_temp)
	if(conflict)
		return "[conflict.type] could go off in the same beaker"
	return "it plans, but not into whole units in the beaker given"

// --- At the bench -----------------------------------------------------------------------------------

/// Clicks a beaker we carry into a machine. TRUE if it went in. Sleeps.
/proc/sp_chem_insert(datum/ai_controller/controller, obj/machinery/machine, obj/item/reagent_containers/beaker)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(QDELETED(machine) || QDELETED(beaker))
		return FALSE
	if(beaker.loc == machine)
		return TRUE
	if(!sp_take_in_hand(pawn, beaker))
		return FALSE
	sp_ai_click(controller, machine)
	return beaker.loc == machine

/// Takes a beaker back out of a machine: a right-click with a free hand. TRUE if we have it again. Sleeps.
/proc/sp_chem_eject(datum/ai_controller/controller, obj/machinery/machine, obj/item/reagent_containers/beaker)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(QDELETED(beaker))
		return FALSE
	if(beaker.loc != machine)
		return beaker in pawn.get_all_contents()
	var/obj/item/held = pawn.get_active_held_item()
	if(held && !(pawn.back && pawn.transferItemToLoc(held, pawn.back, silent = TRUE)))
		pawn.dropItemToGround(held)
	sp_ai_click(controller, machine, list(RIGHT_CLICK = "1"))
	return pawn.is_holding(beaker)

/**
 * Keeps a reacting beaker's pH where its reaction wants it, a unit of the heater's buffer at a time, the way a
 * chemist leans on the heater's buffer buttons. Libital sours by six and a half pH as it forms; left alone
 * a batch ends in the acid, and every step made there comes out less pure than the last.
 */
/proc/sp_buffer_ph(obj/machinery/chem_heater/heater, obj/item/reagent_containers/beaker, datum/chemical_reaction/reaction)
	var/ph = beaker.reagents.ph
	var/buffer
	if(ph < reaction.optimal_ph_min + 0.5)
		buffer = /datum/reagent/reaction_agent/basic_buffer
	else if(ph > reaction.optimal_ph_max - 0.5)
		buffer = /datum/reagent/reaction_agent/acidic_buffer
	if(isnull(buffer) || !heater.reagents.has_reagent(buffer, 1))
		return FALSE
	heater.reagents.trans_to(beaker, 1, target_id = buffer)
	return TRUE

/// How far a stage's reaction moves the pH by the time it is done: the whole H_ion_release for one that /tg/
/// scales to the batch, otherwise that much for every unit made.
/proc/sp_brew_ph_drift(datum/sp_brew_stage/stage)
	var/datum/chemical_reaction/reaction = stage.reaction
	if(reaction.reaction_flags & REACTION_PH_VOL_CONSTANT)
		return reaction.H_ion_release
	return reaction.H_ion_release * stage.amount

/// Where a stage's pH should start so its own drift carries it through the good range rather than out of it:
/// low for aiuri, which turns basic as it forms, high for libital, which turns acid.
/proc/sp_brew_start_ph(datum/sp_brew_stage/stage)
	var/datum/chemical_reaction/reaction = stage.reaction
	var/middle = (reaction.optimal_ph_min + reaction.optimal_ph_max) / 2
	return clamp(middle - sp_brew_ph_drift(stage) / 2, reaction.optimal_ph_min + 0.3, reaction.optimal_ph_max - 0.3)

/// Whether a stage starting at this pH would start, or drift, out of its reaction's good range.
/proc/sp_brew_needs_buffer(datum/sp_brew_stage/stage, start_ph)
	var/datum/chemical_reaction/reaction = stage.reaction
	var/end_ph = start_ph + sp_brew_ph_drift(stage)
	return min(start_ph, end_ph) < reaction.optimal_ph_min || max(start_ph, end_ph) > reaction.optimal_ph_max

/**
 * Sets a stage's pH before its last ingredient goes in, so the reaction starts where it should rather than
 * where its ingredients happen to land. Aiuri is done in about a second and a half, so buffering once it has
 * started is too late: a batch that starts at pH 3.6 comes out barely a third pure. Needs the beaker in the
 * heater, whose buffers these are.
 */
/proc/sp_prebuffer(obj/machinery/chem_heater/heater, obj/item/reagent_containers/beaker, datum/sp_brew_stage/stage, datum/reagent/trigger, trigger_units)
	var/datum/reagents/holder = beaker.reagents
	var/volume = holder.total_volume
	if(volume <= 0)
		return FALSE
	var/trigger_ph = initial(trigger.ph)
	// The pH the beaker needs now for the mix to land on the target once the last ingredient is in.
	var/wanted = clamp((sp_brew_start_ph(stage) * (volume + trigger_units) - trigger_ph * trigger_units) / volume, 0.5, 13.5)
	var/shift = wanted - holder.ph
	if(abs(shift) < 0.2)
		return FALSE
	var/buffer = shift > 0 ? /datum/reagent/reaction_agent/basic_buffer : /datum/reagent/reaction_agent/acidic_buffer
	// A unit of buffer moves every reagent in the beaker by BUFFER_IONIZING_STRENGTH over the beaker's volume.
	var/units = min(abs(shift) * volume / BUFFER_IONIZING_STRENGTH, heater.reagents.get_reagent_amount(buffer))
	if(units < 0.1)
		return FALSE
	heater.reagents.trans_to(beaker, units, target_id = buffer)
	return TRUE

/// The heater's two buffers, the one the brews use most first: libital, aiuri and cryoxadone all want the basic.
/proc/sp_chem_buffers()
	var/static/list/buffers = list(
		/datum/reagent/reaction_agent/basic_buffer,
		/datum/reagent/reaction_agent/acidic_buffer,
	)
	return buffers

/**
 * The buffer a heater is running short of, if the dispenser can make it. A heater starts with twenty units of
 * each, which is three brews' worth, and the first live chemist found out what the brew after that is like.
 */
/proc/sp_chem_buffer_wanted(obj/machinery/chem_heater/heater, obj/machinery/chem_dispenser/dispenser)
	if(QDELETED(heater) || QDELETED(dispenser))
		return null
	var/obj/item/reagent_containers/cup/beaker/standard = /obj/item/reagent_containers/cup/beaker
	for(var/buffer in sp_chem_buffers())
		if(heater.reagents.get_reagent_amount(buffer) >= SP_CHEM_BUFFER_LOW)
			continue
		if(!isnull(sp_plan_brew(buffer, dispenser.dispensable_reagents, initial(standard.volume), dispenser.dispensed_temperature)))
			return buffer
	return null

/// Draws the buffer in the inserted beaker into the heater's own store, as the heater's draw button does.
/obj/machinery/chem_heater/proc/sp_draw_buffer(datum/reagent/buffer_type)
	return move_buffer(buffer_type, -1)

/**
 * Puts a batch of buffer where the brews can use it: into the heater's store, up to the half of the heater it
 * keeps for each, and whatever is left down the ChemMaster. Returns TRUE if the heater took any. Sleeps.
 */
/proc/sp_load_buffer(datum/ai_controller/controller, obj/machinery/chem_heater/heater, obj/machinery/chem_master/master, obj/item/reagent_containers/beaker, buffer)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/before = heater.reagents.get_reagent_amount(buffer)
	if(sp_chem_insert(controller, heater, beaker))
		heater.sp_draw_buffer(buffer)
		sp_chem_eject(controller, heater, beaker)
	var/loaded = heater.reagents.get_reagent_amount(buffer) - before
	if(beaker.reagents.total_volume)
		sp_chem_drain(controller, master, beaker)
	if(loaded <= 0)
		log_sp("[pawn.real_name] could not get the buffer into [heater.name]")
		return FALSE
	var/datum/reagent/buffer_type = buffer
	sp_record("chem.buffer", round(loaded, 1))
	log_sp("[pawn.real_name] topped [heater.name] up with [round(loaded, 0.1)]u of [initial(buffer_type.name)], now [round(heater.reagents.get_reagent_amount(buffer), 0.1)]u")
	return TRUE

/**
 * Holds the beaker in the heater at the stage's temperature until its reaction has made what it should, or has
 * stopped. Returns how much of the stage's product there is. Sleeps.
 */
/proc/sp_react_stage(obj/machinery/chem_heater/heater, obj/item/reagent_containers/beaker, datum/sp_brew_stage/stage)
	heater.target_temperature = stage.heat_to
	heater.on = TRUE
	beaker.reagents.handle_reactions()
	var/started = world.time
	while(world.time - started < SP_BREW_STAGE_TIMEOUT)
		sleep(0.5 SECONDS)
		if(QDELETED(beaker) || QDELETED(heater) || beaker.loc != heater)
			break
		sp_buffer_ph(heater, beaker, stage.reaction)
		if(beaker.reagents.get_reagent_amount(stage.product) >= stage.amount * 0.98)
			break
		// At temperature and nothing happening: it has run out of something.
		if(!beaker.reagents.is_reacting && abs(beaker.reagents.chem_temp - stage.heat_to) < 15 && world.time - started > 5 SECONDS)
			break
	return QDELETED(beaker) ? 0 : beaker.reagents.get_reagent_amount(stage.product)

/**
 * Brews a planned medicine at a bench: each stage's additions from the dispenser, then its reaction in the
 * heater. Returns how many units of the medicine came out. Sleeps.
 */
/proc/sp_run_brew(datum/ai_controller/controller, datum/sp_brew/brew, obj/item/reagent_containers/beaker, obj/machinery/chem_dispenser/dispenser, obj/machinery/chem_heater/heater)
	var/mob/living/carbon/human/pawn = controller.pawn
	for(var/datum/sp_brew_stage/stage as anything in brew.stages)
		if(QDELETED(beaker) || QDELETED(pawn))
			return 0
		if(!sp_chem_insert(controller, dispenser, beaker))
			log_sp("[pawn.real_name] could not get [beaker.name] into [dispenser.name]")
			return 0
		// Everything but the last ingredient, which is what sets the reaction off.
		var/datum/reagent/trigger = stage.additions[length(stage.additions)]
		var/trigger_units = stage.additions[trigger]
		for(var/reagent in stage.additions)
			if(reagent != trigger)
				sp_dispense_into(dispenser, beaker, reagent, stage.additions[reagent])
		var/volume = beaker.reagents.total_volume
		var/predicted_ph = volume ? (beaker.reagents.ph * volume + initial(trigger.ph) * trigger_units) / (volume + trigger_units) : initial(trigger.ph)
		if(volume && sp_brew_needs_buffer(stage, predicted_ph))
			if(sp_chem_eject(controller, dispenser, beaker) && sp_chem_insert(controller, heater, beaker))
				sp_prebuffer(heater, beaker, stage, trigger, trigger_units)
			if(!sp_chem_eject(controller, heater, beaker) || !sp_chem_insert(controller, dispenser, beaker))
				log_sp("[pawn.real_name] could not get [beaker.name] back into [dispenser.name] after buffering it")
				return 0
		sp_dispense_into(dispenser, beaker, trigger, trigger_units)
		if(!sp_chem_eject(controller, dispenser, beaker) || !sp_chem_insert(controller, heater, beaker))
			log_sp("[pawn.real_name] could not move [beaker.name] from [dispenser.name] to [heater.name]")
			heater.on = FALSE
			return 0
		var/made = sp_react_stage(heater, beaker, stage)
		sp_chem_eject(controller, heater, beaker)
		if(made < stage.amount * 0.5)
			var/datum/reagent/stage_product = stage.product
			log_sp("[pawn.real_name]'s [initial(stage_product.name)] stage made [round(made, 0.1)]u of [round(stage.amount, 0.1)]u (pH [round(beaker.reagents.ph, 0.1)], [round(beaker.reagents.chem_temp)] K)")
			heater.on = FALSE
			return 0
	heater.on = FALSE
	return beaker.reagents.get_reagent_amount(brew.product)

/**
 * Prints what is in the ChemMaster's buffer into containers, as its create button would, but without the name
 * prompt: that is a tgui input, which a mob with no client never answers, so the button would just stop.
 */
/obj/machinery/chem_master/proc/sp_print(mob/living/user, obj/item/reagent_containers/container_type, count, item_name)
	if(is_printing || !is_operational || !reagents.total_volume || count < 1)
		return FALSE
	var/volume_in_each = min(round(reagents.total_volume / count, CHEMICAL_VOLUME_ROUNDING), initial(container_type.volume))
	selected_container = container_type
	is_printing = TRUE
	printing_progress = 0
	printing_total = count
	create_containers(user, count, item_name, volume_in_each, container_type)
	return TRUE

/// Pours a beaker away down the ChemMaster: into its buffer, and the buffer emptied. Sleeps.
/proc/sp_chem_drain(datum/ai_controller/controller, obj/machinery/chem_master/master, obj/item/reagent_containers/beaker)
	if(!sp_chem_insert(controller, master, beaker))
		return FALSE
	beaker.reagents.trans_to(master.reagents, beaker.reagents.total_volume)
	master.reagents.clear_reagents()
	sp_chem_eject(controller, master, beaker)
	return !beaker.reagents.total_volume

/**
 * Turns the medicine in a beaker into patches at the ChemMaster: in goes the beaker, the medicine into the
 * buffer, out come the patches onto the machine's tile, and whatever else was in the beaker goes down the
 * drain. Returns the patches, picked up. Sleeps.
 */
/proc/sp_print_patches(datum/ai_controller/controller, obj/machinery/chem_master/master, obj/item/reagent_containers/beaker, product)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/list/obj/item/printed = list()
	var/count = round(beaker.reagents.get_reagent_amount(product) / SP_CHEM_PATCH_UNITS)
	if(count < 1 || !sp_chem_insert(controller, master, beaker))
		return printed
	master.reagents.clear_reagents()
	beaker.reagents.trans_to(master.reagents, count * SP_CHEM_PATCH_UNITS, target_id = product)
	var/datum/reagent/medicine = product
	var/turf/output = master.drop_location()
	var/list/obj/item/already_there = list()
	for(var/obj/item/reagent_containers/applicator/patch/patch in output)
		already_there += patch
	if(master.sp_print(pawn, /obj/item/reagent_containers/applicator/patch/style, count, "[initial(medicine.name)] patch ([SP_CHEM_PATCH_UNITS]u)"))
		var/give_up_at = world.time + count * master.printing_speed + 5 SECONDS
		while(master.is_printing && world.time < give_up_at)
			sleep(0.5 SECONDS)
	// Whatever else was in the beaker — spent buffer, the little that never reacted — goes down the drain.
	beaker.reagents.trans_to(master.reagents, beaker.reagents.total_volume)
	master.reagents.clear_reagents()
	sp_chem_eject(controller, master, beaker)
	for(var/obj/item/reagent_containers/applicator/patch/patch in output)
		if(patch in already_there)
			continue
		sp_free_hands(pawn)
		sp_ai_click(controller, patch)
		if(!pawn.is_holding(patch))
			continue
		if(pawn.back)
			pawn.transferItemToLoc(patch, pawn.back, silent = TRUE)
		printed += patch
	return printed

/**
 * The smallest empty beaker we carry. A standard beaker's batch is a few patches or a tube's worth of
 * cryoxadone, and a bigger batch needs more of the heater's buffer than it holds: twenty units of each, and a
 * 27u batch of libital takes about eight. Null if nothing we carry is clean.
 */
/proc/sp_chem_find_beaker(mob/living/carbon/human/chemist)
	var/obj/item/reagent_containers/cup/beaker/best
	for(var/obj/item/reagent_containers/cup/beaker/beaker as anything in chemist.get_all_contents_type(/obj/item/reagent_containers/cup/beaker))
		if(beaker.reagents?.total_volume)
			continue
		if(isnull(best) || beaker.volume < best.volume)
			best = beaker
	return best

/**
 * Makes one order at a bench: finds a clean beaker, plans the brew for it, brews it, and prints patches if
 * that is the form it is wanted in. Returns TRUE if there is medicine to deliver. Sleeps.
 */
/proc/sp_make_medicine(datum/ai_controller/controller, product, form, obj/machinery/chem_dispenser/dispenser, obj/machinery/chem_heater/heater, obj/machinery/chem_master/master)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/datum/reagent/medicine = product
	var/medicine_name = initial(medicine.name)
	if(QDELETED(dispenser) || QDELETED(heater) || QDELETED(master))
		return FALSE
	var/obj/item/reagent_containers/cup/beaker/beaker = sp_chem_find_beaker(pawn)
	if(isnull(beaker))
		// Nothing clean: pour one away down the ChemMaster and use that.
		var/list/obj/item/reagent_containers/cup/beaker/carried = pawn.get_all_contents_type(/obj/item/reagent_containers/cup/beaker)
		if(!length(carried) || !sp_chem_drain(controller, master, carried[1]))
			log_sp("[pawn.real_name] has no beaker to brew [medicine_name] in")
			return FALSE
		beaker = carried[1]
	var/datum/sp_brew/brew = sp_plan_brew(product, dispenser.dispensable_reagents, beaker.volume, dispenser.dispensed_temperature)
	if(isnull(brew))
		log_sp("[pawn.real_name] cannot make [medicine_name] from [dispenser.name]: [sp_explain_brew(product, dispenser.dispensable_reagents, dispenser.dispensed_temperature)]")
		return FALSE
	sp_crew_speak(pawn, pick("Mixing up some [medicine_name].", "[capitalize(medicine_name)], coming up.", "Time for a batch of [medicine_name]."))
	var/made = sp_run_brew(controller, brew, beaker, dispenser, heater)
	if(made < 1)
		log_sp("[pawn.real_name]'s batch of [medicine_name] came to nothing")
		sp_chem_drain(controller, master, beaker)
		return FALSE
	sp_record("chem.brewed")
	log_sp("[pawn.real_name] brewed [round(made, 0.1)]u of [medicine_name] at [round(sp_reagent_purity(beaker, product) * 100)]% purity in [length(brew.stages)] stages")
	if(form == SP_CHEM_FORM_HEATER)
		return sp_load_buffer(controller, heater, master, beaker, product)
	if(form != SP_CHEM_FORM_PATCH)
		return TRUE
	var/list/obj/item/patches = sp_print_patches(controller, master, beaker, product)
	if(!length(patches))
		return FALSE
	sp_record("chem.patches", length(patches))
	log_sp("[pawn.real_name] printed [length(patches)] [medicine_name] patches")
	return TRUE

/**
 * A place to stand with a chemistry dispenser, a heater and a ChemMaster all in reach, so a whole brew happens
 * without walking: list(turf, dispenser, heater, chem master), the nearest. MetaStation builds all three of its
 * benches this way, with a chemist's spawn point on the standing tile.
 */
/proc/sp_find_chem_bench(atom/near)
	var/turf/here = get_turf(near)
	if(isnull(here))
		return null
	var/list/best
	var/best_distance = INFINITY
	for(var/obj/machinery/chem_dispenser/dispenser as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/chem_dispenser))
		if(!sp_is_chem_dispenser(dispenser) || dispenser.z != here.z || !dispenser.is_operational || !sp_in_chem_lab(dispenser))
			continue
		for(var/turf/open/spot in range(1, dispenser))
			if(spot.is_blocked_turf(exclude_mobs = TRUE))
				continue
			var/obj/machinery/chem_heater/heater = locate() in range(1, spot)
			var/obj/machinery/chem_master/master
			for(var/obj/machinery/chem_master/candidate in range(1, spot))
				if(!istype(candidate, /obj/machinery/chem_master/condimaster))
					master = candidate
					break
			if(isnull(heater) || isnull(master))
				continue
			var/distance = get_dist(here, spot)
			if(distance < best_distance)
				best = list(spot, dispenser, heater, master)
				best_distance = distance
	return best

// --- What medbay needs ------------------------------------------------------------------------------

/// The chemistry fridges in the lab, which medbay reaches into through the wall.
/proc/sp_chem_fridges(atom/near)
	var/list/obj/machinery/smartfridge/fridges = list()
	var/turf/here = get_turf(near)
	if(isnull(here))
		return fridges
	for(var/obj/machinery/smartfridge/chemistry/fridge as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/smartfridge/chemistry))
		if(fridge.z == here.z && fridge.is_operational && sp_in_chem_lab(fridge))
			fridges += fridge
	return fridges

/// The nearest chemistry fridge with room in it.
/proc/sp_find_chem_fridge(atom/near)
	var/obj/machinery/smartfridge/best
	for(var/obj/machinery/smartfridge/fridge as anything in sp_chem_fridges(near))
		if(fridge.visible_items() >= fridge.max_n_of_items)
			continue
		if(isnull(best) || get_dist(near, fridge) < get_dist(near, best))
			best = fridge
	return best

/// Patches of a medicine waiting in the chemistry fridges.
/proc/sp_chem_patch_stock(atom/near, chem)
	var/count = 0
	for(var/obj/machinery/smartfridge/fridge as anything in sp_chem_fridges(near))
		for(var/obj/item/reagent_containers/applicator/patch/patch in fridge)
			if(patch.reagents?.has_reagent(chem))
				count++
	return count

/// Patches of a medicine the chemist is carrying, which will be in the fridge as soon as they have walked over.
/proc/sp_carried_patches(mob/living/carbon/human/chemist, chem)
	var/count = 0
	for(var/obj/item/reagent_containers/applicator/patch/patch as anything in chemist.get_all_contents_type(/obj/item/reagent_containers/applicator/patch))
		if(patch.reagents?.has_reagent(chem))
			count++
	return count

/// Cryoxadone for the tubes, in units: what is in them, and what is waiting in the cryo room.
/proc/sp_cryoxadone_supply(atom/near)
	var/list/obj/machinery/cryo_cell/cells = sp_medbay_cryo_cells(near)
	if(!length(cells))
		return INFINITY
	var/total = 0
	for(var/obj/machinery/cryo_cell/cryo as anything in cells)
		total += sp_cryoxadone_units(cryo.beaker)
	var/obj/machinery/cryo_cell/first = cells[1]
	var/area/room = get_area(first)
	for(var/turf/spot as anything in get_area_turfs(room.type, first.z))
		for(var/obj/item/reagent_containers/cup/cup in spot)
			total += sp_cryoxadone_units(cup)
	return total

/// Where fresh cryoxadone goes: the table in the cryo room nearest the tubes.
/proc/sp_find_cryo_drop(atom/near)
	var/list/obj/machinery/cryo_cell/cells = sp_medbay_cryo_cells(near)
	if(!length(cells))
		return null
	var/obj/machinery/cryo_cell/first = cells[1]
	var/area/room = get_area(first)
	var/obj/structure/table/best
	for(var/turf/spot as anything in get_area_turfs(room.type, first.z))
		var/obj/structure/table/table = locate() in spot
		if(table && (isnull(best) || get_dist(first, table) < get_dist(first, best)))
			best = table
	return best

/**
 * What the chemist should make next at a bench (sp_find_chem_bench's list), as list(product, form), or null
 * when medbay has what it needs. Buffer for the bench's heater comes first, since every brew after it leans
 * on it; then cryo, because a patient in a tube with nothing in the beaker is only getting cold; then patches.
 *
 * What the chemist is carrying counts as delivered. Counting only the fridge had the first live chemist brew
 * libital three times running, with two batches of patches in their pocket on the way, and spend the
 * heater's buffer on them, so the aiuri after came out 43% pure.
 */
/proc/sp_next_chem_order(mob/living/carbon/human/chemist, list/bench)
	if(length(bench) >= 4)
		var/buffer = sp_chem_buffer_wanted(bench[3], bench[2])
		if(buffer)
			return list(buffer, SP_CHEM_FORM_HEATER)
	var/carried_cryoxadone = 0
	for(var/obj/item/reagent_containers/cup/cup as anything in chemist.get_all_contents_type(/obj/item/reagent_containers/cup))
		carried_cryoxadone += sp_cryoxadone_units(cup)
	if(sp_cryoxadone_supply(chemist) + carried_cryoxadone < SP_CRYOXADONE_LOW && !isnull(sp_find_cryo_drop(chemist)))
		return list(/datum/reagent/medicine/cryoxadone, SP_CHEM_FORM_BEAKER)
	if(isnull(sp_find_chem_fridge(chemist)))
		return null
	for(var/chem in GLOB.sp_patch_chems)
		if(sp_chem_patch_stock(chemist, chem) + sp_carried_patches(chemist, chem) < SP_CHEM_PATCH_STOCK)
			return list(chem, SP_CHEM_FORM_PATCH)
	return null

/// Where the medicine we carry should go, as list(target, item): cryoxadone to cryo, patches to the fridge.
/proc/sp_next_chem_drop(mob/living/carbon/human/chemist)
	var/obj/item/reagent_containers/cup/cryoxadone = sp_carried_cryoxadone(chemist)
	if(cryoxadone)
		var/obj/structure/table/table = sp_find_cryo_drop(chemist)
		if(table)
			return list(table, cryoxadone)
	var/list/obj/item/reagent_containers/applicator/patch/patches = chemist.get_all_contents_type(/obj/item/reagent_containers/applicator/patch)
	if(length(patches))
		var/obj/machinery/smartfridge/fridge = sp_find_chem_fridge(chemist)
		if(fridge)
			return list(fridge, patches[1])
	return null
