# README

<https://clime.cloud> is a web application designed to add convenient functionality to 4g feature phones (Also known as dumbphones) via a lightweight dashboard.

It is primarily tested through everyday use on my Nokia 2660.

All user information is stored client-side, meaning that there is no user data stored on climecloud servers.

Current functionality includes bus and train departures, turn by turn walking and driving directions, places nearby, weather forecasting, Wikipedia and news feeds.

This is all in a lightweight text-based format which is  sized to suit screens of 240x320px with minimal user interaction required due to the lack of touchscreen controls or a qwerty keyboard. There is no JavaScript on any page: every screen is plain HTML, and every choice on it is numbered so it can be reached with one keypress.


**The dashboard**

![Main menu in the Commodore callback theme](images/menu-commodore-callback.png)

*The main menu. Everything is a numbered option, so the keypad is the whole interface — press 3 for places nearby, 6 for departures. Theme: Commodore callback.*


**Bus and train times, without typing anything**

Typing a stop name on a keypad is miserable, so you never have to. The app takes the postcode saved in settings and lists the stops and stations around it in order of distance. Press the number next to one and it is saved; from then on it is on the departures screen and its times are two keypresses away.

![Nearby stops list in the Nokia LCD theme](images/nearby-stops-nokia-lcd.png)

*Every stop and station within walking distance, nearest first, with more a keypress away. Nothing here needs a keyboard. Theme: Nokia LCD.*

![Departure times in the Departure board theme](images/departures-departure-board.png)

*A saved stop, with the time, the service number, where it is going and what kind of vehicle it is. Live times are marked as live; everything else is the timetable. Theme: Departure board.*


**Turn by turn navigation**

A route is broken into one turn per screen, each with its own map image, the distance and time for that leg, and the compass heading to set off on. 1 moves to the next turn and 2 goes back, so the phone can stay in a pocket between junctions.

![A single turn with its map in the Amber phosphor theme](images/turn-by-turn-amber-phosphor.png)

*Turn 1 of 9 on a walking route, with the map oriented north up. Theme: Amber phosphor.*


**Places nearby, including a toilet when you need one**

Ten categories of useful things around you — food, shops, cash, toilets, pharmacy, pub, transport, parking, petrol, and hospital and doctor — each returning the nearest handful with the distance to them. Toilets deliberately returns everything that usually has one rather than only public conveniences, because with a toddler in tow the nearest pub, cafe or Greggs is the answer far more often than an actual public toilet is. Each result links straight into walking directions.

![Toilets nearby in the Green phosphor theme](images/toilets-nearby-green-phosphor.png)

*Toilets near central Manchester: a pub at 51m, a cafe at 57m, and an actual public toilet at 95m. Theme: Green phosphor.*


**Wikipedia**

Search Wikipedia and read the summary of an article, or the whole thing, as plain text at a readable size.

![The Wikipedia search screen in the Barbiephone theme](images/wikipedia-barbiephone.png)

*The search screen. Results come back numbered, so an article is one keypress away. Theme: Barbiephone.*


**Themes**

The look is chosen in settings and remembered. Most of the styles borrow from a screen with a character of its own — a phosphor terminal, a departure board, a Game Boy — and they work on the handset as well as on a modern phone.

* (No theme) — black on white, the default
* Amber phosphor
* Barbiephone
* Barbiephone dark
* Blue LCD
* Commodore callback
* Departure board
* E-ink paper
* Game Boy
* Green phosphor
* Nokia LCD
* OLED dark
* Orange plasma
* Teletext
* Workbench


**On the handset**

![Main menu screen](images/1tn.jpeg)

![Weather forecast screen](images/3tn.jpeg)

![Directions screen](images/7tn.jpeg)
