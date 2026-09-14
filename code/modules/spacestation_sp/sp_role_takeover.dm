/**
 * Spacestation SP — a player takes a role from the AI crew.
 *
 * The AI crew fill the station's jobs at roundstart, and TG counts them exactly like players: a job they
 * hold is full, and the join screen greys it out. In a singleplayer game that locks the one real player out
 * of the CMO's office, the bar and every head of staff. Here a job held by AI crew is never locked. A player
 * who picks it on the join screen gets it, and one of the AI crew in that job goes off shift: off the
 * manifest, bank account closed, slot handed over. At roundstart this never comes up, because TG hands
 * readied players their jobs before the station is populated.
 *
 * TG has no way to free a job slot (no cryo, and nothing ever decrements current_positions), so the
 * clean-up here is our own, along the lines of the admin "retcon" smite.
 */

/**
 * The AI crew holding a job, in the order they give it up: the dead first, whose place is only a number by
 * now, then anyone not in the middle of a job, then the rest.
 */
/proc/sp_ai_crew_in_job(datum/job/job)
	var/list/dead = list()
	var/list/idle = list()
	var/list/busy = list()
	if(isnull(job))
		return dead
	for(var/mob/living/carbon/human/crew as anything in SSspacestation_sp.ai_crew)
		if(QDELETED(crew) || crew.mind?.assigned_role != job)
			continue
		if(crew.stat == DEAD)
			dead += crew
			continue
		var/datum/ai_controller/sp_crew/controller = crew.ai_controller
		if(istype(controller) && controller.busy_with_work())
			busy += crew
		else
			idle += crew
	return dead + idle + busy

/**
 * Frees one place in a job that AI crew hold, for a player joining as it. A dead holder just stops counting
 * against the job and their body stays where it is; a living one goes off shift. Returns TRUE if a place was
 * freed.
 */
/proc/sp_free_slot_from_ai(datum/job/job)
	var/list/holders = sp_ai_crew_in_job(job)
	if(!length(holders))
		return FALSE
	var/mob/living/carbon/human/crew = holders[1]
	job.current_positions = max(job.current_positions - 1, 0)
	// Out of the AI crew list at once, so a second player joining a moment later cannot take the same place.
	SSspacestation_sp.ai_crew -= crew
	if(crew.stat == DEAD)
		log_sp("[crew.real_name]'s place as [job.title] went to a player; their body stays where it is")
		return TRUE
	sp_send_off_shift(crew, job)
	return TRUE

/**
 * Takes a living AI crew member off the station for good: they say so, drop off the manifest, their bank
 * account closes, and a moment later they are gone.
 */
/proc/sp_send_off_shift(mob/living/carbon/human/crew, datum/job/job)
	var/datum/ai_controller/sp_crew/controller = crew.ai_controller
	if(istype(controller))
		controller.on_sent_off_shift()
		controller.set_ai_status(AI_STATUS_OFF)
	sp_crew_speak(crew, pick(
		"Looks like my relief is here. I'm off shift.",
		"That's my replacement arriving. I'm clocking out.",
		"Somebody's taking over as [LOWER_TEXT(job.title)]. I'm off.",
	))
	var/datum/record/locked/locked_record = find_record(crew.real_name, locked_only = TRUE)
	if(locked_record)
		qdel(locked_record)
	GLOB.manifest.remove(crew.real_name)
	var/datum/bank_account/account = SSeconomy.bank_accounts_by_id["[crew.account_id]"]
	if(account)
		qdel(account)
	sp_record("crew.relieved")
	log_sp("[crew.real_name] went off shift so a player could be [job.title]")
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(sp_finish_off_shift), crew, crew.mind), 2 SECONDS)

/// The end of going off shift: the crew member, and the mind TG would otherwise keep, leave the round.
/proc/sp_finish_off_shift(mob/living/carbon/human/crew, datum/mind/mind)
	if(!QDELETED(crew))
		qdel(crew)
	if(!QDELETED(mind))
		qdel(mind)

/**
 * A job that is full only because AI crew hold it is open to a player. TG stops at "full" before its other
 * checks (bans, playtime, the latejoin special cases), so those run here instead.
 */
/mob/dead/new_player/IsJobUnavailable(rank, latejoin = FALSE)
	. = ..()
	if(. != JOB_UNAVAILABLE_SLOTFULL)
		return
	var/datum/job/job = SSjob.get_job(rank)
	if(!length(sp_ai_crew_in_job(job)))
		return
	var/eligibility_check = SSjob.check_job_eligibility(src, job, "Mob IsJobUnavailable")
	if(eligibility_check != JOB_AVAILABLE)
		return eligibility_check
	if(latejoin && !job.special_check_latejoin(client))
		return JOB_UNAVAILABLE_GENERIC
	return JOB_AVAILABLE

/**
 * A player joining late as a job the AI crew fill takes one of their places, just before TG gives them the
 * job: after every check that could still turn them away, so nobody is sent off shift for a join that fails.
 */
/datum/controller/subsystem/job/assign_role(mob/dead/new_player/player, datum/job/job, latejoin = FALSE, do_eligibility_checks = TRUE)
	if(latejoin && player?.mind && job && job.total_positions != -1 && job.current_positions >= job.total_positions)
		if(!do_eligibility_checks || check_job_eligibility(player, job, "SP") == JOB_AVAILABLE)
			sp_free_slot_from_ai(job)
	return ..()

/// The join screen counts a job's AI crew as open places, so the numbers match what a player can take.
/datum/latejoin_menu/ui_data(mob/user)
	var/list/data = ..()
	var/list/departments = data["departments"]
	for(var/department_name in departments)
		var/list/department_data = departments[department_name]
		var/list/department_jobs = department_data["jobs"]
		for(var/title in department_jobs)
			var/datum/job/job = SSjob.get_job(title)
			if(isnull(job) || job.total_positions < 0)
				continue
			var/held_by_ai = length(sp_ai_crew_in_job(job))
			if(!held_by_ai)
				continue
			var/players = max(job.current_positions - held_by_ai, 0)
			var/list/job_data = department_jobs[title]
			job_data["used_slots"] = players
			if(isnum(department_data["open_slots"]))
				department_data["open_slots"] += max(job.total_positions - players, 0) - max(job.total_positions - job.current_positions, 0)
	return data
