/**
 * Spacestation SP — greytide, gently.
 *
 * Assistants have no department and no work, and on a real server that makes them the station's mischief:
 * insulated gloves out of tool storage, lockers left hanging open, crayon on the floors, the lights going out
 * in the bar. These are the beginnings of that, tuned for fun rather than trouble. Nothing here hurts anybody,
 * breaks anything or gets through a door that was shut; the lights always come back on; and nobody pulls a
 * prank with security watching.
 */

/// Where assistants hang about: the public parts of the station, and the tool storage every assistant knows.
/proc/sp_greytide_haunts()
	var/static/list/areas = list(
		/area/station/hallway/primary/central,
		/area/station/hallway/primary/fore,
		/area/station/hallway/primary/aft,
		/area/station/hallway/primary/port,
		/area/station/hallway/primary/starboard,
		/area/station/commons/lounge,
		/area/station/commons/dorms,
		/area/station/commons/fitness,
		/area/station/commons/storage/primary,
		/area/station/service/bar,
		/area/station/service/library,
	)
	return areas

/// An assistant's tastes: gloves, masks, toys and one tool, on top of whatever they roll like anyone else.
/proc/sp_greytide_interests()
	var/list/interests = list(/obj/item/clothing/gloves, /obj/item/clothing/mask, /obj/item/toy, pick(GLOB.sp_greytide_tools))
	return unique_list(interests + sp_roll_interests())

/// Crayon designs an assistant draws: the friendly end of the crayon menu. No chalk outlines, runes or slogans.
GLOBAL_LIST_INIT(sp_graffiti_designs, list(
	"star",
	"face",
	"guy",
	"dwarf",
	"heart",
	"peace",
	"like",
	"space",
	"carp",
	"cat",
	"clown",
	"corgi",
	"ghost",
	"stickman",
	"toolbox",
))

/// Gloves worth a trip to tool storage: real insulated ones, or the budget sort that is usually all there is.
GLOBAL_LIST_INIT(sp_greytide_gloves, list(
	/obj/item/clothing/gloves/color/yellow,
	/obj/item/clothing/gloves/color/fyellow,
))

/// Tools an assistant feels underdressed without. Not the flashlight: half the crew carry one already.
GLOBAL_LIST_INIT(sp_greytide_tools, list(
	/obj/item/crowbar,
	/obj/item/wrench,
	/obj/item/screwdriver,
	/obj/item/wirecutters,
	/obj/item/multitool,
))

// --- Where, and in front of whom -------------------------------------------------------------------

/// Floor an assistant draws on: hallways, maintenance and the commons, nobody's workplace.
/proc/sp_is_graffiti_area(area/place)
	return istype(place, /area/station/hallway) || istype(place, /area/station/maintenance) || istype(place, /area/station/commons)

/// Rooms where the lights going out for a few seconds is a joke rather than a problem.
/proc/sp_is_prank_room(area/place)
	return istype(place, /area/station/hallway) || istype(place, /area/station/commons) || istype(place, /area/station/service/bar) \
		|| istype(place, /area/station/service/cafeteria) || istype(place, /area/station/service/library) || istype(place, /area/station/service/theater)

/// Somewhere an assistant has no business, whose windows are therefore worth knocking on.
/proc/sp_is_off_limits(area/place)
	return istype(place, /area/station/command) || istype(place, /area/station/security) || istype(place, /area/station/ai)

/// Somewhere anyone may stand: the public areas, and the lobbies in front of the departments.
/proc/sp_is_public_spot(turf/spot)
	var/area/place = get_area(spot)
	if(isnull(place))
		return FALSE
	return sp_is_graffiti_area(place) || sp_is_prank_room(place) || findtext("[place.type]", "lobby")

/// Whether anyone from security is watching: no assistant pulls a prank in front of an officer.
/proc/sp_security_watching(mob/living/carbon/human/prankster)
	for(var/mob/living/carbon/human/other in oview(SP_CURIOSITY_RANGE, prankster))
		if(other.stat != STABLE)
			continue
		var/datum/job/role = other.mind?.assigned_role
		if(role && (/datum/job_department/security in role.departments_list))
			return TRUE
	return FALSE

/// How many other people, awake and on their feet, are in a room.
/proc/sp_people_in_area(area/room, mob/exclude)
	. = 0
	for(var/mob/living/carbon/human/other as anything in GLOB.human_list)
		if(other != exclude && other.stat == STABLE && get_area(other) == room)
			.++

/// A tile beside something on its public side, to stand on and reach it from: a counter has two sides.
/proc/sp_public_reach_spot(atom/thing, atom/near)
	var/turf/target_turf = get_turf(thing)
	if(isnull(target_turf))
		return null
	var/turf/best
	for(var/turf/open/spot in range(1, target_turf))
		if(!sp_is_public_spot(spot) || spot.is_blocked_turf(exclude_mobs = TRUE) || !spot.Adjacent(thing))
			continue
		if(isnull(best) || get_dist(near, spot) < get_dist(near, best))
			best = spot
	return best

// --- What there is to do ---------------------------------------------------------------------------

/// A crayon we carry. Not a spray can: those paint faces as readily as floors.
/proc/sp_carried_crayon(mob/living/carbon/human/prankster)
	for(var/obj/item/toy/crayon/crayon as anything in prankster.get_all_contents_type(/obj/item/toy/crayon))
		if(!istype(crayon, /obj/item/toy/crayon/spraycan))
			return crayon
	return null

/// Somewhere to draw: a bit of public floor close by, clear and not already drawn on.
/proc/sp_find_graffiti_spot(mob/living/carbon/human/prankster)
	var/list/turf/candidates = list()
	for(var/turf/open/floor/spot in view(4, prankster))
		if(!sp_is_graffiti_area(get_area(spot)) || spot.is_blocked_turf(exclude_mobs = TRUE))
			continue
		if(locate(/obj/effect/decal/cleanable/crayon) in spot)
			continue
		candidates += spot
	return length(candidates) ? pick(candidates) : null

/// A light switch in a room with people in it and the lights on, where the dark is only a joke.
/proc/sp_find_light_prank(mob/living/carbon/human/prankster)
	for(var/obj/machinery/light_switch/light_switch in view(SP_MISCHIEF_RANGE, prankster))
		var/area/room = light_switch.area
		if(isnull(room) || !room.lightswitch || !light_switch.is_operational || !sp_is_prank_room(room))
			continue
		if(!sp_people_in_area(room, prankster))
			continue
		var/turf/spot = sp_reach_spot(light_switch, prankster)
		if(spot)
			return list(SP_MISCHIEF_LIGHTS, light_switch, spot)
	return null

/**
 * A working light in a public area worth smashing, with a tile to reach its fixture from. The malicious
 * end of the menu: it stays dark until a crew member replaces the tube, so only where that is a nuisance
 * rather than a hazard — the same public rooms the harmless lights-out prank uses, never a workplace.
 */
/proc/sp_find_light_to_break(mob/living/carbon/human/prankster)
	for(var/obj/machinery/light/light in view(SP_MISCHIEF_RANGE, prankster))
		if(light.status != LIGHT_OK || !light.on)
			continue
		var/area/room = get_area(light)
		if(isnull(room) || !sp_is_prank_room(room))
			continue
		var/turf/spot = sp_reach_spot(light, prankster)
		if(spot)
			return list(SP_MISCHIEF_VANDALISM, light, spot)
	return null

/// A window into somewhere off limits, with public floor outside it to knock from.
/proc/sp_find_window_to_knock(mob/living/carbon/human/prankster)
	for(var/obj/structure/window/window in view(SP_MISCHIEF_RANGE, prankster))
		if(!window.fulltile || !window.anchored)
			continue
		var/off_limits = sp_is_off_limits(get_area(window))
		for(var/direction in GLOB.cardinals)
			if(off_limits)
				break
			off_limits = sp_is_off_limits(get_area(get_step(window, direction)))
		if(!off_limits)
			continue
		var/turf/spot = sp_public_reach_spot(window, prankster)
		if(spot)
			return list(SP_MISCHIEF_KNOCK, window, spot)
	return null

/// A desk bell nearby, on a counter whose public side we can stand at.
/proc/sp_find_bell_to_ring(mob/living/carbon/human/prankster)
	for(var/obj/structure/desk_bell/bell in view(SP_MISCHIEF_RANGE, prankster))
		if(bell.broken_ringer)
			continue
		var/turf/spot = sp_public_reach_spot(bell, prankster)
		if(spot)
			return list(SP_MISCHIEF_BELL, bell, spot)
	return null

/// A horn, or a rubber duck, that we carry, and somebody about to hear it.
/proc/sp_find_honk(mob/living/carbon/human/prankster)
	var/obj/item/bikehorn/horn = locate() in prankster.get_all_contents()
	if(isnull(horn))
		return null
	for(var/mob/living/carbon/human/other in oview(5, prankster))
		if(other.stat == STABLE)
			return list(SP_MISCHIEF_HONK, horn, get_turf(prankster))
	return null

/// Every prank open to this assistant where they stand, as list(kind, target, tile to do it from) entries.
/proc/sp_mischief_options(mob/living/carbon/human/prankster)
	var/list/options = list()
	if(sp_carried_crayon(prankster))
		var/turf/canvas = sp_find_graffiti_spot(prankster)
		if(canvas)
			options += list(list(SP_MISCHIEF_GRAFFITI, canvas, canvas))
	for(var/list/option as anything in list(sp_find_light_prank(prankster), sp_find_window_to_knock(prankster), sp_find_bell_to_ring(prankster), sp_find_honk(prankster)))
		if(option)
			options += list(option)
	// A troublemaker, where the malicious streak is switched on, will also break a light. Offered alongside
	// the pranks rather than instead of them, so it is the occasional edge, not their whole shift.
	var/datum/ai_controller/sp_crew/controller = prankster.ai_controller
	if(istype(controller) && controller.blackboard[BB_SP_TROUBLEMAKER] && CONFIG_GET(flag/sp_greytide_malice))
		var/list/vandalism = sp_find_light_to_break(prankster)
		if(vandalism)
			options += list(vandalism)
	return options

// --- Doing it --------------------------------------------------------------------------------------

/// Smashes a light tube. Goes dark until somebody replaces it, and a witness calls it out. TRUE if it broke. Sleeps.
/proc/sp_prank_vandalism(datum/ai_controller/controller, obj/machinery/light/light)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(QDELETED(light) || light.status != LIGHT_OK)
		return FALSE
	sp_free_hands(pawn)
	pawn.face_atom(light)
	// A whack with whatever is to hand, or a bare fist; break_light_tube() is what a hit that connects does.
	sp_ai_click(controller, light)
	light.break_light_tube()
	if(light.status == LIGHT_OK)
		return FALSE
	sp_crew_speak(pawn, pick("Oops.", "Wasn't me.", "It just went out. Honest."))
	sp_crime_seen(pawn, SP_CRIME_VANDALISM, "smash a light", get_turf(light))
	return TRUE

/// Draws on a bit of floor beside or under us with a crayon we carry. TRUE if a drawing appeared. Sleeps.
/proc/sp_prank_graffiti(datum/ai_controller/controller, turf/canvas)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/obj/item/toy/crayon/crayon = sp_carried_crayon(pawn)
	if(isnull(crayon) || !sp_take_in_hand(pawn, crayon))
		return FALSE
	// Crayons come set to a random design, runes and three-tile murals included, so always choose one.
	crayon.drawtype = pick(GLOB.sp_graffiti_designs)
	sp_ai_click(controller, canvas)
	if(!QDELETED(crayon) && pawn.is_holding(crayon) && pawn.back)
		pawn.transferItemToLoc(crayon, pawn.back, silent = TRUE)
	return !isnull(locate(/obj/effect/decal/cleanable/crayon) in canvas)

/**
 * Lights out in a room with people in it, a few seconds of dark, and the lights back on. They always come
 * back on, whatever happens in between: a joke that leaves the bar dark all shift is not one. TRUE if the
 * room went dark. Sleeps.
 */
/proc/sp_prank_lights(datum/ai_controller/controller, obj/machinery/light_switch/light_switch)
	var/mob/living/carbon/human/pawn = controller.pawn
	var/area/room = light_switch.area
	if(isnull(room) || !room.lightswitch)
		return FALSE
	sp_free_hands(pawn)
	sp_ai_click(controller, light_switch)
	if(room.lightswitch)
		return FALSE
	sp_crew_speak(pawn, pick("Boo!", "Lights out!", "Who turned the lights off? Oh, me."))
	sleep(SP_MISCHIEF_DARK_TIME)
	if(!QDELETED(light_switch) && !room.lightswitch && pawn.Adjacent(light_switch))
		sp_ai_click(controller, light_switch)
	if(!QDELETED(light_switch) && !room.lightswitch)
		light_switch.set_lights(TRUE)
	sp_crew_speak(pawn, pick("Just kidding!", "Ha! Your faces.", "There. Happy now?"))
	return TRUE

/// Knocks on a window into somewhere off limits and asks to be let in. TRUE if they knocked. Sleeps.
/proc/sp_prank_knock(datum/ai_controller/controller, obj/structure/window/window)
	var/mob/living/carbon/human/pawn = controller.pawn
	sp_free_hands(pawn)
	var/knocks = 0
	for(var/i in 1 to rand(2, 3))
		if(QDELETED(window) || !pawn.Adjacent(window))
			break
		sp_ai_click(controller, window)
		knocks++
	if(!knocks)
		return FALSE
	sp_crew_speak(pawn, pick("Knock knock!", "Hey! Let me in!", "Anyone home?", "I can see you in there!"))
	return TRUE

/// Rings a desk bell a few times and asks for service. TRUE if it rang. Sleeps.
/proc/sp_prank_bell(datum/ai_controller/controller, obj/structure/desk_bell/bell)
	var/mob/living/carbon/human/pawn = controller.pawn
	sp_free_hands(pawn)
	var/rung_before = bell.times_rang
	for(var/i in 1 to rand(2, 4))
		if(QDELETED(bell) || !pawn.Adjacent(bell))
			break
		sp_ai_click(controller, bell)
		// The bell's own cooldown is a third of a second.
		sleep(0.5 SECONDS)
	if(QDELETED(bell) || bell.times_rang == rung_before)
		return FALSE
	sp_crew_speak(pawn, pick("Service!", "Hello? Anybody?", "Ding ding!", "I'd like to speak to the manager."))
	return TRUE

/// Honks a horn, or squeaks a duck, at whoever is about. TRUE if it made a noise. Sleeps.
/proc/sp_prank_honk(datum/ai_controller/controller, obj/item/bikehorn/horn)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(QDELETED(horn) || !sp_take_in_hand(pawn, horn))
		return FALSE
	for(var/i in 1 to rand(2, 3))
		// Used in hand; the squeak component's own two-second cooldown spaces the honks out.
		horn.attack_self(pawn)
		sleep(2.1 SECONDS)
		if(QDELETED(horn) || !pawn.is_holding(horn))
			break
	if(!QDELETED(horn) && pawn.is_holding(horn) && pawn.back)
		pawn.transferItemToLoc(horn, pawn.back, silent = TRUE)
	return TRUE

// --- Tool storage ----------------------------------------------------------------------------------

/// What an assistant still wants from tool storage, as lists of types that would do: gloves first, then a tool.
/proc/sp_gear_wanted(mob/living/carbon/human/assistant)
	var/list/wanted = list()
	if(isnull(assistant.gloves))
		wanted += list(GLOB.sp_greytide_gloves)
	for(var/obj/item/thing as anything in assistant.get_all_contents_type(/obj/item))
		if(is_type_in_list(thing, GLOB.sp_greytide_tools))
			return wanted
	wanted += list(GLOB.sp_greytide_tools)
	return wanted

/**
 * The nearest loose item of these sorts in tool storage, and the tile to reach it from, as list(item, spot),
 * or null when tool storage has nothing left that will do.
 */
/proc/sp_find_gear(mob/living/carbon/human/assistant, list/types)
	var/turf/here = get_turf(assistant)
	if(isnull(here))
		return null
	var/obj/item/best
	var/turf/best_spot
	for(var/turf/spot as anything in get_area_turfs(/area/station/commons/storage/primary, here.z))
		for(var/obj/item/thing in spot)
			if(thing.anchored || !is_type_in_list(thing, types))
				continue
			if(best && get_dist(assistant, thing) >= get_dist(assistant, best))
				continue
			var/turf/reach = sp_reach_spot(thing, assistant)
			if(reach)
				best = thing
				best_spot = reach
	return best ? list(best, best_spot) : null

/// Takes an item from tool storage: gloves go on, anything else goes in the bag. TRUE if we have it.
/proc/sp_take_gear_item(mob/living/carbon/human/assistant, obj/item/thing)
	if(QDELETED(thing) || !isturf(thing.loc) || !assistant.Adjacent(thing))
		return FALSE
	if(istype(thing, /obj/item/clothing/gloves) && isnull(assistant.gloves))
		return assistant.equip_to_slot_if_possible(thing, ITEM_SLOT_GLOVES, disable_warning = TRUE, bypass_equip_delay_self = TRUE)
	if(assistant.back && thing.forceMove(assistant.back))
		return TRUE
	return assistant.put_in_hands(thing)
