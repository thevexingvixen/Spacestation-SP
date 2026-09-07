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
	var/area/home = get_area(crew)
	if(home)
		controller.set_blackboard_key(BB_SP_HOME_AREA, home)

	SSspacestation_sp.register_crew(crew)
	log_sp("spawned AI crew [crew.real_name] as [job.title] at [AREACOORD(crew)]")
	return crew

/// Picks the AI controller type for a job based on its department.
/proc/sp_controller_for_job(datum/job/job)
	if(/datum/job_department/medical in job.departments_list)
		return /datum/ai_controller/sp_crew/medical
	if(/datum/job_department/security in job.departments_list)
		return /datum/ai_controller/sp_crew/security
	if(/datum/job_department/engineering in job.departments_list)
		return /datum/ai_controller/sp_crew/engineer
	if(istype(job, /datum/job/botanist))
		return /datum/ai_controller/sp_crew/botanist
	return /datum/ai_controller/sp_crew

/**
 * Jobs the station cannot do without; populate fills one of each before anything else (after heads).
 * The botanist is here because they feed the kitchen, and a station with nobody growing anything is a
 * station where the chef has nothing to cook.
 */
/proc/sp_essential_job_types()
	var/static/list/essential = list(
		/datum/job/station_engineer,
		/datum/job/security_officer,
		/datum/job/doctor,
		/datum/job/botanist,
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

	// Heads first, then one of each essential job (engineer, security, doctor), then everyone else shuffled.
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
	var/list/datum/job/order = shuffle(heads) + essentials + shuffle(rest)

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
