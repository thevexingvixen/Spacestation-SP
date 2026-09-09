/**
 * Spacestation SP — idle curiosity.
 *
 * Everything in here is what a crew member does when they have nothing to do: wander off across the
 * station, open a locker to see what is in it and pocket anything they fancy, and occasionally try a
 * door they have no business opening.
 *
 * It is shared by every job rather than bolted onto one, because it is character rather than work, and
 * because it is the groundwork for greytide and antagonists. The three things an antagonist changes are
 * all overridable on the controller: `wants_item()` decides what is worth taking, `may_rummage()` and
 * `may_try_doors()` decide whether to bother, and `on_door_denied()` decides what to do about a locked
 * door — an ordinary crew member grumbles and walks off, a greytider will not.
 */

/// Places people plausibly end up when they are not at work. Used for the occasional trip off-station.
/proc/sp_roaming_areas()
	var/static/list/areas = list(
		/area/station/hallway/primary/central,
		/area/station/hallway/primary/fore,
		/area/station/hallway/primary/aft,
		/area/station/hallway/primary/port,
		/area/station/hallway/primary/starboard,
		/area/station/hallway/secondary/entry,
		/area/station/hallway/secondary/exit,
		/area/station/hallway/secondary/service,
		/area/station/commons/lounge,
		/area/station/commons/dorms,
		/area/station/commons/fitness,
		/area/station/commons/vacant_room,
		/area/station/service/bar,
		/area/station/service/library,
		/area/station/service/chapel,
		/area/station/service/theater,
		/area/station/service/kitchen,
		/area/station/service/hydroponics,
		/area/station/medical/medbay/lobby,
		/area/station/cargo/office,
		/area/station/security/checkpoint,
		/area/station/maintenance/starboard,
		/area/station/maintenance/port,
		/area/station/maintenance/fore,
		/area/station/maintenance/aft,
	)
	return areas

// --- What somebody wants ---------------------------------------------------------------------------

/**
 * The sort of thing a person pockets. Each crew member rolls a few of these at spawn, so one has a
 * weakness for hats and another walks off with every screwdriver they find, and the same character is
 * consistent about it all shift.
 */
GLOBAL_LIST_INIT(sp_interest_pool, list(
	/obj/item/food,
	/obj/item/reagent_containers/cup/glass,
	/obj/item/clothing/head,
	/obj/item/clothing/gloves,
	/obj/item/clothing/mask,
	/obj/item/toy,
	/obj/item/flashlight,
	/obj/item/screwdriver,
	/obj/item/wrench,
	/obj/item/crowbar,
	/obj/item/wirecutters,
	/obj/item/pen,
	/obj/item/paper,
	/obj/item/lighter,
	/obj/item/storage/fancy/cigarettes,
	/obj/item/soap,
	/obj/item/reagent_containers/applicator/pill,
	/obj/item/stock_parts/power_store/cell,
	/obj/item/clothing/glasses,
	/obj/item/radio,
))

/// Things nobody should be walking off with, whatever their tastes.
GLOBAL_LIST_INIT(sp_interest_blacklist, typecacheof(list(
	/obj/item/card/id,
	/obj/item/implant,
	/obj/item/organ,
	/obj/item/bodypart,
	/obj/item/gun,
	/obj/item/grenade,
	/obj/item/tank/internals,
	/obj/item/disk/nuclear,
)))

/// Rolls this character's tastes.
/proc/sp_roll_interests()
	var/list/pool = GLOB.sp_interest_pool.Copy()
	var/list/chosen = list()
	for(var/i in 1 to SP_INTEREST_COUNT)
		if(!length(pool))
			break
		var/pick = pick(pool)
		pool -= pick
		chosen += pick
	return chosen

// --- Containers ------------------------------------------------------------------------------------

/**
 * A locker, crate or box worth opening: shut, not welded or broken, and either unlocked or something
 * our ID opens. Deliberately `oview`: this is idle nosiness, so it only covers what we can actually see
 * from where we are standing, not the whole department.
 */
/proc/sp_find_rummage_target(mob/living/carbon/human/crew, list/ignored)
	if(QDELETED(crew))
		return null
	var/obj/structure/closet/best
	var/best_distance = INFINITY
	for(var/obj/structure/closet/candidate in oview(SP_CURIOSITY_RANGE, crew))
		if(!sp_worth_a_look(candidate, crew))
			continue
		if(ignored?[candidate] > world.time)
			continue
		var/distance = get_dist(crew, candidate)
		if(distance < best_distance)
			best = candidate
			best_distance = distance
	return best

/// Could we open this, and is there any point?
/proc/sp_worth_a_look(obj/structure/closet/container, mob/living/carbon/human/crew)
	if(QDELETED(container) || container.opened || container.welded || container.broken)
		return FALSE
	if(container.locked && !container.allowed(crew))
		return FALSE
	// Somebody standing in it is a person, not a haul.
	for(var/mob/living/inside in container)
		return FALSE
	return TRUE

/// Everything in the container this person would actually take.
/proc/sp_tempting_contents(obj/structure/closet/container, datum/ai_controller/sp_crew/controller)
	var/list/obj/item/wanted = list()
	if(QDELETED(container) || isnull(controller))
		return wanted
	for(var/obj/item/thing in container.contents)
		if(controller.wants_item(thing))
			wanted += thing
	return wanted

// --- Doors -----------------------------------------------------------------------------------------

/**
 * A door we cannot open. The point is the rebuff, so this deliberately looks for one that will refuse
 * us — an ordinary crew member finds out the hard way that engineering is not for them.
 */
/proc/sp_find_door_to_try(mob/living/carbon/human/crew, list/ignored)
	if(QDELETED(crew))
		return null
	var/obj/machinery/door/airlock/best
	var/best_distance = INFINITY
	for(var/obj/machinery/door/airlock/candidate in oview(SP_CURIOSITY_RANGE, crew))
		if(!candidate.density || candidate.operating || (candidate.obj_flags & EMAGGED))
			continue
		if(!length(candidate.req_access) && !length(candidate.req_one_access))
			continue // a public door tells us nothing
		if(candidate.allowed(crew))
			continue
		if(ignored?[candidate] > world.time)
			continue
		var/distance = get_dist(crew, candidate)
		if(distance < best_distance)
			best = candidate
			best_distance = distance
	return best
