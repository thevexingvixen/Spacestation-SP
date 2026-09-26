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
 * Somebody to visit who is not in the middle of anything. Somebody whose job has something to fetch first, so the
 * favours can all be asked for; somewhere public before anywhere else, where a player would bump into them -- two
 * minutes in, most of the crew are at their posts.
 */
/proc/sp_stand_in_host(list/exclude)
	var/mob/living/carbon/human/best
	var/best_score = -1
	for(var/mob/living/carbon/human/crew as anything in shuffle(SSspacestation_sp.ai_crew))
		if(QDELETED(crew) || crew.stat != STABLE || (crew in exclude) || !is_station_level(crew.z))
			continue
		var/datum/ai_controller/sp_crew/crew_ai = crew.ai_controller
		if(!istype(crew_ai) || istype(crew_ai, /datum/ai_controller/sp_crew/security) || !crew.can_speak())
			continue
		if(crew_ai.busy_with_work() || crew_ai.blackboard_key_exists(BB_SP_THREAD) || crew_ai.blackboard_key_exists(BB_SP_IN_THREAD) || crew_ai.blackboard_key_exists(BB_SP_FAVOUR))
			continue
		// Somebody with something to fetch, and not in medbay -- a medic cannot be asked to call a medic -- so every
		// favour can be asked of the one person.
		var/score = (length(crew_ai.fetchables()) || length(crew_ai.spares()) ? 2 : 0) + (sp_clown_prank_spot(crew) ? 1 : 0)
		if(score >= 2 && !istype(crew_ai, /datum/ai_controller/sp_crew/medical))
			score += 2
		if(score > best_score)
			best = crew
			best_score = score
	return best

/**
 * A clear tile of station floor exactly `distance` from somebody, in their sight. Floor, and not out in space: in
 * sight includes the far side of a window, and the second round of favours sent the stand-in out into the vacuum
 * beside a hallway, where nobody heard it say hello and it came back hurt.
 */
/proc/sp_stand_in_spot(mob/living/host, distance)
	for(var/turf/open/floor/candidate in range(distance, host))
		if(get_dist(candidate, host) != distance || candidate.is_blocked_turf(exclude_mobs = FALSE))
			continue
		var/area/place = get_area(candidate)
		if(istype(place, /area/space) || !is_station_level(candidate.z))
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

/**
 * Draws `host` into small talk with a free colleague nearby, the way the fifth visit lost them, so the next step
 * can check a player still comes first. Returns the chat, or null if nobody is about to have one with.
 */
/datum/sp_stand_in/proc/start_small_talk(mob/living/carbon/human/host)
	for(var/mob/living/carbon/human/colleague in oview(SP_DIALOGUE_RANGE, host))
		var/datum/ai_controller/sp_crew/their_ai = colleague.ai_controller
		if(!istype(their_ai) || their_ai.busy_with_work() || their_ai.blackboard_key_exists(BB_SP_THREAD) || their_ai.blackboard_key_exists(BB_SP_IN_THREAD))
			continue
		var/datum/sp_dialogue_thread/chat = sp_start_thread(their_ai, sp_pick_dialogue(colleague, host), colleague, host)
		if(!isnull(chat))
			return chat
	return null

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

	// Talk to, on purpose, from the menu -- with a colleague chatting to them, if one is about: a player outranks
	// small talk. The fifth visit lost this step to exactly that.
	sleep(4 SECONDS)
	var/datum/sp_dialogue_thread/chat = start_small_talk(first)
	if(!isnull(chat))
		note("[first_name] is drawn into [chat.dialogue.id] with a colleague")
		sleep(1 SECONDS)
	var/list/menu = sp_talk_offer(first, body)
	note("Talk to [first_name] offers: [length(menu) ? jointext(menu, ", ") : "nothing"]")
	check(!("Introduce yourself" in menu), "nobody is offered an introduction twice")
	if(check(("Ask what they do" in menu), "asking what somebody does is on the menu"))
		var/chatting = !isnull(chat) && (chat in GLOB.sp_active_threads)
		sp_talk_start(first, body, "Ask what they do")
		if(chatting)
			check(!(chat in GLOB.sp_active_threads), "[first_name] breaks off the small talk for us")
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

	// Standing spent: somebody who likes us does things for us.
	ask_favours(first)

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

	// And what the station has been talking about -- walking back up to them first if they have gone back to work.
	sleep(4 SECONDS)
	if(check(ask_when_offered(second, "Ask if they've heard anything"), "asking after the news is on the menu"))
		thread = wait_for_offer(second, 20 SECONDS)
		if(thread)
			click(thread, "Thanks")
		check(isnull(thread) || wait_for_end(thread, 25 SECONDS), "the news runs to its end")
	finish()

/// Waits up to `timeout` for `host_ai` to take a favour on. Returns which one, or null.
/datum/sp_stand_in/proc/wait_for_favour(datum/ai_controller/sp_crew/host_ai, timeout)
	var/deadline = world.time + timeout
	while(world.time < deadline && !QDELETED(body))
		var/kind = host_ai.blackboard[BB_SP_FAVOUR]
		if(kind)
			return kind
		sleep(0.5 SECONDS)
	return null

/// Waits up to `timeout` for `condition` to come true, checking twice a second. Returns whether it did.
/datum/sp_stand_in/proc/wait_until(datum/callback/condition, timeout)
	var/deadline = world.time + timeout
	while(world.time < deadline && !QDELETED(body))
		if(condition.Invoke())
			return TRUE
		sleep(0.5 SECONDS)
	return condition.Invoke()

/**
 * A shut door near `host` that they could open for us and we cannot, with a clear tile beside it on their side to
 * ask from. Their side is the one they can see: the first round of favours stood the stand-in on the far side of a
 * maintenance door, where the crew member who had followed it through could not hear it say "that's all".
 */
/datum/sp_stand_in/proc/door_near(mob/living/carbon/human/host)
	for(var/obj/machinery/door/airlock/door in range(10, host))
		if(!door.density || door.locked || door.welded || !door.hasPower() || !door.allowed(host) || door.allowed(body) || sp_door_off_limits(door))
			continue
		var/turf/open/floor/best
		for(var/direction in GLOB.cardinals)
			var/turf/open/floor/spot = get_step(door, direction)
			if(!istype(spot) || spot.is_blocked_turf(exclude_mobs = FALSE) || !can_see(host, spot, 10))
				continue
			var/area/place = get_area(spot)
			if(istype(place, /area/space))
				continue
			if(isnull(best) || get_dist(host, spot) < get_dist(host, best))
				best = spot
		if(best)
			return list(door, best)
	return null

/// Whether `host` is beside us and can see us: close enough to hear what we say to them, and nothing in between.
/datum/sp_stand_in/proc/beside(mob/living/host)
	return !QDELETED(host) && get_dist(host, body) <= 1 && can_see(host, body, 2)

/// Whether somebody is standing beside us who works in medbay and could see to us.
/datum/sp_stand_in/proc/medic_beside()
	for(var/mob/living/carbon/human/medic in range(2, body))
		if(istype(medic.ai_controller, /datum/ai_controller/sp_crew/medical))
			return medic
	return null

/// Whether something has reached us: in our hands, or at our feet.
/datum/sp_stand_in/proc/got(obj/item/thing)
	return !QDELETED(thing) && (get(thing, /mob) == body || thing.loc == get_turf(body))

/**
 * Standing spent, with somebody who likes us: come along to a door and open it, fetch us something, and call medbay
 * when we are hurt. Each favour is asked for from Talk to, the way a player would, and checked in the world.
 */
/datum/sp_stand_in/proc/ask_favours(mob/living/carbon/human/host)
	var/host_name = sp_first_name(host)
	var/datum/ai_controller/sp_crew/host_ai = host.ai_controller
	var/list/at_door = door_near(host)
	sleep(4 SECONDS)
	var/list/menu = sp_talk_offer(host, body)
	note("Talk to [host_name] offers: [length(menu) ? jointext(menu, ", ") : "nothing"] (standing [sp_reputation(host_ai, body)])")
	if(check(("Ask them to come with you" in menu), "somebody who likes us can be asked to come along"))
		sp_talk_start(host, body, "Ask them to come with you")
		if(check(wait_for_favour(host_ai, 15 SECONDS) == SP_FAVOUR_FOLLOW, "[host_name] agrees to come with us"))
			var/turf/destination = at_door ? at_door[2] : sp_stand_in_spot(host, 6)
			if(destination)
				body.forceMove(destination)
				note("walks off to [get_area_name(destination)], [get_dist(host, body)] tiles from [host_name]")
				check(wait_until(CALLBACK(src, PROC_REF(beside), host), 30 SECONDS), "[host_name] keeps up")
			body.say("That's all, [host_name]. Thanks.")
			check(wait_until(CALLBACK(src, PROC_REF(favour_over), host_ai), 5 SECONDS), "[host_name] is let off with a thanks")

	if(isnull(at_door))
		note("no door near [host_name] for them to open")
	else
		var/obj/machinery/door/airlock/door = at_door[1]
		sleep(4 SECONDS)
		menu = sp_talk_offer(host, body)
		if(check(("Ask them to open a door" in menu), "[host_name] can be asked to open [door] in [get_area_name(door)]"))
			sp_talk_start(host, body, "Ask them to open a door")
			if(check(wait_for_favour(host_ai, 15 SECONDS) == SP_FAVOUR_DOOR, "[host_name] agrees to open it"))
				if(check(wait_until(CALLBACK(src, PROC_REF(door_open), door), 30 SECONDS), "[host_name] opens [door] with their own card"))
					var/turf/far_side = get_step(door, get_dir(at_door[2], door))
					body.forceMove(get_turf(door))
					sleep(2 SECONDS)
					if(isopenturf(far_side))
						body.forceMove(far_side)
					note("walks through [door]")
					check(wait_until(CALLBACK(src, PROC_REF(favour_over), host_ai), 5 SECONDS), "[host_name] lets go of the door once we are through")
				body.forceMove(at_door[2])

	sleep(4 SECONDS)
	if(!ask_when_offered(host, "Ask them to fetch something"))
		note("[host_name] ([host.mind?.assigned_role?.title]) has nothing to fetch us, or is busy with work")
	else
		if(check(wait_for_favour(host_ai, 15 SECONDS) == SP_FAVOUR_FETCH, "[host_name] agrees to fetch us something"))
			var/obj/item/thing = host_ai.blackboard[BB_SP_FAVOUR_TARGET]
			note("[host_name] goes for [thing] in [get_area_name(thing)]")
			check(wait_until(CALLBACK(src, PROC_REF(got), thing), SP_FAVOUR_FETCH_TIME), "[host_name] brings us [thing]")
			body.say("Thanks, [host_name].")

	sleep(4 SECONDS)
	// Hard enough to look hurt (sp_dialogue_hurt(), below seven tenths of health). TG weighs a limb's damage at less
	// than the whole body's, so 35 brute spread over arms and legs came to 71 health, and the answer was "You look
	// fine to me."
	body.adjust_brute_loss(50)
	note("takes a knock ([round(body.get_brute_loss())] brute, health [body.health] of [body.maxHealth])")
	var/asked_at = world.time
	if(!ask_when_offered(host, "Ask them to call a doctor"))
		note("[host_name] cannot call a doctor just now: busy, no headset, or no medic to call")
	else
		if(check(wait_until(CALLBACK(src, PROC_REF(called_since), host_ai, asked_at), 20 SECONDS), "[host_name] calls medbay for us"))
			check(wait_until(CALLBACK(src, PROC_REF(medic_beside)), 150 SECONDS), "a medic comes to see us")
			body.say("Thanks, doc.")
			sleep(10 SECONDS)

/**
 * Walks back up to `host` if they have gone back to work in the meantime, the way a player would, waits up to
 * twenty seconds for `title` to be on their Talk to menu -- somebody mid-job is busy until the job is done -- and
 * asks. Returns whether it was asked. A crew member goes back to work once a favour is over, and the fourth round
 * asked a cook for something from four tiles away, which Talk to does not reach.
 */
/datum/sp_stand_in/proc/ask_when_offered(mob/living/carbon/human/host, title)
	if(get_dist(host, body) > 1)
		arrive(host, 1)
	if(!wait_until(CALLBACK(src, PROC_REF(offered), host, title), 20 SECONDS))
		return FALSE
	if(get_dist(host, body) > 2)
		arrive(host, 1)
	return !isnull(sp_talk_start(host, body, title))

/datum/sp_stand_in/proc/offered(mob/living/carbon/human/host, title)
	return (title in sp_talk_offer(host, body))

/datum/sp_stand_in/proc/favour_over(datum/ai_controller/sp_crew/host_ai)
	return !host_ai.blackboard_key_exists(BB_SP_FAVOUR)

/datum/sp_stand_in/proc/door_open(obj/machinery/door/door)
	return !QDELETED(door) && !door.density

/datum/sp_stand_in/proc/called_since(datum/ai_controller/sp_crew/host_ai, since)
	var/list/radio_call = host_ai.blackboard[BB_SP_LAST_CALL]
	return length(radio_call) && radio_call[SP_CALL_TIME] >= since

/datum/sp_stand_in/proc/finish()
	note("done: [passed] passed, [failed] failed")
	qdel(src)

/// Sends a stand-in player out to visit the crew.
/datum/controller/subsystem/spacestation_sp/proc/debug_stand_in()
	var/datum/sp_stand_in/stand_in = new
	INVOKE_ASYNC(stand_in, TYPE_PROC_REF(/datum/sp_stand_in, visit))
	return stand_in
