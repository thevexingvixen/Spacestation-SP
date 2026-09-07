/**
 * Hull breach detection and repair.
 *
 * A breach is a space turf inside a pressurised station area that still has a real floor next to it,
 * which is exactly what a hole punched in the hull looks like. Solar arrays, catwalks and other
 * deliberately-open areas are made of space turfs with no adjacent floor, so they never match.
 *
 * Scanning is rolling: SSspacestation_sp walks a slice of the station's areas on each watchdog tick,
 * so a full sweep costs almost nothing per tick. AI engineers pull from the resulting cache, walk to
 * a safe tile next to the hole and patch it with the RCD every engineer spawns with.
 */

/// Areas that are meant to be open to space; never treated as breached.
GLOBAL_LIST_INIT(sp_breach_area_blacklist, typecacheof(list(
	/area/station/solars,
	/area/station/engineering/atmos/space_catwalk,
	/area/station/maintenance/external,
)))

/// Builds (once) the list of station areas the breach scanner walks.
/proc/sp_breach_scan_areas()
	var/list/areas = list()
	for(var/area/candidate as anything in GLOB.areas)
		if(!(candidate.type in GLOB.the_station_areas))
			continue
		if(is_type_in_typecache(candidate, GLOB.sp_breach_area_blacklist))
			continue
		areas += candidate
	return areas

/// TRUE if this space turf looks like a hole in the hull rather than open space by design.
/proc/sp_is_breach_turf(turf/candidate)
	if(!isspaceturf(candidate) || !is_station_level(candidate.z))
		return FALSE
	var/area/candidate_area = get_area(candidate)
	if(isnull(candidate_area) || !(candidate_area.type in GLOB.the_station_areas))
		return FALSE
	if(is_type_in_typecache(candidate_area, GLOB.sp_breach_area_blacklist))
		return FALSE
	// A real floor next to it means this used to be inside the station.
	for(var/turf/open/floor/neighbour in RANGE_TURFS(1, candidate))
		var/area/neighbour_area = get_area(neighbour)
		if(isnull(neighbour_area) || !(neighbour_area.type in GLOB.the_station_areas))
			continue
		if(is_type_in_typecache(neighbour_area, GLOB.sp_breach_area_blacklist))
			continue
		return TRUE
	return FALSE

/// A safe, walkable, pressurised-side turf an engineer can stand on to patch `breach`. Null if there is none.
/proc/sp_breach_standpoint(turf/breach, mob/living/repairer)
	var/turf/best
	var/best_pressure = 0
	for(var/turf/open/floor/candidate in RANGE_TURFS(1, breach))
		if(candidate == breach || candidate.density)
			continue
		if(candidate.is_blocked_turf(exclude_mobs = TRUE))
			continue
		if(!isnull(repairer) && !candidate.can_cross_safely(repairer))
			continue
		var/datum/gas_mixture/air = candidate.return_air()
		var/pressure = air ? air.return_pressure() : 0
		if(isnull(best) || pressure > best_pressure)
			best = candidate
			best_pressure = pressure
	return best

/// Nearest known breach to `who` on the same z-level that still needs patching, or null.
/proc/sp_find_nearest_breach(mob/living/who, list/ignored)
	var/turf/origin = get_turf(who)
	if(isnull(origin))
		return null
	var/turf/best
	var/best_distance = INFINITY
	for(var/turf/breach as anything in SSspacestation_sp.breach_turfs)
		if(!sp_is_breach_turf(breach) || breach.z != origin.z)
			continue
		var/retry_at = LAZYACCESS(ignored, breach)
		if(!isnull(retry_at) && retry_at > world.time)
			continue
		if(isnull(sp_breach_standpoint(breach, who)))
			continue
		var/distance = get_dist(origin, breach)
		if(distance < best_distance)
			best = breach
			best_distance = distance
	return best

/**
 * Puts a breath mask on and opens an emergency tank, so working next to vacuum is survivable.
 * Best effort: returns TRUE if we are breathing from a tank afterwards.
 */
/proc/sp_open_internals(mob/living/carbon/human/who)
	if(!istype(who))
		return FALSE
	if(who.internal)
		return TRUE
	if(isnull(who.wear_mask))
		var/obj/item/clothing/mask/breath/mask = locate() in who.get_all_contents_type(/obj/item/clothing/mask/breath)
		if(mask)
			who.equip_to_slot_if_possible(mask, ITEM_SLOT_MASK, disable_warning = TRUE)
	if(!who.can_breathe_internals())
		return FALSE
	var/list/tanks = who.get_all_contents_type(/obj/item/tank/internals)
	if(!length(tanks))
		return FALSE
	return !!who.open_internals(tanks[1])

/// Stops breathing from the tank once the job is done, so it is still full next time.
/proc/sp_close_internals(mob/living/carbon/human/who)
	if(istype(who) && who.internal)
		who.close_internals()

/**
 * Fires the RCD at `breach` to lay plating over it. Returns TRUE if the hole is gone afterwards.
 * The RCD must already be in the engineer's active hand.
 */
/proc/sp_patch_breach(mob/living/carbon/human/engineer, turf/breach)
	if(QDELETED(engineer) || !isspaceturf(breach))
		return FALSE
	var/obj/item/construction/rcd/device = engineer.get_active_held_item()
	if(!istype(device))
		return FALSE
	if(!breach.Adjacent(engineer))
		return FALSE
	// Plating over space: instant, 3 matter (1 if a lattice is already there).
	device.construction_mode = RCD_TURF
	device.rcd_design_path = /turf/open/floor/plating/rcd
	engineer.face_atom(breach)
	device.interact_with_atom(breach, engineer)
	var/turf/patched = get_turf(breach)
	if(isspaceturf(patched))
		return FALSE
	SSspacestation_sp.breach_turfs -= breach
	log_sp("[engineer.real_name] patched a hull breach at [AREACOORD(patched)]")
	return TRUE

/**
 * Patches `breach` and then every other hole still within reach, so a five-tile hull rupture is sealed
 * in one visit instead of one full plan-and-walk cycle per tile. Returns how many turfs were sealed.
 */
/proc/sp_patch_breach_cluster(mob/living/carbon/human/engineer, turf/breach, max_patches = 9)
	var/sealed = 0
	if(!sp_patch_breach(engineer, breach))
		return 0
	sealed++
	while(sealed < max_patches)
		var/turf/next_hole
		for(var/turf/candidate in RANGE_TURFS(1, engineer))
			if(isspaceturf(candidate) && candidate.Adjacent(engineer) && sp_is_breach_turf(candidate))
				next_hole = candidate
				break
		if(isnull(next_hole) || !sp_patch_breach(engineer, next_hole))
			break
		sealed++
	return sealed

/// Debug helper: punches `count` holes in a random pressurised station room. Used by SP_DEBUG_BREACH_COUNT.
/proc/sp_debug_make_breach(count = 3)
	var/list/candidates = list()
	for(var/area/room as anything in sp_breach_scan_areas())
		if(!length(room.turfs_by_zlevel))
			continue
		candidates += room
	if(!length(candidates))
		return 0
	var/made = 0
	for(var/attempt in 1 to 20)
		var/area/room = pick(candidates)
		var/list/turfs = room.get_turfs_from_all_zlevels()
		if(!length(turfs))
			continue
		var/turf/start
		for(var/i in 1 to 30)
			var/turf/candidate = pick(turfs)
			if(istype(candidate, /turf/open/floor) && is_station_level(candidate.z) && !candidate.is_blocked_turf(exclude_mobs = TRUE))
				start = candidate
				break
		if(isnull(start))
			continue
		for(var/turf/victim in RANGE_TURFS(1, start))
			if(made >= count)
				break
			if(!istype(victim, /turf/open/floor))
				continue
			victim.ChangeTurf(/turf/open/space)
			made++
		if(made >= count)
			log_sp("debug: punched [made] hull breaches in [room.name]")
			return made
	log_sp("debug: punched [made] hull breaches")
	return made
