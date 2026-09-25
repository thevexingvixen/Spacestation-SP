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

ADMIN_VERB(sp_spawn_antagonist, R_SPAWN, "SP: Spawn Antagonist (Thief)", "Spawn an AI crew member with a hidden scheme to steal something, at your location.", ADMIN_CATEGORY_FUN)
	var/list/datum/job/pool = sp_get_crew_job_pool()
	var/list/titles = list()
	for(var/datum/job/job as anything in pool)
		titles[job.title] = job
	var/picked = tgui_input_list(user, "Which job should the antagonist hold?", "Spawn Antagonist", sort_list(titles))
	if(isnull(picked))
		return
	var/datum/job/job = titles[picked]
	var/mob/living/carbon/human/crew = sp_spawn_crew_member(job, spawn_point = get_turf(user.mob), controller_type = /datum/ai_controller/sp_crew/antagonist)
	if(isnull(crew))
		to_chat(user, span_warning("Failed to spawn an AI antagonist."))
		return
	var/datum/sp_scheme/scheme = sp_make_thief(crew.ai_controller)
	if(isnull(scheme))
		to_chat(user, span_warning("Spawned [crew.real_name], but found nothing on the map worth stealing to scheme about."))
		return
	message_admins("[key_name_admin(user)] spawned AI antagonist [crew.real_name] ([job.title]) at [ADMIN_VERBOSEJMP(crew)], scheme: [scheme.name].")
	log_admin("[key_name(user)] spawned AI antagonist [crew.real_name] ([job.title]); scheme: [scheme.name].")

ADMIN_VERB(sp_behaviour_tally, R_DEBUG, "SP: Behaviour Tally", "Show what the AI crew have actually managed to do so far this round.", ADMIN_CATEGORY_DEBUG)
	var/list/tally = SSspacestation_sp.event_tally
	if(!length(tally))
		to_chat(user, span_notice("The AI crew have not done anything worth counting yet."))
		return
	var/list/lines = list("<b>Spacestation SP — what the crew have done this round</b>")
	for(var/event in sort_list(tally))
		lines += "[event]: [tally[event]]"
	to_chat(user, boxed_message(jointext(lines, "<br>")))

ADMIN_VERB(sp_stand_in, R_DEBUG, "SP: Stand-in Player", "Send a scripted stand-in player to talk to the crew, and log what they hear, see and click.", ADMIN_CATEGORY_DEBUG)
	SSspacestation_sp.debug_stand_in()
	to_chat(user, span_notice("A stand-in player has set off. Their visit is logged as 'SP: stand-in:' in the game log."))
