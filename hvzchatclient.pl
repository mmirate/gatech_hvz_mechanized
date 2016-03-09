#!/usr/bin/env perl

use strict;
use warnings;
use feature ':5.20';
use utf8;
#BEGIN { use File::Spec::Functions qw/rel2abs/; use File::Basename qw/dirname/;  }
#use lib dirname rel2abs $0;
## no critic (SubroutinePrototypes)

use Carp::Always;
use Algorithm::Diff qw/diff/;
use AnyEvent;
use AnyEvent::Strict;
use AnyEvent::Util qw/run_cmd/;
use Class::Struct;
use Data::Dump qw/pp dd/;
use Date::Format;
use DateTime;
use DateTime::Duration;
use DateTime::Format::Strptime;
use File::Which qw/which/;
use HTML::TreeBuilder 5 -weak;
use IO::All;
use List::AllUtils qw/max min notall uniq first shuffle/;
use LWP::UserAgent;
use Term::ReadKey;
use Text::Wrap qw/wrap/;
use URI;
use WWW::Mechanize;
$Text::Wrap::columns = main::min ($ENV{COLUMNS}, 140);

my $strp = DateTime::Format::Strptime->new(
	pattern=>"%Y/%m/%d %R",
	time_zone=>'America/New_York',
	on_error=>'croak'
);

my $quit = AE::cv;

sub concat(@) { map {@$_} @_ }

{
	package WWW::Mechanize::GaTechCAS;

	use parent qw/WWW::Mechanize/;

	sub new {
		my $class = shift;
		my $self = $class->SUPER::new();
		$self->timeout(10);
		$self->{CAS} = {username=>"",password=>""};
		$self->{hvz_data}->{killboard}->{$_} = [] for qw/human zombie/;
		$self->{hvz_data}->{chatlines}->{$_} = [] for qw/all hum zomb/;
		$self->{data_file} = $0 =~ s/\.pl$/.data.pl/r;
		if (-f $self->{data_file}) {
			$self->{hvz_data} = do $self->{data_file};
		}

		return $self;
	}

	## no critic (SubroutinePrototypes)
	sub ensure_hvz_session($) {
		my $self = shift;
		$self->get('https://hvz.gatech.edu/killboard/');
		if ('login.gatech.edu' eq $self->uri->host) {
			$self->submit_form(with_fields=>$self->{CAS});
		}
		return 'hvz.gatech.edu' eq $self->uri->host;
	}

	sub stdio_authenticate($) {
		my $self = shift;
		my $failed_yet = 0;
		until ((length $self->{CAS}->{username}) and (length $self->{CAS}->{password}) and $self->ensure_hvz_session) {
			print "Authentication failure; please try again.\n" if $failed_yet;
			print STDERR "Username for login.gatech.edu: ";
			chomp($self->{CAS}->{username} = <STDIN>);
			main::ReadMode 'noecho';
			print STDERR "Password for login.gatech.edu: ";
			chomp($self->{CAS}->{password} = <STDIN>);
			main::ReadMode 'restore';
			print STDERR "\n";
			$failed_yet = 1;
		}
	}

	sub get_killboard($) {
		my $self = shift;
		$self->ensure_hvz_session;
		$self->get('/killboard');
		my $tree = HTML::TreeBuilder->new;
		$tree->parse_content($self->content);
		my $factions = {}; $factions->{$_} = [] for qw/human zombie/;
		for my $faction (keys %$factions) {
			my @killboard = $tree->look_down(id=>"$faction-killboard");
			$factions->{$faction} = [map {$_->as_text} $killboard[0]->look_down(_tag=>'a',href=>qr/\?gtname=/)];
			$factions->{$faction} = ['The OZ'] unless scalar @{$factions->{$faction}};
		}
		my @deaths = map { $_->[2] } grep {$_->[0] eq '+'} main::concat(main::diff($self->{hvz_data}->{killboard}->{zombie}, $factions->{zombie}));
		print "$_ is dead.\n" for @deaths;
		@deaths = () unless scalar @{$self->{hvz_data}->{killboard}->{zombie}};
		for my $nom (@deaths) {
			my $exclamation = main::first {1} main::shuffle ("Consarnit.", "Well, drat.", "Argh.", "Dear me.", "Eek!", "Well, I'll be.", "Oh, scrap.", "Hunh.");
			my $qualifier = main::first {1} main::shuffle ("Looks like", "I think that", "They're 100% positive that", "Seems that", "It appears as though", "The killboard says");
			my $verbphrase = main::first {1} main::shuffle ("$nom bit the dust", "$nom died", "$nom turned", "$nom was nommed", "someone killed $nom", "$nom became an ex-human", "$nom is no longer with us", "the zeds got $nom");
			_groupme_post("hum", "$exclamation $qualifier $verbphrase up to 3 hours ago.");
		}
		_groupme_post("hum", "There are now ".(scalar @{$self->{hvz_data}->{killboard}->{zombie}})." zombies on the killboard.") if @deaths;
		$self->{hvz_data}->{killboard} = $factions;
		$self->back;
		return $factions;
	}

	sub longest_name_length_on_killboard($) {
		my $self = shift;
		return main::max map { length $_ } main::concat values %{$self->get_killboard};
	}

	sub whoami($) {
		my $self = shift;
		return $self->{CAS}->{username};
	}

	sub make_chattracker($) {
		my $self = shift;

		my $longest_name_length = $self->longest_name_length_on_killboard;
		ChatLine->print_all($self, $longest_name_length, undef, main::concat values %{$self->{hvz_data}->{chatlines}});
		return sub {
			use sort 'stable';
			my @outlines = ();
			$self->ensure_hvz_session or die "auth problem";
			$longest_name_length = $self->longest_name_length_on_killboard;
			$self->get('/chat/');
			for my $faction (sort keys %{$self->{hvz_data}->{chatlines}}) {
				$self->post(URI->new_abs('_update.php', $self->uri), {aud=>$faction});
				my $tree = HTML::TreeBuilder->new;
				$tree->parse_content($self->content);
				map { $_->replace_with_content } $tree->look_down(_tag=>'a', href=>qr/\?gtname=/);
				my @additions = map { $_->[2] } grep {$_->[0] eq '+'} main::concat(main::diff($self->{hvz_data}->{chatlines}->{$faction}, [map {ChatLine->from_tr($faction, $_)} $tree->look_down(_tag=>'tr',class=>qr/chat_line/)], sub { defined $_ ? $_->hash : "" } ));
				push @{$self->{hvz_data}->{chatlines}->{$faction}}, @additions;
				push @outlines, @additions;
			}
			if (@outlines) {
				print "\a";
				main::pp($self->{hvz_data}) > main::io($self->{data_file});
				ChatLine->print_all($self, $longest_name_length, \&main::run_cmd, @outlines);
			}
		};
	}

}

$main::groupme_bots = do ($0 =~ s/hvzchatclient\.pl$/bot_ids.pl/r);

sub _groupme_post($$);
sub _groupme_post($$) {
	my ($faction, $text) = @_;
	return if $main::groupme_bots->{$faction} =~ /^</;
	my $uri = URI->new('https://api.groupme.com/v3/bots/post');
	$uri->query_form({bot_id=>$main::groupme_bots->{$faction},text=>$text});
	my $poster = LWP::UserAgent->new;
	my $response = $poster->post($uri);
	if ($response->code eq "400") { sleep 5; return _groupme_post($faction, $text); }
	if (!$response->is_success) { die $response->status_line; }
}

{
	package ChatLine;
	use Class::Struct faction=>'$',sender=>'$',sender_is_admin=>'$',timestamp=>'$',message=>'$';

	sub from_tr($$$) {
		my $class = shift;
		my ($faction, $tr) = @_;

		my $ret = $class->new(
			faction=>$faction,
			sender=>($tr->content_list)[0]->as_trimmed_text,
			sender_is_admin=>($tr->attr('class') =~ /admin_line/ || 0),
			timestamp=>([$tr->content_list]->[1]->as_trimmed_text =~ s/ ([0-9][^0-9])/ 0$1/r),
			message=>[$tr->content_list]->[2]->as_trimmed_text,
		);
		return $ret;
	}

	sub is_old($) {
		my $self = shift;
		# "2016/" is a kludge to avoid error "There is no use providing a month without providing a year."
		return (DateTime::Duration->compare(DateTime->now->subtract_datetime($strp->parse_datetime("2016/". $self->timestamp)),DateTime::Duration->new(minutes=>2)) == 1)
	}

	sub format($$) {
		my ($self, $longest_name_length) = @_;
		my $header = sprintf("[%s] %-${longest_name_length}s -> %s: ", $self->timestamp, $self->sender, $self->faction);
		$header = ($self->is_old ? " " : "!") . $header;
		my $subsequent_tab = " " x (length $header);
		return main::wrap($header, $subsequent_tab, $self->message) . "\n";
	}

	sub hash($) { return 0 if not $_; return join "\t", @$_; }

	sub alert ($$) {
		my $self = shift;
		my $run_cmd = shift;
		return unless defined main::which 'notify-send';
		$run_cmd->([qw/notify-send -a/,'HvZ Chat','--',$self->sender.' -> '.$self->faction,$self->message]);
	}

	sub groupme_post ($) {
		my $self = shift;
		return if $self->faction eq "all" and not $self->sender_is_admin;
		#print $timestamp; print "\n";
		my $message = sprintf("%s: %s",$self->sender,$self->message);
		$message = sprintf("[%s] ",$self->timestamp) . $message if $self->is_old;
		main::_groupme_post($self->faction,$message);
	}

	sub print_all($$$&@) {
		my ($class, $mech, $longest_name_length, $should_alert, @lines) = @_;
		#open my $null, '>', '/dev/null';
		my @oldies = grep { $_->is_old } @lines;
		if (main::notall { !(defined $_ ) or defined $main::groupme_bots->{$_->faction} } @lines) {
			main::_groupme_post("human","My creator has died. RIP. My genes are at http://gatech.edu/mmirate/gatech_hvz_mechanized if anyone wants to re-clone me. Signing off.");
			$quit->send;
		}
		if (defined $should_alert and scalar @oldies) {
			main::_groupme_post("all","Whoops, looks like I slept through some chat posts. Here we go. Oldies are timestamped.");
		}
		print map { $_->alert($should_alert) if defined $should_alert; $_->groupme_post() if defined $should_alert; $_->format($longest_name_length) } sort { $a->timestamp cmp $b->timestamp } @lines;
	}
}

my $mech = WWW::Mechanize::GaTechCAS->new();

$mech->stdio_authenticate;

my $tracker = $mech->make_chattracker;
my $timer_repeated = AE::timer 0, 3, $tracker;

my $stdin_ready = AE::io *STDIN, 0, sub {
	chomp( my $input = <STDIN> );
	$input =~ /(all|hum|zomb|ALL|HUM|ZOMB): *(.+)/ or die 'usage: (*all*|*hum*|*zomb*)*:* message';
	if ($1 ne lc $1) {
		_groupme_post(lc $1, $2);
	} else {
		$mech->post(URI->new_abs('_post.php', $mech->uri), {aud=>$1, content=>$2});
	}
};

$quit->recv;
