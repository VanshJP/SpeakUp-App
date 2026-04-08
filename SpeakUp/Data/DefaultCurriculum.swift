import Foundation

// To add new content:
//   1. Add a CurriculumLesson to an existing phase, or add a new CurriculumPhase
//   2. Use factory methods: .lesson(), .practice(), .drill(), .exercise(), .review()
//   3. Build lesson content with: .concepts(), .tip(), .example(), .keyTakeaway(), .callout()
//   4. Activity IDs must be unique — use the pattern w{week}_l{lesson}_a{activity}
//   5. For practice auto-completion, mention the duration in the description (e.g. "60-second")

struct DefaultCurriculum {
    static let phases: [CurriculumPhase] = [

        // ╔══════════════════════════════════════════════════════════════╗
        // ║  WEEK 1 — AWARENESS                                        ║
        // ╚══════════════════════════════════════════════════════════════╝

        CurriculumPhase(
            id: "week1", week: 1,
            title: "Awareness",
            description: "Discover your speaking patterns and set your baseline.",
            lessons: [

                // ── W1 L1: Your Baseline Recording ──────────────────
                CurriculumLesson(
                    id: "w1_l1",
                    title: "Your Baseline Recording",
                    objective: "Record your first session to establish a starting point.",
                    activities: [
                        .lesson(
                            id: "w1_l1_a1",
                            title: "Why baselines matter",
                            description: "Your first recording becomes your comparison point. Don't try to be perfect — just be natural.",
                            content: LessonContent(sections: [
                                .concepts(title: "Why Record a Baseline?", body: "A baseline captures where you are right now — your natural pace, filler habits, and comfort level.\nWithout a starting point, you can't measure growth. Every great speaker started somewhere.\nThis isn't a test. There's no passing or failing. It's just a snapshot of today.", icon: "chart.line.uptrend.xyaxis"),
                                .tip("Speak as if you're explaining something to a friend. Don't rehearse or try to sound polished — your natural speaking voice is exactly what we want to capture."),
                                .example(title: "What to Expect", body: "Most people score between 40-60 on their first recording. That's completely normal. After completing this learning path, the average improvement is 20-30 points."),
                                .keyTakeaway("Your baseline isn't your limit — it's your launch pad. The only bad recording is the one you never make."),
                            ])
                        ),
                        .practice(id: "w1_l1_a2", title: "Record a 60-second session", description: "Pick any topic and speak for 60 seconds. Talk about your day, your favorite hobby, or anything on your mind.", duration: 60),
                    ]
                ),

                // ── W1 L2: Know Your Fillers ─────────────────────────
                CurriculumLesson(
                    id: "w1_l2",
                    title: "Know Your Fillers",
                    objective: "Identify your most common filler words.",
                    activities: [
                        .lesson(
                            id: "w1_l2_a1",
                            title: "What are filler words?",
                            description: "Words like 'um', 'uh', 'like', and 'you know' are natural speech patterns. Awareness is the first step.",
                            content: LessonContent(sections: [
                                .concepts(title: "Understanding Fillers", body: "Filler words are sounds or phrases we insert when thinking: \"um,\" \"uh,\" \"like,\" \"you know,\" \"so,\" \"basically,\" \"right?\"\nEveryone uses them — even professional speakers. The goal isn't zero fillers, it's awareness and control.\nFillers become a problem when they distract listeners or undermine your confidence. A few are natural; a dozen per minute is worth addressing.", icon: "text.bubble"),
                                .example(title: "Before & After", body: "Before: \"So, um, I think that, like, the best approach would be, you know, to basically just focus on, um, the main points.\"\n\nAfter: \"I think the best approach is to focus on the main points.\"\n\nSame idea — half the words, twice the impact."),
                                .tip("Replace fillers with silence. A brief pause feels awkward to you but sounds confident to your audience. The space gives listeners time to absorb what you just said."),
                                .keyTakeaway("You can't fix what you can't see. This recording will reveal your filler patterns — that awareness alone starts reducing them."),
                            ])
                        ),
                        .practice(id: "w1_l2_a2", title: "Record and review fillers", description: "Record a session and pay attention to which filler words appear in your analysis. Which ones do you use most?", duration: 60),
                    ]
                ),

                // ── W1 L3: Understanding Pace ────────────────────────
                CurriculumLesson(
                    id: "w1_l3",
                    title: "Understanding Pace",
                    objective: "Learn about speaking pace and where yours falls.",
                    activities: [
                        .lesson(
                            id: "w1_l3_a1",
                            title: "The ideal pace range",
                            description: "130-170 words per minute is considered the optimal range for clear communication.",
                            content: LessonContent(sections: [
                                .concepts(title: "Speaking Pace Explained", body: "The sweet spot for conversational speaking is 130-170 words per minute (WPM).\nBelow 130 WPM can feel slow and cause listeners to lose focus. Above 170 WPM makes it hard for people to follow your ideas.\nPace naturally varies — you might speed up when excited and slow down for emphasis. That variation is actually good.", icon: "speedometer"),
                                .example(title: "Famous Speakers' Pace", body: "Martin Luther King Jr.'s \"I Have a Dream\" averaged ~100 WPM — deliberately slow for dramatic impact.\nJohn F. Kennedy's inaugural address was ~135 WPM — measured and presidential.\nCasual TED talks typically range 150-170 WPM — energetic but clear."),
                                .tip("If you tend to rush, try breathing between sentences. Each breath creates a natural pause that slows you down without feeling forced."),
                                .keyTakeaway("Pace isn't about hitting an exact number — it's about being clear and comfortable. Know your range, then adjust with intention."),
                            ])
                        ),
                        .practice(id: "w1_l3_a2", title: "Record focusing on pace", description: "Record a session and pay attention to your WPM in the analysis. Are you in the 130-170 range?", duration: 60),
                    ]
                ),

                // ── W1 L4: Reading Your Score ────────────────────────
                CurriculumLesson(
                    id: "w1_l4",
                    title: "Reading Your Score",
                    objective: "Understand what each score component means.",
                    activities: [
                        .lesson(
                            id: "w1_l4_a1",
                            title: "Score breakdown",
                            description: "Your overall score combines clarity, pace, filler usage, and pause quality. Each tells you something different.",
                            content: LessonContent(sections: [
                                .concepts(title: "Your Score Components", body: "Clarity — How well-formed and complete your sentences are. Trails off and restarts lower this score.\nPace — How close to the optimal 130-170 WPM range you speak. Consistency matters too.\nFiller Usage — Fewer filler words means a higher score. This tracks \"um,\" \"uh,\" \"like,\" and similar words.\nPause Quality — Strategic pauses (between ideas) help your score. Hesitation pauses (mid-sentence) lower it.", icon: "chart.bar.fill"),
                                .tip("Don't try to improve everything at once. Pick your lowest-scoring area and focus on that for a week. Small, targeted improvements compound into big results."),
                                .keyTakeaway("Your overall score is the average of multiple skills. Improving any single component lifts the whole score."),
                            ])
                        ),
                        .review(id: "w1_l4_a2", title: "Review your sessions", description: "Look at your recordings so far and identify your strongest and weakest areas."),
                    ]
                ),
            ]
        ),

        // ╔══════════════════════════════════════════════════════════════╗
        // ║  WEEK 2 — FUNDAMENTALS                                      ║
        // ╚══════════════════════════════════════════════════════════════╝

        CurriculumPhase(
            id: "week2", week: 2,
            title: "Fundamentals",
            description: "Build core skills with targeted exercises.",
            lessons: [

                // ── W2 L1: Breathing for Speaking ────────────────────
                CurriculumLesson(
                    id: "w2_l1",
                    title: "Breathing for Speaking",
                    objective: "Learn breathing techniques that support clear speech.",
                    activities: [
                        .lesson(
                            id: "w2_l1_a0",
                            title: "The breath-speech connection",
                            description: "Your breath is the engine of your voice. How you breathe determines how you sound.",
                            content: LessonContent(sections: [
                                .concepts(title: "Why Breathing Matters for Speech", body: "Your voice is powered by air. Shallow chest breathing gives you a thin, strained sound and forces you to gasp mid-sentence.\nDiaphragmatic breathing — breathing from your belly — gives you a deeper, steadier voice and enough air to finish your thoughts.\nWhen you're nervous, your breathing shifts to short, shallow breaths. This is your body's fight-or-flight response. Controlled breathing overrides that signal and tells your nervous system you're safe.\nThe result: a calmer mind, a steadier voice, and more control over your pace.", icon: "lungs.fill"),
                                .example(title: "Chest vs. Belly Breathing", body: "Chest breathing: Shoulders rise, breath is short, voice sounds tight. You run out of air mid-sentence and have to gasp.\n\nBelly breathing: Stomach expands, breath is deep, voice sounds full. You have enough air to finish complete thoughts with power."),
                                .tip("Place one hand on your chest and one on your belly. Breathe in. If your chest hand moves first, you're chest-breathing. Practice until your belly hand moves first — that's diaphragmatic breathing.", title: "Quick Test"),
                                .keyTakeaway("Breath is the foundation. Master your breathing, and your voice, pace, and confidence all improve as a side effect."),
                            ])
                        ),
                        .exercise(id: "w2_l1_a1", title: "Box breathing exercise", description: "Complete the box breathing warm-up to calm your nerves and steady your voice.", exerciseId: "box_breathing"),
                        .practice(id: "w2_l1_a2", title: "Record after breathing", description: "Record a 60-second session immediately after the breathing exercise. Notice how your voice feels steadier and your pace is more controlled.", duration: 60),
                    ]
                ),

                // ── W2 L2: Filler Elimination ────────────────────────
                CurriculumLesson(
                    id: "w2_l2",
                    title: "Filler Elimination",
                    objective: "Practice speaking without filler words.",
                    activities: [
                        .lesson(
                            id: "w2_l2_a0",
                            title: "Strategies for clean speech",
                            description: "Specific techniques to catch and replace filler words before they leave your mouth.",
                            content: LessonContent(sections: [
                                .concepts(title: "Three Filler-Busting Techniques", body: "The Pause Swap — Every time you feel an \"um\" coming, close your mouth and pause instead. Silence sounds intentional; fillers sound uncertain.\nThe Sentence Starter — Begin each new thought with a clear first word. \"The reason is...\" \"What I noticed was...\" \"Here's the key thing...\" Starting strong prevents the verbal stumble.\nThe Slow Down — Most fillers happen because your mouth is trying to keep up with your brain. Speak 10% slower and your words will catch up to your thoughts.", icon: "wand.and.stars"),
                                .example(title: "The Pause Swap in Action", body: "With fillers: \"So, um, I think we should, like, move the deadline because, uh, the team needs more time.\"\n\nWith pauses: \"I think we should move the deadline. [pause] The team needs more time.\"\n\nThe paused version sounds decisive. The filler version sounds uncertain. Same message, completely different impression."),
                                .tip("Pick ONE filler to focus on this week. If your biggest filler is \"like,\" just work on catching that one. Trying to eliminate all fillers at once is overwhelming. Target one, master it, then move to the next."),
                                .keyTakeaway("Every filler is a pause waiting to happen. Train yourself to pause instead of fill — the silence is your secret weapon."),
                            ])
                        ),
                        .drill(id: "w2_l2_a1", title: "Filler elimination drill", description: "A fast 15-second challenge: speak without any filler words. The drill detects them in real time.", mode: "fillerElimination"),
                        .practice(id: "w2_l2_a2", title: "30-second clean speech", description: "Now apply what you practiced. Record 30 seconds focusing entirely on avoiding fillers.", duration: 30),
                    ]
                ),

                // ── W2 L3: Pace Control ──────────────────────────────
                CurriculumLesson(
                    id: "w2_l3",
                    title: "Pace Control",
                    objective: "Practice maintaining a steady, comfortable pace.",
                    activities: [
                        .lesson(
                            id: "w2_l3_a0",
                            title: "Mastering your tempo",
                            description: "Learn how to control your speaking speed and use pace variation intentionally.",
                            content: LessonContent(sections: [
                                .concepts(title: "The Art of Pace Control", body: "Rushing is the #1 sign of nervousness. When adrenaline kicks in, your internal clock speeds up and 150 WPM feels like 100 to you.\nThe fix isn't just \"slow down\" — it's building awareness of your pace in real time. That's what the pace drill trains.\nThink of pace like a car's cruise control. You want to set a comfortable speed and only deviate on purpose — speeding up for excitement, slowing down for emphasis.", icon: "gauge.with.dots.needle.33percent"),
                                .concepts(title: "Pace Anchors", body: "Sentence breaks — Pause briefly at the end of each sentence. This naturally regulates your speed.\nKeyword emphasis — Slow down on important words. \"This is the MOST important thing\" lands harder than rushing through.\nBreath checkpoints — Take a full breath every 2-3 sentences. Your breath forces a natural pace reset.", icon: "anchor"),
                                .tip("Record yourself reading the same paragraph at 120, 150, and 170 WPM. Listen back to find your sweet spot — the speed where you sound natural and clear. That's your target pace."),
                                .keyTakeaway("Great speakers don't have one speed — they have a default pace and the skill to vary it. Build your default first, then learn to shift gears."),
                            ])
                        ),
                        .drill(id: "w2_l3_a1", title: "Pace control drill", description: "A 60-second drill where you match a target WPM. The gauge shows you in real time whether you're too fast or slow.", mode: "paceControl"),
                        .practice(id: "w2_l3_a2", title: "Controlled pace recording", description: "Record a 60-second session focusing on maintaining 130-170 WPM. Breathe between sentences to keep steady.", duration: 60),
                    ]
                ),

                // ── W2 L4: Warm-Up Routine ───────────────────────────
                CurriculumLesson(
                    id: "w2_l4",
                    title: "Warm-Up Routine",
                    objective: "Establish a pre-speaking warm-up habit.",
                    activities: [
                        .lesson(
                            id: "w2_l4_a0",
                            title: "Why warm up your voice?",
                            description: "Athletes stretch before competing. Your voice is a muscle that performs better when warmed up.",
                            content: LessonContent(sections: [
                                .concepts(title: "The Science of Vocal Warm-Ups", body: "Your vocal cords are muscles — specifically, two small folds of tissue in your larynx that vibrate to produce sound.\nCold muscles are tense and stiff. When you speak without warming up, your voice can sound tight, thin, or gravelly.\nA 2-3 minute warm-up increases blood flow to your vocal cords, relaxes surrounding muscles, and expands your pitch range.\nSingers never perform without warming up. Speakers should adopt the same habit.", icon: "waveform.circle"),
                                .concepts(title: "Your 3-Minute Pre-Speaking Routine", body: "Step 1: Breathing (30 seconds) — Three deep belly breaths to activate your diaphragm.\nStep 2: Humming (30 seconds) — Hum at a comfortable pitch, feeling the vibration in your face.\nStep 3: Tongue twisters (60 seconds) — Articulation exercises to wake up your mouth muscles.\nStep 4: Range glides (30 seconds) — Slide your voice from low to high and back to expand your range.\nStep 5: Practice sentence (30 seconds) — Say one clear sentence out loud to calibrate your volume and pace.", icon: "list.bullet"),
                                .tip("Do your warm-up in the car, shower, or any private space before a meeting or presentation. Even 60 seconds of humming makes a noticeable difference. Your first words of the day shouldn't be the ones that matter most."),
                                .keyTakeaway("A warm voice is a confident voice. Build a quick warm-up into your pre-speaking ritual and you'll start every session at your best."),
                            ])
                        ),
                        .exercise(id: "w2_l4_a1", title: "Tongue twister warm-up", description: "Loosen your articulation with the classic \"She Sells Seashells\" tongue twister exercise.", exerciseId: "she_sells"),
                        .exercise(id: "w2_l4_a2", title: "Vocal warm-up", description: "Warm up your vocal cords with the humming exercise. This relaxes tension and improves resonance.", exerciseId: "humming"),
                    ]
                ),
            ]
        ),

        // ╔══════════════════════════════════════════════════════════════╗
        // ║  WEEK 3 — STRUCTURE                                         ║
        // ╚══════════════════════════════════════════════════════════════╝

        CurriculumPhase(
            id: "week3", week: 3,
            title: "Structure",
            description: "Organize your thoughts with frameworks and deliberate pausing.",
            lessons: [

                // ── W3 L1: The PREP Framework ────────────────────────
                CurriculumLesson(
                    id: "w3_l1",
                    title: "The PREP Framework",
                    objective: "Learn to structure responses using Point-Reason-Example-Point.",
                    activities: [
                        .lesson(
                            id: "w3_l1_a1",
                            title: "PREP explained",
                            description: "PREP stands for Point, Reason, Example, Point. It's perfect for answering questions clearly.",
                            content: LessonContent(sections: [
                                .concepts(title: "The PREP Framework", body: "Point — State your main idea upfront. Lead with your conclusion so the audience knows where you're headed.\nReason — Explain why. Give the logic, evidence, or rationale behind your point.\nExample — Make it real with a specific story, statistic, or scenario that brings your reason to life.\nPoint — Restate your main idea to land it. Circle back to where you started so it sticks.", icon: "list.number"),
                                .example(title: "PREP in Action", body: "Question: \"Why is teamwork important?\"\n\nPoint: \"Teamwork is essential because it multiplies what any individual can achieve.\"\n\nReason: \"When people combine different strengths, they solve problems faster and catch mistakes that one person would miss.\"\n\nExample: \"On my last project, one teammate caught a critical bug I'd overlooked, which saved us a week of rework.\"\n\nPoint: \"That's why I believe teamwork isn't just nice to have — it's a multiplier for results.\""),
                                .concepts(title: "When to Use PREP", body: "Job interviews — \"Why should we hire you?\" \"What's your greatest strength?\" \"Why this company?\"\nMeetings — Pitching an idea, answering a question from leadership, defending a decision.\nNetworking — Explaining what you do, why you're passionate about your field.\nAnytime someone asks your opinion — PREP gives you instant structure under pressure.", icon: "checkmark.circle"),
                                .tip("Start with your conclusion, not your reasoning. Most people build up to their point — great speakers lead with it. Your audience knows where you're headed, so they can follow your reasoning more easily."),
                                .keyTakeaway("PREP gives your answer instant structure. Even under pressure, if you remember Point-Reason-Example-Point, you'll sound organized and persuasive."),
                            ])
                        ),
                        .practice(id: "w3_l1_a2", title: "Practice with PREP", description: "Record a 60-second response using the PREP framework. Pick any question and structure your answer as Point → Reason → Example → Point.", duration: 60, framework: "PREP"),
                    ]
                ),

                // ── W3 L2: The STAR Framework ────────────────────────
                CurriculumLesson(
                    id: "w3_l2",
                    title: "The STAR Framework",
                    objective: "Practice the Situation-Task-Action-Result format.",
                    activities: [
                        .lesson(
                            id: "w3_l2_a1",
                            title: "STAR explained",
                            description: "STAR is ideal for telling stories: set the Situation, describe the Task, explain your Action, share the Result.",
                            content: LessonContent(sections: [
                                .concepts(title: "The STAR Framework", body: "Situation — Set the scene briefly. Where were you? When was this? What was the context?\nTask — What was your specific role or challenge? What needed to be done, and why did it matter?\nAction — What did you actually do? Be specific about your decisions, steps, and reasoning.\nResult — What was the outcome? Quantify it if you can. What did you learn?", icon: "list.number"),
                                .example(title: "STAR in Action", body: "Question: \"Tell me about a time you solved a difficult problem.\"\n\nSituation: \"Last year, our team's main client threatened to leave because deliveries were consistently late.\"\n\nTask: \"As project lead, I needed to fix the delivery timeline without adding headcount or budget.\"\n\nAction: \"I mapped our entire workflow, found two bottleneck steps, and reorganized the team to work on them in parallel instead of sequentially.\"\n\nResult: \"We cut delivery time by 40%, the client renewed their contract, and the team adopted the new process permanently.\""),
                                .concepts(title: "Common STAR Mistakes", body: "Too much Situation — Keep it to 1-2 sentences. Don't spend 30 seconds setting the scene.\nVague Action — \"I worked hard\" isn't specific. \"I reorganized the pipeline into parallel streams\" is.\nNo numbers in Result — \"It went well\" is weak. \"We cut time by 40%\" is memorable.\nMissing the learning — End with what you took away, especially if the result wasn't perfect.", icon: "exclamationmark.triangle"),
                                .tip("Keep the Situation brief — one or two sentences max. Most people spend too long setting the scene. Your audience cares most about what you did (Action) and what happened (Result)."),
                                .keyTakeaway("STAR turns any experience into a compelling story. It's the go-to framework for interviews, presentations, and anytime you need to share a real example."),
                            ])
                        ),
                        .practice(id: "w3_l2_a2", title: "Practice with STAR", description: "Record a response about a personal experience using STAR. Think of a challenge you faced and walk through Situation → Task → Action → Result.", duration: 60, framework: "STAR"),
                    ]
                ),

                // ── W3 L3: The Power of Pauses ──────────────────────
                CurriculumLesson(
                    id: "w3_l3",
                    title: "The Power of Pauses",
                    objective: "Learn to use deliberate pauses for emphasis and clarity.",
                    activities: [
                        .lesson(
                            id: "w3_l3_a0",
                            title: "The art of strategic silence",
                            description: "Pauses aren't empty space — they're one of the most powerful tools in a speaker's toolkit.",
                            content: LessonContent(sections: [
                                .concepts(title: "Why Silence Is Powerful", body: "A well-placed pause does three things at once: it gives your audience time to absorb what you just said, it signals that something important is coming next, and it makes you look confident and in control.\nResearch shows that speakers who pause strategically are rated as more credible, more intelligent, and more persuasive than those who fill every moment with sound.\nThe irony: most people fear silence, but audiences love it.", icon: "pause.circle.fill"),
                                .concepts(title: "Four Types of Pauses", body: "The Emphasis Pause — Pause BEFORE a key word or phrase. \"The most important thing is... [pause] ...trust.\" The silence creates anticipation.\nThe Transition Pause — Pause between major ideas. It's the verbal equivalent of a paragraph break — it signals \"new topic ahead.\"\nThe Reflection Pause — Pause AFTER making a point. Give the audience a moment to think about what you said. This is where insights land.\nThe Recovery Pause — When you lose your place, pause instead of filling with \"um.\" The audience sees composure; you buy yourself time to regroup.", icon: "list.bullet"),
                                .example(title: "Pause Timing Guide", body: "Short pause (0.5-1 second): Between sentences. Feels natural, keeps flow.\n\nMedium pause (1-2 seconds): Between major ideas or after an important point. Signals a shift.\n\nLong pause (2-3 seconds): Before or after your most important statement. Creates dramatic emphasis. Use sparingly — 1-2 per talk maximum."),
                                .tip("Pauses always feel longer to the speaker than to the audience. What feels like an eternity to you is just a comfortable beat for them. Practice pausing for a full 2 seconds — time it. It will feel impossibly long at first. That's normal."),
                                .keyTakeaway("Silence is not the absence of speaking — it's speaking without words. The pause is where your message lands."),
                            ])
                        ),
                        .drill(id: "w3_l3_a1", title: "Pause practice drill", description: "A 45-second drill where you practice inserting deliberate pauses at marked intervals. The drill tracks your silence at each pause point.", mode: "pausePractice"),
                        .practice(id: "w3_l3_a2", title: "Record with pauses", description: "Record a 60-second session and deliberately pause for 1-2 seconds between your main points. Aim for at least 3 clear pauses.", duration: 60),
                    ]
                ),

                // ── W3 L4: Sentence Organization ─────────────────────
                CurriculumLesson(
                    id: "w3_l4",
                    title: "Sentence Organization",
                    objective: "Practice completing thoughts before starting new ones.",
                    activities: [
                        .lesson(
                            id: "w3_l4_a1",
                            title: "Complete your sentences",
                            description: "A common speech habit is starting a new thought before finishing the current one. Focus on completing each idea.",
                            content: LessonContent(sections: [
                                .concepts(title: "Why Sentences Trail Off", body: "Your brain thinks faster than you speak. By the time you're mid-sentence, your mind has already jumped to the next idea.\nThis creates fragments — half-finished thoughts that leave listeners piecing together what you meant.\nThe fix is simple: finish the sentence you're on before starting the next one. It sounds obvious, but it takes real practice.", icon: "text.alignleft"),
                                .concepts(title: "The One-Thought Rule", body: "Each sentence should carry exactly one idea. When you feel the urge to add a second idea mid-sentence, that's your cue to finish the current one first.\nThink of it like texting: you'd never send half a message and start a new one. Give each thought its own complete sentence.\nThis single habit — completing each thought — makes you sound more organized, more confident, and more authoritative.", icon: "text.justify"),
                                .example(title: "Fragmented vs. Complete", body: "Fragmented: \"So the thing about this project is — well actually, the main issue was that we didn't — I mean, the timeline was really the problem because —\"\n\nComplete: \"The main issue with this project was the timeline. We underestimated how long testing would take. Next time, I'd build in an extra week as a buffer.\"\n\nThree clean sentences. Three complete ideas. Zero confusion."),
                                .tip("When you feel the urge to pivot mid-sentence, pause instead. Take a breath, finish your current thought, then start the new one. The pause buys your brain time to catch up."),
                                .keyTakeaway("One complete thought is worth more than three half-finished ones. Finish each sentence before moving on."),
                            ])
                        ),
                        .practice(id: "w3_l4_a2", title: "Organized speech practice", description: "Record a 90-second session focusing on completing each sentence before moving to the next. Aim for clear, complete thoughts.", duration: 90),
                    ]
                ),
            ]
        ),

        // ╔══════════════════════════════════════════════════════════════╗
        // ║  WEEK 4 — CONFIDENCE                                        ║
        // ╚══════════════════════════════════════════════════════════════╝

        CurriculumPhase(
            id: "week4", week: 4,
            title: "Confidence",
            description: "Push your comfort zone and celebrate your growth.",
            lessons: [

                // ── W4 L1: Managing Nerves ───────────────────────────
                CurriculumLesson(
                    id: "w4_l1",
                    title: "Managing Nerves",
                    objective: "Learn techniques to manage speaking anxiety.",
                    activities: [
                        .lesson(
                            id: "w4_l1_a0",
                            title: "Understanding speaking anxiety",
                            description: "Nerves aren't your enemy — they're energy. Learn to redirect them into powerful speaking.",
                            content: LessonContent(sections: [
                                .concepts(title: "Why We Get Nervous", body: "Speaking anxiety is one of the most common fears worldwide. It triggers the same fight-or-flight response as physical danger: rapid heartbeat, shallow breathing, sweaty palms, racing thoughts.\nThis isn't a flaw — it's your body preparing to perform. The adrenaline that makes you nervous is the same chemical that makes athletes run faster and musicians play with more intensity.\nThe goal isn't to eliminate nerves. It's to reframe them. Research from Harvard shows that people who say \"I'm excited\" before a speech perform significantly better than those who say \"I'm calm.\" Same feelings, different label, better outcome.", icon: "brain.head.profile"),
                                .concepts(title: "Three Anxiety Reset Techniques", body: "Physiological Sigh — Two quick inhales through your nose, then one long exhale through your mouth. This is the fastest known way to reduce heart rate. Works in under 30 seconds.\nGrounding (5-4-3-2-1) — Engage your senses to pull yourself out of anxious thoughts and into the present moment. You'll practice this next.\nPower Posture — Stand tall with shoulders back for 30 seconds before speaking. Research shows expansive postures reduce cortisol (stress hormone) and increase testosterone (confidence hormone).", icon: "shield.checkered"),
                                .tip("Nerves peak in the first 60-90 seconds of speaking, then gradually fade. If you can push through the first two minutes, the rest gets dramatically easier. Knowing this helps: the discomfort is temporary.", title: "The 10-Minute Rule"),
                                .keyTakeaway("Courage isn't the absence of fear — it's speaking despite the fear. Every time you record despite feeling nervous, you're building that courage muscle."),
                            ])
                        ),
                        .exercise(id: "w4_l1_a1", title: "Grounding exercise", description: "The 5-4-3-2-1 technique anchors you in the present moment. Name 5 things you see, 4 you hear, 3 you feel, 2 you smell, 1 you taste.", exerciseId: "grounding_54321"),
                        .exercise(id: "w4_l1_a2", title: "Power statements", description: "Read through affirmation statements designed to build speaking confidence. Say each one out loud with conviction.", exerciseId: "power_statements"),
                    ]
                ),

                // ── W4 L2: Impromptu Speaking ────────────────────────
                CurriculumLesson(
                    id: "w4_l2",
                    title: "Impromptu Speaking",
                    objective: "Get comfortable speaking without preparation.",
                    activities: [
                        .lesson(
                            id: "w4_l2_a0",
                            title: "Think on your feet",
                            description: "Learn the AREA method — a framework for organizing your thoughts instantly when you have zero prep time.",
                            content: LessonContent(sections: [
                                .concepts(title: "The AREA Method for Impromptu Speaking", body: "When someone puts you on the spot, your brain panics because it has no structure. AREA gives you one instantly:\nAssertion — State your position in one sentence. \"I believe remote work is here to stay.\"\nReason — Give one clear reason why. \"It's proven that flexible work increases both productivity and retention.\"\nEvidence — Support with a specific example or fact. \"Our company saw a 15% increase in output after going hybrid.\"\nAssertion — Restate your position to close the loop. \"That's why I believe remote work is the future.\"", icon: "bolt.fill"),
                                .concepts(title: "The 3-Second Rule", body: "When asked an unexpected question, take 3 seconds before answering. Not 1, not 5 — exactly 3.\nIn those 3 seconds: breathe, pick your Assertion, and choose one Reason. That's all you need to start.\nMost people start talking immediately because silence feels threatening. But those 3 seconds are the difference between rambling and a structured response.", icon: "clock"),
                                .tip("If you get a question you're not prepared for, bridge to what you do know. \"That's a great question. What I can tell you is...\" or \"I'm not sure about that specifically, but what I do know is...\" This buys you time and keeps you in control.", title: "The Bridge Technique"),
                                .keyTakeaway("Impromptu doesn't mean unstructured. AREA gives you a framework you can deploy in 3 seconds. The more you practice, the more automatic it becomes."),
                            ])
                        ),
                        .drill(id: "w4_l2_a1", title: "Impromptu sprint", description: "A 30-second challenge: you get a random topic with zero prep time. Just start talking. This builds your ability to think on your feet.", mode: "impromptuSprint"),
                        .practice(id: "w4_l2_a2", title: "Random prompt challenge", description: "Spin the prompt wheel and start recording immediately. No planning, no notes — just speak for 60 seconds.", duration: 60),
                    ]
                ),

                // ── W4 L3: Longer Sessions ───────────────────────────
                CurriculumLesson(
                    id: "w4_l3",
                    title: "Longer Sessions",
                    objective: "Build stamina with longer speaking sessions.",
                    activities: [
                        .lesson(
                            id: "w4_l3_a0",
                            title: "Building speaking endurance",
                            description: "Speaking for 3+ minutes requires a different skill set than short bursts. Here's how to build stamina.",
                            content: LessonContent(sections: [
                                .concepts(title: "The Stamina Challenge", body: "Most conversations happen in 15-30 second bursts. Speaking for 3 minutes straight is like running a mile after only ever doing sprints.\nThe main challenge isn't running out of words — it's running out of structure. Without a plan, you'll circle back to the same points or trail off.\nThe secret to longer talks: think in segments. A 3-minute talk is really just three 1-minute segments stitched together with transitions.", icon: "figure.run"),
                                .concepts(title: "The 3-Block Method", body: "Block 1 (First minute) — Open strong and state your main idea. Use PREP or AREA to structure this.\nBlock 2 (Middle minute) — Go deeper. Add a second example, explore a counter-argument, or share a related story.\nBlock 3 (Final minute) — Circle back to your main idea. Summarize what you covered and end with a memorable closing line.\nTransitions between blocks: \"Now here's where it gets interesting...\" \"On the other hand...\" \"And that brings me to the key point...\"", icon: "rectangle.split.3x1"),
                                .tip("Pick a topic you genuinely care about for your first long session. Passion is fuel — when you care about the subject, words come more easily and your energy stays high. Save the tough topics for later."),
                                .keyTakeaway("Long talks are just short talks connected well. Master the 3-Block Method and 3 minutes will feel natural."),
                            ])
                        ),
                        .practice(id: "w4_l3_a1", title: "3-minute session", description: "Your longest session yet. Record a full 3-minute session to build speaking endurance. Pick a topic you care about — passion makes longer talks easier.", duration: 180),
                        .review(id: "w4_l3_a2", title: "Review your growth", description: "Compare your latest recording with your very first one. Notice the differences in pace, fillers, and confidence."),
                    ]
                ),

                // ── W4 L4: Celebrate Your Progress ───────────────────
                CurriculumLesson(
                    id: "w4_l4",
                    title: "Celebrate Your Progress",
                    objective: "Review how far you've come and set future goals.",
                    activities: [
                        .review(id: "w4_l4_a1", title: "Before and after", description: "Listen to your first and latest recordings back-to-back. You'll hear the growth."),
                        .lesson(
                            id: "w4_l4_a2",
                            title: "Your foundation is set",
                            description: "You've built the core skills. Now it's time to level up with advanced techniques.",
                            content: LessonContent(sections: [
                                .callout(title: "Milestone Reached!", body: "You've completed the foundation phase of the SpeakUp Learning Path. You now have baseline awareness, core technique, structural frameworks, and confidence tools. That's a real achievement.", icon: "trophy.fill"),
                                .concepts(title: "What You've Built", body: "Week 1 gave you awareness — you know your patterns, your filler habits, and your natural pace.\nWeek 2 gave you technique — breathing, filler control, pace management, and warm-up routines.\nWeek 3 gave you structure — PREP, STAR, strategic pauses, and sentence completion.\nWeek 4 gave you confidence — anxiety management, impromptu skills, and endurance.", icon: "checkmark.circle"),
                                .concepts(title: "What's Ahead", body: "The advanced path takes you from competent to compelling. You'll learn:\nVocal mastery — pitch, volume, emphasis, and articulation that commands attention.\nAdvanced frameworks — Rule of Three, Problem-Solution-Benefit, and more structures for any situation.\nStorytelling — how to open with a hook, build emotional connection, and close with impact.\nReal-world application — elevator pitches, Q&A handling, and full 5-minute presentations.", icon: "arrow.up.right"),
                                .tip("The skills you've built in 4 weeks will fade without practice. Even 60 seconds a day maintains your progress. The advanced lessons ahead will compound everything you've learned so far.", title: "Keep the Momentum"),
                                .keyTakeaway("You've gone from baseline to capable. The next four weeks will take you from capable to compelling. Keep going."),
                            ])
                        ),
                    ]
                ),
            ]
        ),

        // ╔══════════════════════════════════════════════════════════════╗
        // ║  WEEK 5 — VOCAL MASTERY                                     ║
        // ╚══════════════════════════════════════════════════════════════╝

        CurriculumPhase(
            id: "week5", week: 5,
            title: "Vocal Mastery",
            description: "Command attention through pitch, volume, articulation, and emphasis.",
            lessons: [

                // ── W5 L1: Vocal Variety ─────────────────────────────
                CurriculumLesson(
                    id: "w5_l1",
                    title: "Vocal Variety",
                    objective: "Use pitch, tone, and inflection to make your speech engaging.",
                    activities: [
                        .lesson(
                            id: "w5_l1_a1",
                            title: "The monotone trap",
                            description: "A flat, unchanging voice puts people to sleep. Vocal variety is what makes people lean in and listen.",
                            content: LessonContent(sections: [
                                .concepts(title: "What Is Vocal Variety?", body: "Vocal variety is the range of changes in your pitch (high/low), pace (fast/slow), volume (loud/soft), and tone (warm/serious/playful) throughout your speech.\nMonotone speaking — using the same pitch, speed, and volume throughout — is the fastest way to lose an audience. Research shows listeners tune out after just 10 seconds of monotone delivery.\nGreat speakers sound like music: they rise for emphasis, drop for gravity, speed up for excitement, and slow down for importance.", icon: "waveform.path.ecg"),
                                .concepts(title: "The Four Dimensions of Your Voice", body: "Pitch — The musical note of your voice. Raise it for questions and excitement. Lower it for authority and seriousness.\nPace — Speed of delivery. Speed up to convey enthusiasm or urgency. Slow down for key points and dramatic moments.\nVolume — Loudness. Get louder for passion and emphasis. Get softer to draw people in and create intimacy.\nTone — The emotional color. Warm and friendly for stories. Serious and measured for data. Playful and light for humor.", icon: "slider.horizontal.3"),
                                .example(title: "Monotone vs. Dynamic", body: "Monotone: \"I'm really excited about this project. It's going to change everything. The team has worked so hard.\" (Every word at the same pitch and speed.)\n\nDynamic: \"I'm really EXCITED about this project. [pause] It's going to change... everything. [slower] The team has worked SO hard.\" (Pitch rises on 'excited,' pause for emphasis, slower for impact, volume up on 'so.')"),
                                .tip("Read children's books out loud. Seriously. Children's books force you to use exaggerated vocal variety — big voices for characters, slow for suspense, fast for action. It's the best vocal variety training there is."),
                                .keyTakeaway("Your voice is an instrument with range. Use all of it. A dynamic voice doesn't just convey information — it conveys emotion, and emotion is what people remember."),
                            ])
                        ),
                        .exercise(id: "w5_l1_a2", title: "Siren vocal warm-up", description: "Glide your voice from your lowest note to your highest and back. This expands your pitch range before practicing.", exerciseId: "siren"),
                        .practice(id: "w5_l1_a3", title: "Vocal variety practice", description: "Record a 90-second session and deliberately vary your pitch, pace, and volume. Try raising your voice for key points and slowing down for emphasis.", duration: 90),
                    ]
                ),

                // ── W5 L2: Volume & Projection ───────────────────────
                CurriculumLesson(
                    id: "w5_l2",
                    title: "Volume & Projection",
                    objective: "Learn to project your voice with confidence and control.",
                    activities: [
                        .lesson(
                            id: "w5_l2_a1",
                            title: "Speaking with presence",
                            description: "Projection isn't about being loud — it's about being heard clearly without straining.",
                            content: LessonContent(sections: [
                                .concepts(title: "Projection vs. Volume", body: "Volume is how loud you are. Projection is how far your voice carries clearly.\nYou can be loud and still hard to understand (yelling). You can be quiet and still fill a room (projection).\nProjection comes from your diaphragm, not your throat. When you push air from your belly, your voice carries naturally without strain. When you push from your throat, you sound strained and tire quickly.", icon: "speaker.wave.3.fill"),
                                .concepts(title: "Three Projection Techniques", body: "Aim past your audience — Imagine your voice needs to reach the back wall, not just the person in front of you. This mental shift naturally increases your projection.\nOpen your mouth — Most people don't open their mouth enough when speaking. A wider opening creates a clearer, more resonant sound.\nSupport with breath — Take a full belly breath before important sentences. The air pressure from your diaphragm is what carries your voice.", icon: "megaphone.fill"),
                                .tip("Imagine a volume dial from 1-10. Normal conversation is a 4. A meeting room is a 6. A presentation is a 7. Practice intentionally speaking at each level so you can shift gears on demand. Most people live at 3-4 and never realize they have more range.", title: "The Volume Dial Technique"),
                                .keyTakeaway("A projected voice commands respect. It tells the room: I have something worth hearing, and I'm confident enough to fill this space with it."),
                            ])
                        ),
                        .exercise(id: "w5_l2_a2", title: "Deep belly breathing", description: "Activate your diaphragm with deep belly breaths. Place a hand on your stomach — it should expand on each inhale.", exerciseId: "deep_belly"),
                        .practice(id: "w5_l2_a3", title: "Projection practice", description: "Record a 60-second session and imagine you're speaking to someone across a large room. Focus on clear, full sound without shouting.", duration: 60),
                    ]
                ),

                // ── W5 L3: Articulation & Clarity ────────────────────
                CurriculumLesson(
                    id: "w5_l3",
                    title: "Articulation & Clarity",
                    objective: "Sharpen your pronunciation so every word is crystal clear.",
                    activities: [
                        .lesson(
                            id: "w5_l3_a1",
                            title: "The clarity advantage",
                            description: "Clear articulation makes you sound polished and professional. Mumbling makes you sound uncertain.",
                            content: LessonContent(sections: [
                                .concepts(title: "Why Articulation Matters", body: "Articulation is how crisply you pronounce each sound and syllable. It's the difference between \"going to\" and \"gonna,\" between \"want to\" and \"wanna.\"\nPoor articulation forces listeners to work harder to understand you. Even if your ideas are brilliant, mumbled delivery makes them inaccessible.\nThe good news: articulation is purely mechanical. It's about training the muscles of your mouth, tongue, and jaw. Like any muscle, they respond to exercise.", icon: "mouth.fill"),
                                .concepts(title: "Common Articulation Weak Spots", body: "Swallowed endings — Dropping the last syllable: \"importan\" instead of \"important,\" \"differen\" instead of \"different.\"\nLazy consonants — Soft T's and D's: \"wader\" instead of \"water,\" \"bedder\" instead of \"better.\"\nMerged words — Running words together: \"didja\" instead of \"did you,\" \"whatcha\" instead of \"what are you.\"\nThe fix for all three: slow down slightly and over-pronounce for a week. It will feel exaggerated, but it recalibrates your default.", icon: "exclamationmark.triangle"),
                                .tip("Hold a pen or pencil horizontally between your teeth and try to speak clearly. This forces your mouth to over-articulate. Practice for 2 minutes, then remove the pen and speak normally — you'll notice an immediate improvement in clarity.", title: "The Pencil Trick"),
                                .keyTakeaway("Clear articulation isn't about being formal — it's about being understood. The easier you are to listen to, the more people will actually listen."),
                            ])
                        ),
                        .exercise(id: "w5_l3_a2", title: "Vowel stretches", description: "Exaggerate each vowel sound to stretch and activate your mouth muscles. Open wide!", exerciseId: "vowel_stretches"),
                        .exercise(id: "w5_l3_a3", title: "Consonant drills", description: "Rapidly repeat consonant pairs to build articulation precision. Focus on crisp, clean sounds.", exerciseId: "consonant_drills"),
                    ]
                ),

                // ── W5 L4: Emphasis & Word Stress ────────────────────
                CurriculumLesson(
                    id: "w5_l4",
                    title: "Emphasis & Word Stress",
                    objective: "Make key words and phrases land with impact.",
                    activities: [
                        .lesson(
                            id: "w5_l4_a1",
                            title: "Making words land",
                            description: "The words you emphasize change the meaning of your entire sentence. Emphasis is how you guide your audience's attention.",
                            content: LessonContent(sections: [
                                .concepts(title: "How Emphasis Changes Meaning", body: "The same sentence means different things depending on which word you stress:\n\"I didn't say she stole the money\" — Someone else said it.\n\"I didn't SAY she stole the money\" — I implied it.\n\"I didn't say SHE stole the money\" — Someone else stole it.\n\"I didn't say she stole THE MONEY\" — She stole something else.\nSeven words, seven completely different meanings. Emphasis is how you control which message your audience receives.", icon: "bold"),
                                .concepts(title: "Four Ways to Emphasize", body: "Volume — Get louder on the key word. The simplest and most intuitive method.\nPitch shift — Raise or lower your pitch on the important word. Higher for surprise, lower for gravity.\nPause before — Insert a beat of silence right before the key word. The pause creates anticipation.\nSlow down — Say the key word or phrase slower than the surrounding words. Stretching a word signals importance.", icon: "textformat.size"),
                                .example(title: "Emphasis in Practice", body: "Flat: \"This is the most important decision we'll make this year.\"\n\nWith emphasis: \"This is the MOST important... decision... we'll make this year.\"\n\nThe emphasized version slows down on 'most,' pauses before 'decision,' and slightly drops pitch on 'this year.' The flat version delivers information. The emphasized version delivers impact."),
                                .tip("Before speaking, mentally highlight 2-3 words per sentence that carry the most meaning. Those are your emphasis targets. Don't emphasize everything — when everything is important, nothing is.", title: "The Highlight Rule"),
                                .keyTakeaway("Emphasis is your vocal highlighter. Use it to guide your audience to exactly what matters most."),
                            ])
                        ),
                        .drill(id: "w5_l4_a2", title: "Pace variation drill", description: "Use the pace control drill to practice speeding up and slowing down intentionally. Focus on slowing down at key moments.", mode: "paceControl"),
                        .practice(id: "w5_l4_a3", title: "Emphasis practice", description: "Record a 90-second session and deliberately emphasize 2-3 key words per sentence using volume, pitch, or pace changes.", duration: 90),
                    ]
                ),
            ]
        ),

        // ╔══════════════════════════════════════════════════════════════╗
        // ║  WEEK 6 — ADVANCED FRAMEWORKS                               ║
        // ╚══════════════════════════════════════════════════════════════╝

        CurriculumPhase(
            id: "week6", week: 6,
            title: "Advanced Frameworks",
            description: "Master four more speech structures for any situation.",
            lessons: [

                // ── W6 L1: Rule of Three ─────────────────────────────
                CurriculumLesson(
                    id: "w6_l1",
                    title: "The Rule of Three",
                    objective: "Structure ideas in groups of three for maximum memorability.",
                    activities: [
                        .lesson(
                            id: "w6_l1_a1",
                            title: "Why three is magic",
                            description: "The human brain loves patterns of three. It's the smallest number that creates a pattern and the easiest to remember.",
                            content: LessonContent(sections: [
                                .concepts(title: "The Rule of Three", body: "Three is the most persuasive number in communication. Our brains are wired to recognize patterns, and three is the minimum needed to create one.\nTwo points feel incomplete. Four feels like a list. Three feels like a complete, satisfying argument.\nThis pattern appears everywhere: \"Life, liberty, and the pursuit of happiness.\" \"Blood, sweat, and tears.\" \"Location, location, location.\" \"Stop, drop, and roll.\"", icon: "3.circle.fill"),
                                .concepts(title: "How to Use the Rule of Three", body: "Three reasons — \"There are three reasons this matters. First... Second... Third...\"\nThree examples — Give three specific instances instead of one. One example is anecdotal; three is a pattern.\nThree-part structure — Open, Body, Close. Or Problem, Solution, Benefit. Or Past, Present, Future.\nTricolon — Three parallel phrases for rhetorical impact: \"We came, we saw, we conquered.\"", icon: "list.number"),
                                .example(title: "Rule of Three in Action", body: "Weak: \"There are several reasons we should adopt this strategy. It saves money. It also saves time. Plus it reduces risk. And it improves quality. Also the team prefers it.\"\n\nStrong: \"There are three reasons to adopt this strategy: it saves money, it saves time, and it reduces risk.\"\n\nFive scattered points vs. three focused ones. The second version is clearer, more memorable, and more persuasive."),
                                .tip("Put your strongest point LAST in your group of three. People remember endings best. Build from good to better to best: \"It's faster, it's cheaper, and most importantly, it's safer.\"", title: "The Power Position"),
                                .keyTakeaway("When you have five things to say, find a way to say three. Your audience will remember all of them instead of none of them."),
                            ])
                        ),
                        .practice(id: "w6_l1_a2", title: "Rule of Three practice", description: "Record a 60-second response to any question, structuring your answer with exactly three points. Signal them clearly: \"First... Second... And most importantly...\"", duration: 60),
                    ]
                ),

                // ── W6 L2: Problem-Solution-Benefit ──────────────────
                CurriculumLesson(
                    id: "w6_l2",
                    title: "Problem-Solution-Benefit",
                    objective: "Master the most persuasive framework in communication.",
                    activities: [
                        .lesson(
                            id: "w6_l2_a1",
                            title: "The PSB framework",
                            description: "Every great pitch follows the same pattern: here's the problem, here's how to fix it, here's why you should care.",
                            content: LessonContent(sections: [
                                .concepts(title: "Problem-Solution-Benefit", body: "Problem — Name the pain your audience feels. Make them nod and think \"yes, that's exactly my struggle.\"\nSolution — Present your answer to that pain. Be specific about what to do, not just what to think.\nBenefit — Paint the picture of life after the solution. What changes? What improves? What do they gain?\nThis framework works because it follows the brain's natural decision-making process: recognize a need, evaluate an option, imagine the outcome.", icon: "arrow.triangle.2.circlepath"),
                                .example(title: "PSB in Action", body: "Problem: \"Most people dread public speaking. They avoid meetings, turn down opportunities, and let others take the spotlight — all because speaking feels terrifying.\"\n\nSolution: \"The fix isn't talent or charisma. It's practice with feedback. Record yourself, review the analysis, and focus on one skill at a time. Small daily sessions build confidence faster than any seminar.\"\n\nBenefit: \"In four weeks, you'll speak with less anxiety, fewer fillers, and more clarity. You'll volunteer for presentations instead of avoiding them. That's career-changing.\""),
                                .concepts(title: "When to Use PSB", body: "Pitching an idea — \"Here's what's broken, here's my solution, here's what we gain.\"\nPersuading someone — \"Here's why the current approach hurts us, here's the better way, here's the payoff.\"\nMotivating action — \"Here's the challenge we face, here's what we can do, here's why it matters.\"\nPSB is the backbone of every TED talk, every sales pitch, and every compelling proposal.", icon: "checkmark.circle"),
                                .tip("Spend the most time on the Problem. If your audience doesn't feel the pain, they won't care about your solution. Use specific, relatable examples of the problem — make it personal."),
                                .keyTakeaway("Problem-Solution-Benefit is persuasion in its purest form. Name the pain, offer the cure, show the better future."),
                            ])
                        ),
                        .practice(id: "w6_l2_a2", title: "PSB pitch practice", description: "Record a 90-second pitch using Problem-Solution-Benefit. Pick any topic: a product, an idea, a habit change. Structure it as Problem → Solution → Benefit.", duration: 90),
                    ]
                ),

                // ── W6 L3: What - So What - Now What ─────────────────
                CurriculumLesson(
                    id: "w6_l3",
                    title: "What - So What - Now What",
                    objective: "Make any information immediately actionable for your audience.",
                    activities: [
                        .lesson(
                            id: "w6_l3_a1",
                            title: "Making information matter",
                            description: "Most people share information without explaining why it matters or what to do about it. This framework fixes that.",
                            content: LessonContent(sections: [
                                .concepts(title: "The What-So What-Now What Framework", body: "What — State the fact, data, observation, or situation clearly. Just the information.\nSo What — Explain why it matters. Why should the audience care? What does it mean for them?\nNow What — Tell them what to do about it. What action should they take? What's the next step?\nThis framework transforms you from an information-dumper into a strategic communicator. Anyone can share data; leaders explain its significance and drive action.", icon: "arrow.right.arrow.left"),
                                .example(title: "The Framework in Action", body: "Without the framework: \"Our customer satisfaction score dropped 12 points this quarter.\"\n\nWith the framework:\nWhat: \"Our customer satisfaction score dropped 12 points this quarter.\"\nSo What: \"If this trend continues, we'll lose our top-tier rating, which could cost us the enterprise contract renewal in September.\"\nNow What: \"I recommend we run a customer survey by Friday and schedule a response team meeting next Monday to address the top three complaints.\""),
                                .concepts(title: "Perfect For These Situations", body: "Status updates — Don't just report numbers. Say what they mean and what to do about them.\nSharing research — State the finding, explain the implication, recommend an action.\nGiving feedback — Describe what happened, explain why it matters, suggest the change.\nTeam communications — Share the news, explain the impact, outline next steps.", icon: "checkmark.circle"),
                                .tip("The 'So What' is the part most people skip, and it's the most important part. If you can't explain why something matters to your audience, reconsider whether you should be sharing it at all."),
                                .keyTakeaway("Information without context is noise. What-So What-Now What turns noise into signal. Always answer: why does this matter, and what should we do?"),
                            ])
                        ),
                        .practice(id: "w6_l3_a2", title: "What-So What-Now What practice", description: "Record a 60-second update about something that happened recently — at work, in the news, or in your life. Structure it as What → So What → Now What.", duration: 60),
                    ]
                ),

                // ── W6 L4: The Bridge Framework ──────────────────────
                CurriculumLesson(
                    id: "w6_l4",
                    title: "The Bridge Framework",
                    objective: "Guide your audience from where they are to where you want them to be.",
                    activities: [
                        .lesson(
                            id: "w6_l4_a1",
                            title: "Building a bridge",
                            description: "The Bridge takes your audience on a journey from the current reality to a better future — with you as the guide.",
                            content: LessonContent(sections: [
                                .concepts(title: "Present → Bridge → Future", body: "Present — Describe the current reality. Where are things now? What's the status quo? What challenges exist?\nBridge — Explain the transition. What needs to change? What's the path forward? What's your proposed shift?\nFuture — Paint the destination. What does the better world look like? What will be different once you cross the bridge?\nThis framework creates narrative momentum. It gives your audience a reason to move from here to there — with you leading the way.", icon: "arrow.right"),
                                .example(title: "The Bridge in Action", body: "Present: \"Right now, our onboarding process takes 3 weeks and new hires report feeling lost for their first month. We lose 15% of new hires in their first 90 days.\"\n\nBridge: \"By restructuring onboarding into a buddy-system model with daily check-ins and a clear 30-60-90 day roadmap, we can change this.\"\n\nFuture: \"Imagine new hires feeling productive in week one, confident by month one, and fully ramped by month two. Retention improves, managers spend less time hand-holding, and our team velocity increases.\""),
                                .concepts(title: "Why the Bridge Works", body: "It creates contrast — The gap between Present and Future makes the audience feel the need for change.\nIt provides a path — The Bridge answers the question \"how do we get there?\" without being overwhelming.\nIt's visual — People can literally picture moving from one state to another, which makes your argument tangible.\nIt works at any scale — From a 30-second suggestion to a 30-minute presentation.", icon: "brain.head.profile"),
                                .tip("Make the Future vivid and specific. Don't say \"things will be better.\" Say \"new hires will be productive in week one.\" The more concrete your future state, the more compelling your bridge becomes."),
                                .keyTakeaway("The Bridge is how leaders create change. Show them where we are, show them where we could be, and show them the path between."),
                            ])
                        ),
                        .practice(id: "w6_l4_a2", title: "Bridge framework practice", description: "Record a 90-second pitch about a change you'd like to see — at work, in your community, or in your life. Structure it as Present → Bridge → Future.", duration: 90),
                    ]
                ),
            ]
        ),

        // ╔══════════════════════════════════════════════════════════════╗
        // ║  WEEK 7 — STORYTELLING & ENGAGEMENT                         ║
        // ╚══════════════════════════════════════════════════════════════╝

        CurriculumPhase(
            id: "week7", week: 7,
            title: "Storytelling & Engagement",
            description: "Hook your audience, build emotional connection, and close with lasting impact.",
            lessons: [

                // ── W7 L1: The Story Arc ─────────────────────────────
                CurriculumLesson(
                    id: "w7_l1",
                    title: "The Story Arc",
                    objective: "Structure compelling stories that hold attention from start to finish.",
                    activities: [
                        .lesson(
                            id: "w7_l1_a1",
                            title: "The anatomy of a great story",
                            description: "Every memorable story follows the same arc. Learn it, and you can make any experience captivating.",
                            content: LessonContent(sections: [
                                .concepts(title: "Why Stories Beat Facts", body: "When you hear a statistic, two brain areas activate (language processing). When you hear a story, seven areas activate — including the motor cortex, sensory cortex, and emotional centers.\nStories are literally more engaging than data. They trigger empathy, build trust, and make information 22 times more memorable than facts alone.\nEvery great communicator — from CEOs to comedians — is fundamentally a storyteller.", icon: "book.fill"),
                                .concepts(title: "The Five-Part Story Arc", body: "Setup — Introduce the character (usually you) and the normal world. Keep it brief: who, where, when.\nConflict — Something disrupts the normal world. A problem, a challenge, a surprising moment. This is the hook.\nStruggles — The attempt to resolve the conflict. What did you try? What went wrong? What was hard? This is where tension builds.\nTurning Point — The moment of insight, decision, or breakthrough that changed everything.\nResolution — The outcome and the lesson. What changed? What did you learn? How are things different now?", icon: "theatermasks.fill"),
                                .example(title: "A Simple Story Arc", body: "Setup: \"Two years ago, I was terrified of speaking in meetings.\"\nConflict: \"My manager asked me to present our quarterly results to the entire department — 200 people.\"\nStruggles: \"I spent a week writing and rewriting my script. I practiced in the mirror until 2am. The morning of, my hands were shaking.\"\nTurning Point: \"Thirty seconds in, I forgot my script completely. I panicked — then I just started talking about what the numbers actually meant to our team.\"\nResolution: \"Three people came up afterward and said it was the most authentic presentation they'd ever seen. I learned that connection beats perfection every time.\""),
                                .tip("Start your story in the middle of the action, not at the beginning. \"My hands were shaking as I walked to the podium\" is far more gripping than \"Two years ago my manager asked me to do a presentation.\" You can fill in the backstory once you've hooked them."),
                                .keyTakeaway("Every experience you've had is a story waiting to be told. The arc — Setup, Conflict, Struggles, Turning Point, Resolution — is your blueprint for making any experience captivating."),
                            ])
                        ),
                        .practice(id: "w7_l1_a2", title: "Tell a story", description: "Record a 120-second story from your life using the five-part arc: Setup → Conflict → Struggles → Turning Point → Resolution. Pick any real experience.", duration: 120),
                    ]
                ),

                // ── W7 L2: Opening Hooks ─────────────────────────────
                CurriculumLesson(
                    id: "w7_l2",
                    title: "Opening Hooks",
                    objective: "Grab your audience's attention in the first 10 seconds.",
                    activities: [
                        .lesson(
                            id: "w7_l2_a1",
                            title: "7 types of opening hooks",
                            description: "You have 7-10 seconds to capture attention. These seven hook types work every time.",
                            content: LessonContent(sections: [
                                .concepts(title: "The First 10 Seconds", body: "Your audience decides in the first 10 seconds whether they'll pay attention or zone out. This decision is largely unconscious — it's based on whether your opening triggers curiosity.\nThe worst opening? \"Hi, my name is... and today I'll be talking about...\" This is the verbal equivalent of a loading screen. Your audience has already checked out.\nGreat speakers start with a hook — something that grabs attention and creates a reason to keep listening.", icon: "hand.raised.fingers.spread.fill"),
                                .concepts(title: "Seven Hooks That Work", body: "1. The Question — Ask something that makes them think. \"What would you do if you had 24 hours to live?\"\n2. The Surprising Fact — Lead with something unexpected. \"You spend 93% of your life indoors.\"\n3. The Bold Statement — Say something provocative. \"Everything you know about productivity is wrong.\"\n4. The Story — Drop them into a scene. \"I was standing at the edge of a cliff when my phone rang.\"\n5. The Quotation — Use a powerful quote, then react to it.\n6. The Imagine Prompt — \"Imagine waking up tomorrow and your biggest fear is gone.\"\n7. The Callback — Reference something the audience just experienced. \"Five minutes ago, every one of you checked your phone.\"", icon: "list.number"),
                                .example(title: "Same Topic, Different Hooks", body: "Topic: The importance of sleep\n\nQuestion: \"How many hours did you sleep last night? If it's under seven, you're operating with the cognitive ability of someone who's legally drunk.\"\n\nSurprising fact: \"In 1942, less than 8% of Americans slept six hours or less. Today, it's nearly 50%.\"\n\nBold statement: \"The most productive thing you can do right now is take a nap.\"\n\nStory: \"Last Tuesday at 3pm, I fell asleep in a meeting with our CEO.\""),
                                .tip("Write your hook LAST. Finish your talk, then ask: what single opening line would make someone need to hear the rest? Your best hook is often hiding in your content — pull it to the front."),
                                .keyTakeaway("Never start with your name or your topic. Start with a hook that creates curiosity. The introduction can come after you've earned their attention."),
                            ])
                        ),
                        .drill(id: "w7_l2_a2", title: "Quick-start drill", description: "Impromptu sprint with a twist: focus entirely on your opening line. Get a random topic and nail the first 10 seconds.", mode: "impromptuSprint"),
                        .practice(id: "w7_l2_a3", title: "Hook practice", description: "Record a 60-second talk that opens with a strong hook. Try a question, a surprising fact, or a bold statement. No introductions — start with the hook.", duration: 60),
                    ]
                ),

                // ── W7 L3: Emotional Connection ──────────────────────
                CurriculumLesson(
                    id: "w7_l3",
                    title: "Emotional Connection",
                    objective: "Use vivid language and vulnerability to create genuine connection.",
                    activities: [
                        .lesson(
                            id: "w7_l3_a1",
                            title: "Speaking to the heart",
                            description: "Facts inform. Emotions move people to action. The best speakers do both.",
                            content: LessonContent(sections: [
                                .concepts(title: "Why Emotion Matters", body: "Neuroscience shows that decisions are made emotionally first and justified logically second. If you only speak to logic, you'll inform but never inspire.\nEmotional connection doesn't mean being dramatic or manipulative. It means being specific, vivid, and honest enough that your audience feels something.\nThe speakers who change minds aren't the ones with the best data. They're the ones who make people care.", icon: "heart.fill"),
                                .concepts(title: "Three Tools for Emotional Connection", body: "Sensory Detail — Don't say \"it was a bad day.\" Say \"I sat in my car in the parking lot, staring at the rain on the windshield, too tired to open the door.\" Put people in the scene.\nVulnerability — Share what you felt, not just what happened. \"I was terrified\" is more connecting than \"it was challenging.\" Audiences trust speakers who are honest about their humanity.\nContrast — Juxtapose the struggle with the outcome. The greater the contrast, the greater the emotional impact. \"I went from failing every class to getting my PhD\" hits harder than \"I did well in school.\"", icon: "sparkles"),
                                .example(title: "Abstract vs. Vivid", body: "Abstract: \"The experience was really meaningful to me and taught me a lot about perseverance.\"\n\nVivid: \"I remember sitting on the floor of my apartment at 2am, surrounded by rejection letters, thinking maybe everyone was right — maybe I wasn't cut out for this. Then I opened one more email. And everything changed.\""),
                                .tip("Start small. You don't need to share your deepest fears. Even mild vulnerability builds trust: \"I was nervous about this\" or \"I didn't know the answer at first.\" As you build confidence, you can go deeper. Audiences reward honesty with attention.", title: "The Vulnerability Ladder"),
                                .keyTakeaway("Logic makes people think. Emotion makes people act. The most powerful speaking combines both — and emotional connection is built with specificity, vulnerability, and vivid detail."),
                            ])
                        ),
                        .exercise(id: "w7_l3_a2", title: "Visualize a meaningful moment", description: "Use the visualization exercise to reconnect with a meaningful speaking or life experience. This emotional grounding will fuel your practice recording.", exerciseId: "visualize_success"),
                        .practice(id: "w7_l3_a3", title: "Emotional depth practice", description: "Record a 90-second story about a moment that mattered to you. Focus on sensory details and how you felt. Let the audience see and feel what you experienced.", duration: 90),
                    ]
                ),

                // ── W7 L4: Strong Closings ───────────────────────────
                CurriculumLesson(
                    id: "w7_l4",
                    title: "Strong Closings",
                    objective: "End every talk with impact so your message sticks.",
                    activities: [
                        .lesson(
                            id: "w7_l4_a1",
                            title: "The last thing they hear",
                            description: "Your closing is the last impression you leave. A strong ending can save an average talk; a weak ending can ruin a great one.",
                            content: LessonContent(sections: [
                                .concepts(title: "Why Closings Matter", body: "The Peak-End Rule in psychology says people judge an experience based on the most intense moment and the ending — not the average.\nThis means your closing has disproportionate power over how your audience remembers your entire talk.\nThe worst closing? \"So, yeah... that's pretty much it.\" \"Um, I think that's all I have.\" \"Any questions?\" These endings dissolve everything you've built.", icon: "flag.checkered"),
                                .concepts(title: "Six Powerful Closing Techniques", body: "1. The Callback — Reference your opening hook. This creates a satisfying loop.\n2. The Challenge — Call your audience to action. \"Starting tomorrow, I challenge you to...\"\n3. The Powerful Quote — End with words more eloquent than your own. Let the quote resonate.\n4. The Three-Word Phrase — Distill your message into a mantra. \"Start. Today. Now.\"\n5. The Story Resolution — If you opened with a story, finish it in the closing.\n6. The Vision — Paint a picture of the future if they act on your message.", icon: "list.number"),
                                .example(title: "Weak vs. Strong Closings", body: "Weak: \"So that's everything I wanted to talk about regarding our team's goals this quarter. I hope that was helpful. Does anyone have questions?\"\n\nStrong (Callback + Challenge): \"At the start, I asked how many of you have set a goal and given up within a week. Most of you raised your hands. By the end of this quarter, I want zero hands up. Here's the commitment: pick one goal from today's list and protect 30 minutes for it every morning. One goal. Thirty minutes. Ninety days. That's how we get there.\"\n\nStrong (Vision): \"Imagine walking into next quarter's review and seeing every metric in green. That's not a fantasy — it's the direct result of the three changes we discussed today. Let's make it happen.\""),
                                .tip("Signal your closing. Say \"I'll leave you with this...\" or \"If you remember one thing from today...\" This verbal cue tells the audience to pay extra attention — they know the payoff is coming. Then deliver your strongest line."),
                                .keyTakeaway("Your last sentence is your most valuable sentence. Plan it, practice it, and deliver it with conviction. Never let your talk just... trail off."),
                            ])
                        ),
                        .practice(id: "w7_l4_a2", title: "Strong closing practice", description: "Record a 90-second mini-talk on any topic. Focus on ending with power: use a callback, a challenge, a vision, or a powerful quote. Plan your last sentence before you start.", duration: 90),
                    ]
                ),
            ]
        ),

        // ╔══════════════════════════════════════════════════════════════╗
        // ║  WEEK 8 — REAL-WORLD MASTERY                                ║
        // ╚══════════════════════════════════════════════════════════════╝

        CurriculumPhase(
            id: "week8", week: 8,
            title: "Real-World Mastery",
            description: "Apply everything you've learned in real-world scenarios.",
            lessons: [

                // ── W8 L1: Handling Q&A ──────────────────────────────
                CurriculumLesson(
                    id: "w8_l1",
                    title: "Handling Q&A",
                    objective: "Answer tough questions with poise using structured techniques.",
                    activities: [
                        .lesson(
                            id: "w8_l1_a1",
                            title: "Mastering the Q&A",
                            description: "Q&A sessions are where credibility is won or lost. These techniques ensure you always have a structured answer.",
                            content: LessonContent(sections: [
                                .concepts(title: "Why Q&A Is the Real Test", body: "Presentations are rehearsed. Q&A is live. It's where your audience sees how you really think.\nGreat Q&A answers combine everything you've learned: impromptu structure (AREA), pause management, vocal confidence, and framework selection.\nThe biggest mistake in Q&A? Answering before you've thought. The second biggest? Rambling because you don't know when to stop.", icon: "questionmark.bubble.fill"),
                                .concepts(title: "The CLEAR Method for Q&A", body: "Clarify — Make sure you understand the question. \"Just to confirm, are you asking about...?\"\nListen — Don't plan your answer while the question is being asked. Fully hear it first.\nEcho — Paraphrase the question back briefly. This buys you time and shows respect.\nAnswer — Use PREP, AREA, or Rule of Three. Keep it to 30-60 seconds.\nReturn — Check if you answered their question. \"Does that address what you were asking?\"", icon: "arrow.uturn.right"),
                                .concepts(title: "Handling Tough Questions", body: "\"I don't know\" — Say it confidently: \"I don't have that figure right now, but I'll follow up by end of day.\" Honesty with a follow-up plan beats a bad guess.\nHostile questions — Stay calm, acknowledge the concern, bridge to your point: \"I understand the frustration. What I can share is...\"\nOff-topic questions — Redirect with grace: \"That's an important topic that deserves its own discussion. For today, let me focus on...\"\nMulti-part questions — \"You asked three things. Let me take them one at a time.\"", icon: "shield.checkered"),
                                .tip("Most Q&A answers should be under 30 seconds. If you're past 45 seconds, you're probably rambling. Say your point, give one supporting detail, and stop. Silence after a clear answer is powerful.", title: "The 30-Second Rule"),
                                .keyTakeaway("Q&A is not a threat — it's an opportunity to demonstrate expertise and poise. With the CLEAR method, every question becomes a chance to shine."),
                            ])
                        ),
                        .drill(id: "w8_l1_a2", title: "Rapid-fire Q&A drill", description: "Impromptu sprint simulating a Q&A environment. Get a random topic and answer as if it's a question from the audience. 30 seconds, no prep.", mode: "impromptuSprint"),
                        .practice(id: "w8_l1_a3", title: "Q&A practice session", description: "Record a 60-second response to this question: \"What's the biggest challenge in your field right now, and how would you solve it?\" Use the CLEAR method.", duration: 60),
                    ]
                ),

                // ── W8 L2: The Elevator Pitch ────────────────────────
                CurriculumLesson(
                    id: "w8_l2",
                    title: "The Elevator Pitch",
                    objective: "Deliver a compelling 60-second pitch that makes people want to hear more.",
                    activities: [
                        .lesson(
                            id: "w8_l2_a1",
                            title: "60 seconds to convince",
                            description: "An elevator pitch isn't about cramming information into a minute — it's about creating curiosity in a minute.",
                            content: LessonContent(sections: [
                                .concepts(title: "What Makes a Great Elevator Pitch", body: "An elevator pitch has one job: make the listener want to continue the conversation. Not close a deal, not explain everything, just spark enough interest for a follow-up.\nMost pitches fail because they try to say everything. The best pitches leave people wanting more.\nYou need: a hook (5 seconds), a problem (10 seconds), your solution (15 seconds), proof it works (15 seconds), and a clear ask (15 seconds).", icon: "building.2.fill"),
                                .concepts(title: "The Pitch Structure", body: "Hook — One sentence that grabs attention. A question, a surprising stat, or a bold claim.\nProblem — The pain point your audience relates to. Make them nod.\nSolution — What you do / what your idea is. Keep it simple enough for a 10-year-old to understand.\nProof — One piece of evidence: a number, a testimonial, a result. Credibility in one sentence.\nAsk — What do you want them to do? Exchange cards? Schedule a call? Always end with a clear next step.", icon: "list.number"),
                                .example(title: "A Complete Elevator Pitch", body: "Hook: \"Did you know that 75% of people are more afraid of public speaking than death?\"\n\nProblem: \"Most people avoid speaking opportunities entirely — which means they miss promotions, stay quiet in meetings, and let others take credit for their ideas.\"\n\nSolution: \"SpeakUp is a private practice app that lets you record yourself, get instant AI analysis on your pace, fillers, and clarity, and follow a guided learning path from nervous beginner to confident speaker.\"\n\nProof: \"Users improve their speaking score by an average of 25 points in just four weeks of daily practice.\"\n\nAsk: \"I'd love to show you a quick demo. Could I have 5 minutes of your time tomorrow?\""),
                                .tip("Practice your pitch at a dinner table with a non-expert friend. If they can repeat your main idea back to you in one sentence, your pitch is clear. If they can't, it's too complex. Simplify until they can.", title: "The Dinner Table Test"),
                                .keyTakeaway("The best pitch is one the listener can repeat to someone else. If they can retell your story in 10 seconds, you've won."),
                            ])
                        ),
                        .practice(id: "w8_l2_a2", title: "Elevator pitch recording", description: "Record a 60-second elevator pitch for something you care about: your job, a project, an idea, or even this app. Use the pitch structure: Hook → Problem → Solution → Proof → Ask.", duration: 60),
                    ]
                ),

                // ── W8 L3: The 5-Minute Talk ─────────────────────────
                CurriculumLesson(
                    id: "w8_l3",
                    title: "The 5-Minute Talk",
                    objective: "Deliver a complete mini-presentation combining every skill you've learned.",
                    activities: [
                        .lesson(
                            id: "w8_l3_a1",
                            title: "Structuring a complete talk",
                            description: "A 5-minute talk is a full presentation in miniature. It requires opening hooks, clear structure, stories, and a strong closing.",
                            content: LessonContent(sections: [
                                .concepts(title: "The 5-Minute Talk Blueprint", body: "Five minutes is the gold standard for short-form speaking. It's long enough to be substantive but short enough to hold full attention. TED recommends 5-18 minutes for a reason.\nThis is your capstone — every skill from the past 8 weeks comes together here.\nThink of it as five 1-minute blocks, each with a clear purpose.", icon: "rectangle.split.3x1.fill"),
                                .concepts(title: "The Five Blocks", body: "Block 1: The Hook + Big Idea (0:00-1:00) — Open with a hook (Week 7), then state your one big idea clearly. Everything else supports this single thesis.\nBlock 2: The Problem or Context (1:00-2:00) — Set up the tension using PSB or What-So What-Now What.\nBlock 3: The Core Argument (2:00-3:30) — Your main evidence, using Rule of Three. Three points, each with a brief example.\nBlock 4: The Story (3:30-4:30) — A personal story that illustrates your big idea. Use the Story Arc for structure.\nBlock 5: The Close (4:30-5:00) — Restate your big idea, deliver a challenge or vision, and end with your strongest line.", icon: "list.number"),
                                .concepts(title: "Transitions Between Blocks", body: "\"Here's why this matters...\" (Hook → Problem)\n\"Let me show you the three reasons...\" (Problem → Argument)\n\"Let me tell you a story that brings this to life...\" (Argument → Story)\n\"And that brings me to the one thing I hope you take away...\" (Story → Close)\nSmooth transitions are the glue that holds your talk together. Without them, your talk feels like a list.", icon: "arrow.left.arrow.right"),
                                .tip("Your talk should have exactly ONE big idea. Not three, not five — one. Everything in your 5 minutes should support, illustrate, or reinforce that single idea. If a section doesn't serve the big idea, cut it.", title: "The One Big Idea Rule"),
                                .keyTakeaway("A great 5-minute talk proves you can speak at any length. If you can hold an audience for 5 minutes with structure, stories, and a clear big idea, you can hold them for 50."),
                            ])
                        ),
                        .practice(id: "w8_l3_a2", title: "5-minute talk", description: "Your capstone recording. Record a full 5-minute talk on a topic you're passionate about. Use the five-block structure: Hook → Problem → Three Points → Story → Close.", duration: 300),
                    ]
                ),

                // ── W8 L4: Graduation ────────────────────────────────
                CurriculumLesson(
                    id: "w8_l4",
                    title: "Graduation",
                    objective: "Celebrate your transformation and plan your continued growth.",
                    activities: [
                        .review(id: "w8_l4_a1", title: "Final before-and-after", description: "Listen to your very first recording from Week 1 and your 5-minute talk from the previous lesson. The difference is your proof of growth."),
                        .lesson(
                            id: "w8_l4_a2",
                            title: "What's next for you",
                            description: "You've completed the entire SpeakUp Learning Path. Here's how to keep growing.",
                            content: LessonContent(sections: [
                                .callout(title: "Congratulations, Graduate!", body: "You've completed the entire 8-week SpeakUp Learning Path. That's 32 lessons, dozens of practice sessions, 8 speech frameworks, and a transformation from uncertain beginner to confident, structured speaker. That takes serious commitment.", icon: "graduationcap.fill"),
                                .concepts(title: "Your Complete Toolkit", body: "Awareness skills — You know your baseline, your filler patterns, your natural pace, and your score components.\nFoundation skills — Breathing, filler control, pace management, and vocal warm-up routines.\nStructure frameworks — PREP, STAR, Rule of Three, PSB, What-So What-Now What, and the Bridge.\nVocal skills — Variety, projection, articulation, emphasis, and word stress.\nStorytelling skills — Story arc, opening hooks, emotional connection, and powerful closings.\nReal-world skills — Q&A handling, elevator pitches, and full 5-minute presentations.", icon: "briefcase.fill"),
                                .concepts(title: "Your Ongoing Practice Plan", body: "Daily (2 minutes) — One quick recording using any framework. Consistency matters more than duration.\nWeekly (10 minutes) — One longer practice session (3-5 minutes). Try a new topic or framework each week.\nBefore important events — Run through your warm-up routine, then do one practice recording of your opening.\nMonthly — Compare your latest recording to one from the previous month. Track your improvement over time.", icon: "calendar"),
                                .concepts(title: "Advanced Challenges", body: "Record yourself explaining a complex topic to a child. If you can make it simple, you truly understand it.\nPractice the same 60-second talk five times in a row. Watch how it improves with each iteration.\nRecord a talk, listen back, and re-record trying to fix one specific thing. Deliberate practice is how experts are made.\nChallenge a friend through the social challenge feature. Teaching and competing accelerate growth.", icon: "flame.fill"),
                                .tip("The best speakers never stop practicing. They just practice with more awareness, more intention, and more joy. You now have every tool you need. The difference between a good speaker and a great one is simply: the great one kept practicing.", title: "One Final Thought"),
                                .keyTakeaway("You started with a baseline. You're leaving with a complete communication toolkit. The path ends here, but your growth as a speaker never does. Keep recording. Keep improving. Keep speaking up."),
                            ])
                        ),
                    ]
                ),
            ]
        ),
    ]
}
