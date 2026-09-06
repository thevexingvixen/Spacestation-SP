ADMIN_VERB(sp_populate_station, R_SPAWN, "SP: Populate Station", "Spawn AI-controlled crew members across the joinable station jobs.", ADMIN_CATEGORY_FUN)
	var/count = tgui_input_number(user, "How many AI crew members should be spawned?", "Populate Station", default = 10, max_value = 60, min_value = 1)
	if(isnull(count))
		return
	var/spawned = sp_populate_station(count)
	message_admins("[key_name_admin(user)] populated the station with [spawned] AI crew.")
	log_admin("[key_name(user)] populated the station with [spawned] AI crew.")

ADMIN_VERB(sp_spawn_crew_job, R_SPAWN, "SP: Spawn Crew (Job)", "Spawn one AI-controlled crew member of a chosen job at your location.", ADMIN_CATEGORY_FUN)
	var/list/datum/job/pool = sp_get_crew_job_pool()
	var/list/titles = list()
	for(var/datum/job/job as anything in pool)
		titles[job.title] = job
	var/picked = tgui_input_list(user, "Which job?", "Spawn AI Crew", sort_list(titles))
	if(isnull(picked))
		return
	var/datum/job/job = titles[picked]
	var/mob/living/carbon/human/crew = sp_spawn_crew_member(job, spawn_point = get_turf(user.mob))
	if(isnull(crew))
		to_chat(user, span_warning("Failed to spawn an AI [job.title]."))
		return
	message_admins("[key_name_admin(user)] spawned AI crew [crew.real_name] ([job.title]) at [ADMIN_VERBOSEJMP(crew)].")
	log_admin("[key_name(user)] spawned AI crew [crew.real_name] ([job.title]) at [AREACOORD(crew)].")
