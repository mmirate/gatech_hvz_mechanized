# GA Tech HvZ, Mechanized

## Background

A student organization at the Georgia Institute of Technology, also known as Georgia Tech, hosts a campuswide game of tag (of sorts) which is based on, and uses the name of, "Humans vs Zombies" or "HvZ" for short.

In order to comply with Georgia Tech IT regulations, Georgia Tech HvZ uses, to track the state of the game and provide certain player-facing services, one of Georgia Tech's own webservers with Georgia Tech HvZ's own custom-made web application.

This custom-made web application includes a "Chat" system. This chat system is, in some cases, the only way to quickly contact other players, let alone to blast out important information to every member of one's faction.

This "Chat" system, however, is implemented by polling the server for the complete contents of the chat log.

As such, the "Chat" system cannot detect when new messages have arrived.

As such, the "Chat" system cannot use HTML5's Notification API to asynchronously tell me when I actually need to pay attention to it.

As such, the "Chat" system consumes much more mental resources than it should. This is a problem.

In lieu of me figuring out how to cram a `diff` algorithm into a userscript, this repo is my solution.

## What this does

`hvzchatclient.pl` prompts for your Georgia Tech SSO credentials; with them and WWW::Mechanize, it scrapes the SSO login page and uses the resulting cookies to access the HvZ website's chat system in mostly the same way that the original website frontend does.

Any messages which were not recorded as previously-received, are echoed to standard output, sent through `notify-send` and logged to disk.

Any input on stdin which matches `/(all|hum|zomb): .+/` will be sent to the corresponding channel, provided that you're not trying to send to the opposing faction.

## Limitations

- Polls the server every few seconds. This is bad for network performance and really bad for power consumption. The original website frontend itself is no different, however.
- Since it uses a non-POE event loop, it cannot interact with you by using POE's IRCd; this is half bug, half feature: it's a bug in that being able to use Irssi would yield a lot of nice things for free, but it's a feature in that being strictly limited to one user prevents anyone from using this in a manner which might violate Georgia Tech IT regulations against storing SSO credentials.

## Bugs

- Does not yet interact with you by acting as a client of *insert hip new mobile direct-messaging protocol here*.
- Does not use ncurses or similar to separate input from output. Workaround is to make a fifo, connect the reader end to `hvzchatclient.pl` and connect the writer end to `cat` on another terminal.
- Does not yet scrape the HvZ website to see who you are, in order to filter-out your own messages from causing notifications.
- Does not yet scrape the player list to notify upon detection of taggings.
- Does not yet scrape the announcements etc that used to be emailed before that system went out-of-commission.
- Is not decomposed into a module and a main program.

## Dependencies

- Perl
- a ton of Perl modules:
	- Algorithm::Diff
	- AnyEvent
	- Class::Struct
	- Data::Dump
	- Date::Format
	- HTML::TreeBuilder
	- IO::All
	- List::AllUtils
	- Term::ReadKey
	- Text::Wrap
	- WWW::Mechanize

## Copyright

Copyright (C) 2016 Milo Mirate.

All rights reserved. This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
