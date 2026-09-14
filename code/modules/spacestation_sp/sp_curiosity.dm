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

/**
 * Opens a container, takes what this person fancies out of it, and shuts it again unless they are the
 * sort to leave it hanging open. Returns the names of what was taken. Sleeps.
 */
/proc/sp_rummage_container(datum/ai_controller/sp_crew/controller, obj/structure/closet/container)
	var/mob/living/carbon/human/pawn = controller?.pawn
	var/list/names = list()
	if(!istype(pawn) || QDELETED(container))
		return names
	sp_free_hands(pawn)
	// What we fancy, picked out before it is opened: TG's closets tip their whole contents onto the floor
	// as they open, so a look inside afterwards finds an empty box and everybody goes home empty-handed.
	var/list/obj/item/tempting = sp_tempting_contents(container, controller)
	var/unlocked_it = FALSE
	if(container.locked)
		sp_ai_click(controller, container, list(RIGHT_CLICK = "1"))
		unlocked_it = !container.locked
	if(!container.opened)
		sp_ai_click(controller, container)
	if(!container.opened)
		sp_relock(controller, container, unlocked_it)
		return names
	var/taken = 0
	for(var/obj/item/thing as anything in tempting)
		if(taken >= controller.rummage_take_limit())
			break
		if(QDELETED(thing))
			continue
		if(!(pawn.back && thing.forceMove(pawn.back)) && !pawn.put_in_hands(thing))
			continue
		names |= thing.name
		taken++
	// Shut it behind us. An ordinary crew member is nosy, not a vandal; leaving lockers hanging open is a
	// greytide tell, and the assistants do (closes_lockers()).
	if(container.opened && controller.closes_lockers())
		sp_ai_click(controller, container)
	sp_relock(controller, container, unlocked_it)
	return names

/**
 * Locks a closet again if we were the ones who unlocked it. A research director who took their headset out and
 * left the locker unlocked behind them left it for the next scientist to help themselves, and one did.
 * Sleeps, like any click.
 */
/proc/sp_relock(datum/ai_controller/controller, obj/structure/closet/container, unlocked_it)
	if(!unlocked_it || QDELETED(container) || container.opened || container.locked)
		return
	sp_ai_click(controller, container, list(RIGHT_CLICK = "1"))

// --- Things lying about ----------------------------------------------------------------------------

/**
 * Rooms where something on the floor is somebody's work in progress rather than a find: the botanist's
 * harvest lands at their feet before they gather it, and the chef stocks up off the kitchen floor.
 */
GLOBAL_LIST_INIT(sp_no_pocketing_areas, typecacheof(list(
	/area/station/service/hydroponics,
	/area/station/service/kitchen,
)))

/**
 * Something worth picking up off the floor. Only the floor: anything on a table or a rack was put there
 * by somebody — the chef's ingredients, the chemist's patches, a beaker of cryoxadone waiting for a tube —
 * and helping yourself to that is theft rather than magpie curiosity.
 */
/proc/sp_find_loose_item(mob/living/carbon/human/crew, datum/ai_controller/sp_crew/controller, list/ignored)
	if(QDELETED(crew) || isnull(controller))
		return null
	var/obj/item/best
	var/best_distance = INFINITY
	for(var/obj/item/thing in oview(SP_CURIOSITY_RANGE, crew))
		if(!isturf(thing.loc) || thing.anchored)
			continue
		if(ignored?[thing] > world.time)
			continue
		if((locate(/obj/structure/table) in thing.loc) || (locate(/obj/structure/rack) in thing.loc))
			continue
		// Held in a variable: is_type_in_typecache() is a macro, and a get_area() call inside it does not parse.
		var/area/thing_area = get_area(thing)
		if(is_type_in_typecache(thing_area, GLOB.sp_no_pocketing_areas))
			continue
		if(!controller.wants_item(thing))
			continue
		var/distance = get_dist(crew, thing)
		if(distance >= best_distance)
			continue
		best = thing
		best_distance = distance
	return best

/// Picks something up off the floor: into the bag if it fits, otherwise a hand. TRUE if we have it.
/proc/sp_pocket_loose_item(datum/ai_controller/sp_crew/controller, obj/item/thing)
	var/mob/living/carbon/human/pawn = controller.pawn
	if(!istype(pawn) || QDELETED(thing))
		return FALSE
	var/thing_name = thing.name
	if(!(pawn.back && thing.forceMove(pawn.back)) && !pawn.put_in_hands(thing))
		return FALSE
	sp_record("crew.pocketed")
	log_sp("[pawn.real_name] picked [thing_name] up off the floor in [get_area_name(pawn)]")
	controller.remark_on_find(list(thing_name))
	return TRUE

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
