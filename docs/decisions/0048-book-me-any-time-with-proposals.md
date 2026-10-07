---
id: 0048
date: 2026-10-07
status: accepted
repos: [openlabtwin]
commits: []
---

## Context

Book me offered only pre-computed free slots from the consultation hours. With no hours in the window, students saw "No free times this week" and could not ask at all. Staff want to take any request and move it to fit their load.

## Decision

Students ask for any date, time and length. Staff accept, reject, or propose another time; the student answers on the private status link (`answer_proposal`). The office shows that day's lessons in the lab room and in the staff member's own master programme. New status `proposed`, counted as open. No emails: staff send the link. `free_slots` stays but is unused. The timetable has one room name for Tech Lab and Game Lab, so they can't be told apart; the study year isn't stored, so own classes match by programme only.

## Consequences

Anyone can fill the 20-request cap with junk; limits and the honeypot are the only guard. Replaces the slot-list part of the Book me design.
