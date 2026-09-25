/**
 * The stand-in player: a debug tool that pays the crew a short, scripted visit the way a player would, so the
 * player's side of conversation can be checked without anybody at the keyboard.
 *
 * It is a person with no AI controller, which is what "a player" means to the dialogue engine, and a trait for
 * the one place that asks for a connected client (greeting newcomers). It hears what is said around it and
 * logs it as a player's-eye transcript. It reads reply links exactly as a client would be sent them, and
 * clicks them the way /client/Topic() ends up doing: the link's own parameters, the conversation found from
 * them with locate(), and its Topic() called with usr set to the player. What it cannot check is the chat
 * window drawing a link and BYOND turning a click into that call, which is how TG's own PDA replies work.
 *
 * It wears an ID, and crew who stand beside it can read the name off it, so the visits keep their distance
 * until the one that is about exactly that. Every step is logged as "SP: stand-in:", and every check as a PASS
 * or a FAIL, tallied as standin.pass and standin.fail. Config key SP_DEBUG_STAND_IN sends one out two
 * minutes in, and the "SP: Stand-in Player" verb sends one whenever it is wanted.
 */
/datum/sp_stand_in
	/// The body doing the visiting.
	var/mob/living/carbon/human/body
	var/passed = 0
	var/failed = 0
	/// Who we last heard say something, and when.
	var/list/heard_at = list()
	/// Our ID, kept so it can be taken off for the test of silence and put back on to be read.
	var/obj/item/card/id/advanced/card

/datum/sp_stand_in/Destroy(force)
	heard_at = null
	card = null
	if(!QDELETED(body))
		UnregisterSignal(body, COMSIG_MOVABLE_PRE_HEAR)
		qdel(body)
	body = null
	return ..()

/datum/sp_stand_in/proc/note(text)
	log_sp("stand-in: [text]")

/// Records a check. Returns the result, so a failed step can be skipped past.
/datum/sp_stand_in/proc/check(result, what)
	if(result)
		passed++
		sp_record("standin.pass")
		note("PASS [what]")
	else
		failed++
		sp_record("standin.fail")
		note("FAIL [what]")
	return result

/// Everything a player standing here would hear, their own lines included.
/datum/sp_stand_in/proc/on_hear(datum/source, list/hearing_args)
	SIGNAL_HANDLER
	var/atom/movable/speaker = hearing_args[HEARING_SPEAKER]
	var/message = hearing_args[HEARING_RAW_MESSAGE]
	if(QDELETED(speaker) || !istext(message))
		return
	heard_at[speaker] = world.time
	note("hears [speaker == body ? "(you)" : speaker.name]: [message]")

/**
 * Somebody to visit who is not in the middle of anything. Somewhere public first, where a player would bump
 * into them; anywhere on the station if nobody is out -- two minutes in, most of the crew are at their posts.
 */
/proc/sp_stand_in_host(list/exclude)
	var/mob/living/carbon/human/anywhere
	for(var/mob/living/carbon/human/crew as anything in shuffle(SSspacestation_sp.ai_crew))
		if(QDELETED(crew) || crew.stat != STABLE || (crew in exclude) || !is_station_level(crew.z))
			continue
		var/datum/ai_controller/sp_crew/crew_ai = crew.ai_controller
		if(!istype(crew_ai) || istype(crew_ai, /datum/ai_controller/sp_crew/security))
			continue
		if(crew_ai.busy_with_work() || crew_ai.blackboard_key_exists(BB_SP_THREAD) || crew_ai.blackboard_key_exists(BB_SP_IN_THREAD))
			continue
		if(sp_clown_prank_spot(crew))
			return crew
		if(isnull(anywhere))
			anywhere = crew
	return anywhere

/// A clear tile exactly `distance` from somebody, in their sight.
/proc/sp_stand_in_spot(mob/living/host, distance)
	for(var/turf/open/candidate in range(distance, host))
		if(get_dist(candidate, host) != distance || candidate.is_blocked_turf(exclude_mobs = FALSE))
			continue
		if(!can_see(host, candidate, distance))
			continue
		return candidate
	return null

/// The links in an offer, as list(parameters, label) pairs, the way a chat window lays them out.
/proc/sp_stand_in_links(html)
	var/list/links = list()
	var/list/pieces = splittext(html, "<a href='byond://?")
	for(var/i in 2 to length(pieces))
		var/piece = pieces[i]
		var/params_end = findtext(piece, "'>")
		var/label_end = findtext(piece, "</a>")
		if(!params_end || !label_end)
			continue
		var/label = copytext(piece, params_end + 2, label_end)
		label = replacetext(replacetext(label, "&#91;", ""), "&#93;", "")
		links += list(list(copytext(piece, 1, params_end), label))
	return links

/// Turns up beside somebody, `distance` tiles off. The first arrival brings the body into being.
/datum/sp_stand_in/proc/arrive(mob/living/carbon/human/host, distance)
	var/turf/spot = sp_stand_in_spot(host, distance)
	if(isnull(spot))
		return FALSE
	if(QDELETED(body))
		body = new /mob/living/carbon/human(spot)
		body.real_name = "Jo Standin"
		body.name = body.real_name
		body.mind_initialize()
		ADD_TRAIT(body, TRAIT_SP_STAND_IN, SP_TRAIT_SOURCE)
		body.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(body), ITEM_SLOT_ICLOTHING)
		card = new(body)
		card.registered_name = body.real_name
		card.assignment = "Assistant"
		body.equip_to_slot_if_possible(card, ITEM_SLOT_ID)
		RegisterSignal(body, COMSIG_MOVABLE_PRE_HEAR, PROC_REF(on_hear))
	else
		body.forceMove(spot)
	body.face_atom(host)
	note("walks up to [host.real_name] ([host.mind?.assigned_role?.title || "crew"]) in [get_area_name(host)], [distance] tiles off")
	return TRUE

/// The conversation this stand-in is having with `host`, if there is one.
/datum/sp_stand_in/proc/thread_with(mob/living/host)
	for(var/datum/sp_dialogue_thread/thread as anything in GLOB.sp_active_threads)
		var/has_us = FALSE
		var/has_host = FALSE
		for(var/role in thread.cast)
			if(thread.cast[role] == body)
				has_us = TRUE
			if(thread.cast[role] == host)
				has_host = TRUE
		if(has_us && has_host)
			return thread
	return null

/// Waits up to `timeout` for `host` to offer us a reply. Returns the conversation, or null.
/datum/sp_stand_in/proc/wait_for_offer(mob/living/host, timeout)
	var/deadline = world.time + timeout
	while(world.time < deadline && !QDELETED(body))
		var/datum/sp_dialogue_thread/thread = thread_with(host)
		if(length(thread?.pending_options))
			return thread
		sleep(0.5 SECONDS)
	return null

/// Waits up to `timeout` for a conversation to be over. Returns TRUE if it is.
/datum/sp_stand_in/proc/wait_for_end(datum/sp_dialogue_thread/thread, timeout)
	var/deadline = world.time + timeout
	while(world.time < deadline && (thread in GLOB.sp_active_threads))
		sleep(0.5 SECONDS)
	return !(thread in GLOB.sp_active_threads)

/// Reads the replies on offer and clicks the one starting with `wanted`, the way a player's click arrives.
/datum/sp_stand_in/proc/click(datum/sp_dialogue_thread/thread, wanted)
	var/list/links = sp_stand_in_links(sp_dialogue_offer_html(thread, body))
	var/list/labels = list()
	for(var/list/link in links)
		labels += "([link[2]])"
	note("sees replies: [jointext(labels, " ")]")
	for(var/list/link in links)
		if(findtext(link[2], wanted) != 1)
			continue
		var/list/params = params2list(link[1])
		var/datum/target = locate(params["src"])
		if(!check(target == thread, "the reply link leads back to the conversation it belongs to"))
			return FALSE
		note("clicks ([link[2]])")
		// Where /client/Topic() ends up: the target's own Topic(), with usr the player whose client clicked.
		usr = body
		target.Topic(link[1], params)
		return TRUE
	check(FALSE, "a reply starting '[wanted]' was on offer")
	return FALSE

/// Somebody to visit, waiting up to `timeout` for somebody to come free.
/datum/sp_stand_in/proc/find_host(list/exclude, timeout = 60 SECONDS)
	var/deadline = world.time + timeout
	while(world.time < deadline)
		var/mob/living/carbon/human/host = sp_stand_in_host(exclude)
		if(!isnull(host))
			return host
		sleep(5 SECONDS)
	return null

/// The visit itself: introduced, talked to on purpose, thanked, ignored, read up close, and asked for news.
/datum/sp_stand_in/proc/visit()
	note("setting off")
	// A stranger turning up is introduced, by the crew member's own doing or on being greeted. Somebody who
	// turns out to be busy with work says so, and we try somebody else: that is the crew being right.
	var/mob/living/carbon/human/first
	var/datum/sp_dialogue_thread/thread
	var/list/tried = list()
	for(var/attempt in 1 to 4)
		first = find_host(tried)
		if(isnull(first))
			break
		tried += first
		if(!arrive(first, 2))
			note("no room to stand beside [sp_first_name(first)]; trying somebody else")
			first = null
			continue
		thread = wait_for_offer(first, 12 SECONDS)
		if(!isnull(thread))
			break
		var/hello_at = world.time
		note("[sp_first_name(first)] did not come over; walking up to say hello")
		arrive(first, 2) // they may have wandered off while we waited, as people do
		body.say("Hello, [sp_first_name(first)].")
		thread = wait_for_offer(first, 15 SECONDS)
		if(!isnull(thread))
			break
		var/datum/ai_controller/sp_crew/busy_ai = first.ai_controller
		if(busy_ai?.busy_with_work())
			check(heard_at[first] > hello_at, "[sp_first_name(first)], busy with work, says so rather than ignoring us")
		note("trying somebody else")
	if(isnull(first))
		note("nobody idle anywhere public to visit")
		return finish()
	var/first_name = sp_first_name(first)
	var/datum/ai_controller/sp_crew/first_ai = first.ai_controller
	if(!check(thread?.dialogue?.id == "introductions", "a stranger is introduced to"))
		return finish()
	click(thread, "I'm")
	wait_for_end(thread, 20 SECONDS)
	check(sp_knows_name(first_ai, body), "[first_name] learns our name from being told it")

	// Talk to, on purpose, from the menu.
	sleep(4 SECONDS)
	var/list/menu = sp_talk_offer(first, body)
	note("Talk to [first_name] offers: [length(menu) ? jointext(menu, ", ") : "nothing"]")
	check(!("Introduce yourself" in menu), "nobody is offered an introduction twice")
	if(check(("Ask what they do" in menu), "asking what somebody does is on the menu"))
		sp_talk_start(first, body, "Ask what they do")
		thread = wait_for_offer(first, 20 SECONDS)
		if(check(!isnull(thread), "[first_name] answers and it is our turn"))
			click(thread, "Need a hand")
			wait_for_end(thread, 20 SECONDS)
			check(sp_remembers(first_ai, body, "offered_help"), "[first_name] remembers being offered a hand")

	// Thanks, and then how they regard us.
	sleep(4 SECONDS)
	body.say("Thanks, [first_name].")
	sleep(6 SECONDS)
	var/list/seen = list()
	SEND_SIGNAL(first, COMSIG_ATOM_EXAMINE, body, seen)
	note("examines [first_name]: [length(seen) ? jointext(seen, " ") : "nothing about how they regard us"] (standing [sp_reputation(first_ai, body)])")
	check(findtext(jointext(seen, " "), "like you"), "somebody who likes us shows it on examine")

	// Somebody else: this time we say nothing, and silence is an answer.
	var/mob/living/carbon/human/second = find_host(list(first))
	if(isnull(second) || !arrive(second, 2))
		note("nobody else idle to visit")
		return finish()
	var/second_name = sp_first_name(second)
	var/datum/ai_controller/sp_crew/second_ai = second.ai_controller
	// Out of sight for this part: whoever we talk to can wander within reading distance, and the test is of
	// silence, not of whether they happened to walk past our chest.
	if(!QDELETED(card) && body.wear_id == card)
		body.temporarilyRemoveItemFromInventory(card, force = TRUE)
		card.forceMove(body)
		note("puts the ID away")
	thread = wait_for_offer(second, 8 SECONDS)
	if(isnull(thread))
		arrive(second, 2)
		body.say("Hello, [second_name].")
		thread = wait_for_offer(second, 15 SECONDS)
	if(check(!isnull(thread), "[second_name] starts a conversation with us"))
		note("says nothing, and waits")
		wait_for_end(thread, 45 SECONDS)
		check(!sp_knows_name(second_ai, body), "keeping quiet keeps our name to ourselves")

	// Up close, the ID on our chest gives the name away.
	sleep(4 SECONDS)
	if(!QDELETED(card))
		body.equip_to_slot_if_possible(card, ITEM_SLOT_ID)
		note("clips the ID back on")
	arrive(second, 1)
	body.say("[second_name], how are you?")
	sleep(6 SECONDS)
	check(sp_knows_name(second_ai, body), "[second_name] reads our name off the ID from beside us")

	// And what the station has been talking about.
	sleep(4 SECONDS)
	menu = sp_talk_offer(second, body)
	if(check(("Ask if they've heard anything" in menu), "asking after the news is on the menu"))
		sp_talk_start(second, body, "Ask if they've heard anything")
		thread = wait_for_offer(second, 20 SECONDS)
		if(thread)
			click(thread, "Thanks")
		check(isnull(thread) || wait_for_end(thread, 25 SECONDS), "the news runs to its end")
	finish()

/datum/sp_stand_in/proc/finish()
	note("done: [passed] passed, [failed] failed")
	qdel(src)

/// Sends a stand-in player out to visit the crew.
/datum/controller/subsystem/spacestation_sp/proc/debug_stand_in()
	var/datum/sp_stand_in/stand_in = new
	INVOKE_ASYNC(stand_in, TYPE_PROC_REF(/datum/sp_stand_in, visit))
	return stand_in
