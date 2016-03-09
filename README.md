# GA Tech HvZ, Mechanized

## Background

A student organization at the Georgia Institute of Technology, also known as Georgia Tech, hosts a campuswide game of tag (of sorts) which is based on, and uses the name of, "Humans vs Zombies" or "HvZ" for short.

In order to comply with Georgia Tech IT regulations, Georgia Tech HvZ uses, to track the state of the game and provide certain player-facing services, one of Georgia Tech's own webservers with Georgia Tech HvZ's own custom-made web application.

This custom-made web application includes a "Chat" system. This chat system is, in some cases, the only way to quickly contact other players, and is generally the only way to blast out important information to every member of one's faction.

This "Chat" system, however, is implemented by polling the server for the complete contents of the chat log.

As such, the "Chat" system cannot detect when new messages have arrived.

As such, the "Chat" system cannot use HTML5's Notification API to asynchronously tell me when I actually need to pay attention to it.

As such, the "Chat" system consumes much more mental resources than it should. That is a problem.

In lieu of me figuring out how to cram a `diff` algorithm into a userscript, this repo is my solution.

## What this does

`hvzchatclient.pl` prompts on standard I/O for your Georgia Tech SSO credentials; with them and WWW::Mechanize, it scrapes the SSO login page and uses the resulting cookies to access the HvZ website's chat system in mostly the same way that the original website frontend does. Both the general channel and your faction's channel are available to you, and the existing backend keeps track of this. (Nonetheless, using this program while your faction-membership is in limbo ... has the same consequences to Rule 1 that would occur if you used the regular chat frontend at such a time.)

Specifically:

- Any messages which were not recorded as previously-received, are echoed to standard output, sent through `notify-send` and logged to disk.

	- Experimental: such messages are also posted through a GroupMe bot. Requires that one edit `bot_ids.pl` with the Bot IDs that one wishes to use. (Posting my own bots' IDs publicly -> spam)

- Any input on stdin which matches `/(all|hum|zomb): .+/` (that is, containing the word "all", "hum" or "zomb", followed immediately by a colon, a space and some message contents) will be sent to the corresponding channel, provided that you're not trying to send to the opposing faction.

- Command-line arguments are ignored.

## Limitations

- Polls the server every few seconds. This is bad for both sides' network performance and even worse for clientside power consumption. The original website frontend itself is no different, however.
- Since it uses a non-POE event loop, it cannot interact with you by using POE's IRCd; this is half bug, half feature: it's a bug in that being able to use Irssi would yield a lot of nice things for free, but it's a feature in that being strictly limited to one user prevents anyone from using this in a manner which might violate Georgia Tech IT regulations against storing SSO credentials.
	- (Note, this program does *not* request or store the primary key for the Georgia Tech SSO database entry that corresponds to you. Storing other people's credentials in-memory on the other hand... where you could dump them to disk as easily as the logs... if that isn't against policy then I would be very, very surprised.)

## Bugs

- ~~Does not yet interact with you by acting as a client of *insert hip new mobile direct-messaging protocol here*.~~ Experimental support for GroupMe's bot system is underway.
- Does not use ncurses or similar to separate input from output. Workaround is to make a fifo, connect the reader end to `hvzchatclient.pl` and connect the writer end to `(echo $username; echo $pass; cat)` on another terminal.
- Does not yet scrape the HvZ website to identify you and thereby filter-out your own messages from causing notifications.
- ~~Does not yet scrape the player list to announce faction membership changes.~~
- Does not yet scrape the announcements etc that used to be emailed before that system went out-of-commission.
- Is not fully decomposed into a module and a main program.
- Error handling is primitive. Most errors will print an error and halt the current poll or send; non-transient errors (e.g. network down) will spam stderr with semi-cryptic messages.

## Dependencies

- notify-send
- perl
- a ton of Perl modules:
	- Algorithm::Diff
	- AnyEvent
	- Carp::Always
	- Class::Struct
	- Data::Dump
	- Date::Format
	- DateTime
	- DateTime::Format::Strptime
	- File::Which
	- HTML::TreeBuilder
	- IO::All
	- List::AllUtils
	- Term::ReadKey
	- Text::Wrap
	- URI
	- WWW::Mechanize

## Copyright

Copyright (C) 2016 Milo Mirate.

All rights reserved. This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

