/**
 * Botany helpers.
 *
 * The AI botanist runs a full crop cycle: plant an empty tray, keep it watered and weeded, pull the
 * dead plants, harvest what is ready, then carry the produce to the kitchen so the chef has something
 * to cook with. Everything is done through the same interactions a player uses, so trays, seeds and
 * produce behave exactly as they normally would.
 */

/// Seeds an SP botanist starts with. Weighted towards things the chef can actually cook, with a few
/// oddities so the garden is not the same every round. What they plant is picked at random from here.
GLOBAL_LIST_INIT(sp_botany_seed_pool, list(
	// Kitchen staples: the chef needs these.
	/obj/item/seeds/tomato = 3,
	/obj/item/seeds/potato = 3,
	/obj/item/seeds/carrot = 3,
	/obj/item/seeds/wheat = 3,
	/obj/item/seeds/corn = 2,
	/obj/item/seeds/cabbage = 2,
	/obj/item/seeds/onion = 2,
	/obj/item/seeds/chili = 2,
	/obj/item/seeds/soya = 2,
	/obj/item/seeds/apple = 2,
	/obj/item/seeds/banana = 1,
	/obj/item/seeds/berry = 2,
	/obj/item/seeds/watermelon = 1,
	/obj/item/seeds/pumpkin = 1,
	/obj/item/seeds/eggplant = 1,
	/obj/item/seeds/garlic = 1,
	// Botanist's own interests. Whether any of this is legal is Security's problem, not botany's.
	/obj/item/seeds/ambrosia = 1,
	/obj/item/seeds/sunflower = 1,
	/obj/item/seeds/poppy = 1,
	/obj/item/seeds/cannabis = 1,
	/obj/item/seeds/tobacco = 1,
	/obj/item/seeds/tea = 1,
	/obj/item/seeds/coffee = 1,
	/obj/item/seeds/glowshroom = 1,
))

/// Below this water level a tray is worth topping up.
#define SP_TRAY_WATER_THRESHOLD 30
/// Above this weed level a tray is worth hoeing.
#define SP_TRAY_WEED_THRESHOLD 2

/// Areas the botanist works in.
/proc/sp_botany_areas()
	var/static/list/areas = list(
		/area/station/service/hydroponics,
		/area/station/service/hydroponics/upper,
		/area/station/service/hydroponics/garden,
	)
	return areas

/// What, if anything, this tray needs from us right now. Null when it is fine or we cannot help.
/proc/sp_tray_job(obj/machinery/hydroponics/tray, mob/living/carbon/human/botanist)
	if(QDELETED(tray))
		return null
	if(tray.plant_status == HYDROTRAY_PLANT_HARVESTABLE)
		return SP_TRAY_JOB_HARVEST
	if(tray.plant_status == HYDROTRAY_PLANT_DEAD)
		return SP_TRAY_JOB_CLEAR
	if(tray.weedlevel > SP_TRAY_WEED_THRESHOLD && length(botanist.get_all_contents_type(/obj/item/cultivator)))
		return SP_TRAY_JOB_WEED
	if(!isnull(tray.myseed) && tray.waterlevel < SP_TRAY_WATER_THRESHOLD && sp_botany_watering_can(botanist, TRUE))
		return SP_TRAY_JOB_WATER
	if(isnull(tray.myseed) && length(botanist.get_all_contents_type(/obj/item/seeds)))
		return SP_TRAY_JOB_PLANT
	return null

/// The botanist's watering can. Pass TRUE to require that it still holds water.
/proc/sp_botany_watering_can(mob/living/carbon/human/botanist, needs_water = FALSE)
	for(var/obj/item/reagent_containers/cup/watering_can/can as anything in botanist.get_all_contents_type(/obj/item/reagent_containers/cup/watering_can))
		if(!needs_water || can.reagents?.has_reagent(/datum/reagent/water, 5))
			return can
	return null

/// The nearest tray in view that wants attention, along with the job it wants. Returns a list(tray, job).
/proc/sp_find_tray_job(mob/living/carbon/human/botanist, range = 12)
	var/obj/machinery/hydroponics/best_tray
	var/best_job
	var/best_distance = INFINITY
	for(var/obj/machinery/hydroponics/tray in oview(range, botanist))
		var/job = sp_tray_job(tray, botanist)
		if(isnull(job))
			continue
		var/distance = get_dist(botanist, tray)
		// Harvesting beats everything else at equal distance: ripe plants rot and block the tray.
		if(job == SP_TRAY_JOB_HARVEST)
			distance -= 6
		if(distance >= best_distance)
			continue
		best_tray = tray
		best_job = job
		best_distance = distance
	if(isnull(best_tray))
		return null
	return list(best_tray, best_job)

/// A seed to plant, picked at random from what the botanist is carrying.
/proc/sp_pick_seed(mob/living/carbon/human/botanist)
	var/list/seeds = botanist.get_all_contents_type(/obj/item/seeds)
	// Grafts and other seed subtypes that are not plantable packets would just fail on the tray.
	for(var/obj/item/seeds/candidate in seeds)
		if(isnull(candidate.plantname))
			seeds -= candidate
	return length(seeds) ? pick(seeds) : null

/// Produce lying loose on the floor near the botanist, nearest first.
/proc/sp_find_loose_produce(mob/living/carbon/human/botanist, range = 4)
	var/obj/item/food/grown/best
	var/best_distance = INFINITY
	for(var/obj/item/food/grown/produce in oview(range, botanist))
		if(!isturf(produce.loc))
			continue
		var/distance = get_dist(botanist, produce)
		if(distance < best_distance)
			best = produce
			best_distance = distance
	return best

/// How much produce the botanist is carrying.
/proc/sp_carried_produce(mob/living/carbon/human/botanist)
	return botanist.get_all_contents_type(/obj/item/food/grown)

/// A table in the kitchen to leave produce on, or null if we cannot find one on our z-level.
/proc/sp_find_kitchen_table(mob/living/carbon/human/botanist)
	var/turf/origin = get_turf(botanist)
	if(isnull(origin))
		return null
	var/static/list/kitchen_areas = list(/area/station/service/kitchen, /area/station/service/kitchen/diner)
	var/obj/structure/table/best
	var/best_distance = INFINITY
	for(var/area_type in kitchen_areas)
		for(var/turf/candidate as anything in get_area_turfs(area_type, origin.z))
			var/obj/structure/table/table = locate() in candidate
			if(isnull(table))
				continue
			var/distance = get_dist(origin, table)
			if(distance < best_distance)
				best = table
				best_distance = distance
	return best

/// A table in hydroponics to display sample produce on.
/proc/sp_find_sample_table(mob/living/carbon/human/botanist)
	var/turf/origin = get_turf(botanist)
	if(isnull(origin))
		return null
	var/obj/structure/table/best
	var/best_distance = INFINITY
	for(var/area_type in sp_botany_areas())
		for(var/turf/candidate as anything in get_area_turfs(area_type, origin.z))
			var/obj/structure/table/table = locate() in candidate
			if(isnull(table))
				continue
			var/distance = get_dist(origin, table)
			if(distance < best_distance)
				best = table
				best_distance = distance
	return best

/// The nearest thing we can refill a watering can from.
/proc/sp_find_water_source(mob/living/carbon/human/botanist, range = 20)
	var/obj/structure/reagent_dispensers/best
	var/best_distance = INFINITY
	for(var/obj/structure/reagent_dispensers/source in oview(range, botanist))
		if(!source.reagents?.has_reagent(/datum/reagent/water, 10))
			continue
		var/distance = get_dist(botanist, source)
		if(distance < best_distance)
			best = source
			best_distance = distance
	return best

#undef SP_TRAY_WATER_THRESHOLD
#undef SP_TRAY_WEED_THRESHOLD
