/**
 * Client-less crew spawning.
 *
 * TG's normal spawn path (/mob/dead/new_player/create_character -> job.get_spawn_mob) assumes a client and
 * deletes the mob otherwise, so we reimplement the small part we need: make a human, randomize them,
 * give them a mind and a job, equip them through the normal SSjob.equip_rank path (which is null-client safe),
 * add them to the crew manifest, then hand them to an AI controller.
 */

/**
 * Spawns one AI-controlled human crew member for `job`.
 *
 * * job - the /datum/job to spawn as
 * * spawn_point - optional atom to spawn at; defaults to the job's roundstart (or latejoin) spawn point
 * * latejoin - use latejoin spawn points (arrivals) instead of roundstart ones
 * * controller_type - the /datum/ai_controller subtype to attach
 *
 * Returns the spawned human, or null on failure.
 */
/proc/sp_spawn_crew_member(datum/job/job, atom/spawn_point, latejoin = FALSE, controller_type = null)
	if(isnull(job))
		return null
	if(isnull(controller_type))
		controller_type = sp_controller_for_job(job)
	if(job.spawn_type != /mob/living/carbon/human)
		return null // silicons and other snowflakes are out of scope for now

	if(isnull(spawn_point))
		spawn_point = latejoin ? job.get_latejoin_spawn_point() : job.get_roundstart_spawn_point()
	var/turf/spawn_turf = get_turf(spawn_point)
	if(isnull(spawn_turf))
		log_sp("no spawn turf for [job.title], skipping")
		return null

	var/mob/living/carbon/human/crew = new(spawn_turf)
	spawn_point.JoinPlayerHere(crew, TRUE)
	randomize_human_normie(crew)

	// Mind + role. mind_initialize() works with no key: it creates the mind and adds it to SSticker.minds.
	crew.mind_initialize()
	SSjob.equip_rank(crew, job, null)
	job.current_positions++

	// Crew manifest / records (inject() no-ops for jobs without JOB_CREW_MANIFEST).
	GLOB.manifest.inject(crew)
	SEND_SIGNAL(crew, COMSIG_HUMAN_CHARACTER_SETUP_FINISHED)

	// AI
	var/datum/ai_controller/sp_crew/controller = new controller_type(crew)
	if(istype(controller))
		controller.equip_extra_gear(crew)
	controller.set_blackboard_key(BB_SP_JOB_TITLE, job.title)
	sp_send_to_post(crew, controller)
	var/area/home = get_area(crew)
	if(home)
		controller.set_blackboard_key(BB_SP_HOME_AREA, home)

	SSspacestation_sp.register_crew(crew)
	log_sp("spawned AI crew [crew.real_name] as [job.title] at [AREACOORD(crew)]")
	return crew

/**
 * Puts a new crew member at their post if the job's own spawn point dropped them at arrivals.
 *
 * SSticker.PostSetup() deletes the roundstart landmarks the moment we yield, and we do not reliably win
 * that race — when we lose it, every job falls back to the arrival shuttle. That is worse than untidy:
 * the shuttle leaves, and it takes the whole crew with it to a z-level their department is not on.
 * Nobody is watching at this point in the round, so placing them where they were assigned is both
 * honest and the only thing that works.
 *
 * Assistants have no department to start in, and one of MetaStation's assistant spawn points is inside
 * the cargo delivery office, behind shipping-access doors and delivery flaps that no standing person gets
 * through. A player crawls under the flaps; the assistant who spawned there spent the round walking into
 * them. An assistant who starts anywhere but their usual haunts starts in one of those instead.
 */
/proc/sp_send_to_post(mob/living/carbon/human/crew, datum/ai_controller/sp_crew/controller)
	var/area/where = get_area(crew)
	var/list/post_areas = controller?.blackboard[BB_SP_WANDER_AREAS]
	if(isnull(where) || !length(post_areas))
		return FALSE
	var/stranded = istype(where, /area/shuttle/arrival) || istype(where, /area/station/hallway/secondary/entry)
	var/shut_in = istype(controller, /datum/ai_controller/sp_crew/assistant) && !(where.type in post_areas)
	if(!stranded && !shut_in)
		return FALSE
	var/turf/here = get_turf(crew)
	for(var/area_type in shuffle(post_areas.Copy()))
		var/list/turf/candidates = get_area_turfs(area_type, here?.z)
		if(!length(candidates))
			continue
		for(var/i in 1 to 20)
			var/turf/spot = pick(candidates)
			if(spot.density || isgroundlessturf(spot) || spot.is_blocked_turf(exclude_mobs = TRUE))
				continue
			crew.forceMove(spot)
			log_sp("[crew.real_name] was assigned to [get_area_name(spot)] rather than left in [where.name]")
			return TRUE
	return FALSE

/// Picks the AI controller type for a job based on its department.
/proc/sp_controller_for_job(datum/job/job)
	if(is_assistant_job(job))
		return /datum/ai_controller/sp_crew/assistant
	if(istype(job, /datum/job/chemist))
		return /datum/ai_controller/sp_crew/medical/chemist
	if(/datum/job_department/medical in job.departments_list)
		return /datum/ai_controller/sp_crew/medical
	// The head of security gives the orders the rest of the department answers to, so they get a controller
	// of their own. Tested before the department, the way the chemist is tested before medical.
	if(istype(job, /datum/job/head_of_security))
		return /datum/ai_controller/sp_crew/security/hos
	if(/datum/job_department/security in job.departments_list)
		return /datum/ai_controller/sp_crew/security
	if(/datum/job_department/engineering in job.departments_list)
		return /datum/ai_controller/sp_crew/engineer
	if(istype(job, /datum/job/clown))
		return /datum/ai_controller/sp_crew/clown
	if(istype(job, /datum/job/janitor))
		return /datum/ai_controller/sp_crew/janitor
	if(istype(job, /datum/job/botanist))
		return /datum/ai_controller/sp_crew/botanist
	if(istype(job, /datum/job/cook))
		return /datum/ai_controller/sp_crew/chef
	if(istype(job, /datum/job/bartender))
		return /datum/ai_controller/sp_crew/bartender
	if(istype(job, /datum/job/quartermaster))
		return /datum/ai_controller/sp_crew/cargo/quartermaster
	if(/datum/job_department/cargo in job.departments_list)
		return /datum/ai_controller/sp_crew/cargo
	return /datum/ai_controller/sp_crew

/**
 * Jobs the station cannot do without; populate fills one of each before anything else (after heads).
 * Botany and the kitchen are here because they feed each other: a station with nobody growing anything
 * is a station where the chef has nothing to cook, and a station with no chef is one where the crew
 * eat out of a vending machine all shift.
 */
/proc/sp_essential_job_types()
	var/static/list/essential = list(
		/datum/job/station_engineer,
		/datum/job/security_officer,
		/datum/job/doctor,
		/datum/job/chemist,
		/datum/job/botanist,
		/datum/job/cook,
		/datum/job/bartender,
		/datum/job/quartermaster,
		/datum/job/cargo_technician,
	)
	return essential

/// Returns the list of jobs an AI crew member may be spawned as: joinable, human, station crew.
/proc/sp_get_crew_job_pool()
	var/list/datum/job/pool = list()
	for(var/datum/job/job as anything in SSjob.joinable_occupations)
		if(!(job.job_flags & JOB_CREW_MEMBER))
			continue
		if(job.spawn_type != /mob/living/carbon/human)
			continue
		if(job.spawn_positions == 0)
			continue
		// Assistants come separately, as many as SP_ASSISTANTS_MIN and MAX say (sp_spawn_assistants).
		if(is_assistant_job(job))
			continue
		pool += job
	return pool

/**
 * Spawns `count` AI crew spread across the job pool, respecting each job's spawn_positions.
 * Heads of staff are filled first so the station has a command structure, then the rest round-robin.
 * Returns the number actually spawned.
 */
/proc/sp_populate_station(count = 10, latejoin = null)
	if(isnull(latejoin))
		latejoin = SSticker.HasRoundStarted()

	var/list/datum/job/pool = sp_get_crew_job_pool()
	if(!length(pool))
		log_sp("job pool is empty, cannot populate")
		return 0

	// Heads first so the station has a command structure, then one of each essential job, then the rest
	// shuffled. There are seven heads and nine essentials, so SP_AUTOPOPULATE below 16 will not staff
	// every department.
	var/list/datum/job/heads = list()
	var/list/datum/job/essentials = list()
	var/list/datum/job/rest = list()
	var/list/essential_types = sp_essential_job_types()
	for(var/datum/job/job as anything in pool)
		if(job.job_flags & JOB_HEAD_OF_STAFF)
			heads += job
		else if(job.type in essential_types)
			essentials += job
		else
			rest += job
	// Essentials go in the order sp_essential_job_types() lists them rather than whatever order the job
	// controller happens to hold: that list is a priority ranking, and a low SP_AUTOPOPULATE will not
	// reach the end of it.
	var/list/datum/job/ranked_essentials = list()
	for(var/essential_type in essential_types)
		for(var/datum/job/job as anything in essentials)
			if(job.type == essential_type)
				ranked_essentials += job
				break
	var/list/datum/job/order = shuffle(heads) + ranked_essentials + shuffle(rest)

	var/spawned = 0
	var/index = 0
	var/safety = count * 4 + length(order)
	while(spawned < count && length(order) && safety-- > 0)
		index = (index % length(order)) + 1
		var/datum/job/job = order[index]
		if(job.spawn_positions != -1 && job.current_positions >= job.spawn_positions)
			order -= job
			index-- // the list shifted left under us; re-check the same slot
			continue
		var/mob/living/carbon/human/crew = sp_spawn_crew_member(job, latejoin = latejoin)
		if(isnull(crew))
			order -= job
			index--
			continue
		spawned++
		// Deliberately no CHECK_TICK: at round start we run from an async OnRoundstart callback and
		// SSticker.PostSetup() deletes the roundstart landmarks as soon as we yield. Spawning the whole
		// batch in one tick keeps everyone in their department instead of falling back to arrivals.
	return spawned

/// Spawns `count` AI assistants, the station's greytide. Returns how many made it.
/proc/sp_spawn_assistants(count, latejoin = null)
	if(isnull(latejoin))
		latejoin = SSticker.HasRoundStarted()
	var/datum/job/assistant = SSjob.get_job_type(/datum/job/assistant)
	if(isnull(assistant))
		return 0
	var/spawned = 0
	for(var/i in 1 to count)
		if(isnull(sp_spawn_crew_member(assistant, latejoin = latejoin)))
			break
		spawned++
	return spawned
