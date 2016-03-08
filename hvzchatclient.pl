#!/usr/bin/env perl

use strict;
use warnings;
use feature ':5.20';
use utf8;
#BEGIN { use File::Spec::Functions qw/rel2abs/; use File::Basename qw/dirname/;  }
#use lib dirname rel2abs $0;
## no critic (SubroutinePrototypes)

use WWW::Mechanize;
use URI;
use HTML::TreeBuilder 5 -weak;
use IO::All;
use AnyEvent;
use AnyEvent::Strict;
use AnyEvent::Util qw/run_cmd/;
use Algorithm::Diff qw/diff/;
use List::AllUtils qw/max min/;
use Class::Struct;
use Data::Dump qw/pp dd/;
use Date::Format;
use Term::ReadKey;
use Text::Wrap qw/wrap/;
$Text::Wrap::columns = main::min ($ENV{COLUMNS}, 140);

sub concat(@) { map {@$_} @_ }

{
	package WWW::Mechanize::GaTechCAS;

	use parent qw/WWW::Mechanize/;

	sub new {
		my $class = shift;
		my $self = $class->SUPER::new();
		$self->{CAS} = {username=>"",password=>""};
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
			print "\n";
			$failed_yet = 1;
		}
	}

	sub get_killboard($) {
		my $self = shift;
		$self->get('/killboard');
		my $tree = HTML::TreeBuilder->new;
		$tree->parse_content($self->content);
		my $factions = {}; $factions->{$_} = [] for qw/human zombie/;
		for my $faction (keys %$factions) {
			my @killboard = $tree->look_down(id=>"$faction-killboard");
			$factions->{$faction} = [map {$_->as_text} $killboard[0]->look_down(_tag=>'a',href=>qr/\?gtname=/)];
			$factions->{$faction} = ['The OZ'] unless scalar @{$factions->{$faction}};
		}
		$self->back;
		return $factions;
	}

	sub longest_name_length_on_killboard($) {
		my $self = shift;
		return main::max map { length $_ } main::concat values %{$self->get_killboard};
	}

}

{
	package ChatLine;
	use Class::Struct faction=>'$',sender=>'$',timestamp=>'$',message=>'$';

	sub from_tr($$$) {
		my $class = shift;
		my ($faction, $tr) = @_;
		return $class->new(
			faction=>$faction,
			sender=>($tr->content_list)[0]->as_trimmed_text,
			timestamp=>([$tr->content_list]->[1]->as_trimmed_text =~ s/ ([0-9][^0-9])/ 0$1/r),
			message=>[$tr->content_list]->[2]->as_trimmed_text,
		);
	}

	sub format($$) {
		my ($self, $longest_name_length) = @_;
		my $header = sprintf("[%s] %-${longest_name_length}s -> %s: ", $self->timestamp, $self->sender, $self->faction);
		my $subsequent_tab = " " x (length $header);
		return main::wrap($header, $subsequent_tab, $self->message) . "\n";
	}

	sub hash($) { return 0 if not $_; return join "\t", @$_; }

	sub alert ($$) {
		my $self = shift;
		my $run_cmd = shift;
		use File::Which qw/which/;
		return unless defined which 'notify-send';
		$run_cmd->([qw/notify-send -a/,'HvZ Chat','--',$self->sender.' -> '.$self->faction,$self->message]);
	}

	sub groupme_post ($) {
		my $self = shift;
		use LWP::UserAgent;
		my $poster = LWP::UserAgent->new;
		my $uri = URI->new('https://api.groupme.com/v3/bots/post');
		my $factions = {all=>'29f6942ccecb3337f7a1695abc',hum=>'9d4d920368ed42d1c628a614e4'};
		$uri->query_form({bot_id=>$factions->{$self->faction},text=>sprintf("%s: %s",$self->sender,$self->message)});
		my $response = $poster->post($uri);
		if (!$response->is_success) { die $response->status_line; }
	}

	sub print_all($$\[$&]@) {
		my ($class, $longest_name_length, $should_alert, @lines) = @_;
		#open my $null, '>', '/dev/null';
		print map { $_->alert($should_alert) if $should_alert; $_->groupme_post() if $should_alert; $_->format($longest_name_length) } sort { $a->timestamp cmp $b->timestamp } @lines;
	}
}

my $mech = WWW::Mechanize::GaTechCAS->new();

$mech->stdio_authenticate;

$mech->get('/chat/');

sub make_chattracker() {
	my $chatlines = {};
	$chatlines->{$_} = [] for qw/all hum zomb/;
	my $data_file = $0 =~ s/\.pl$/.data.pl/r;
	if (-f $data_file) {
		$chatlines = do $data_file;
	}

	my $longest_name_length = $mech->longest_name_length_on_killboard;
	ChatLine->print_all($longest_name_length, 0, concat values %$chatlines);
	return sub {
		use sort 'stable';
		my @outlines = ();
		$mech->ensure_hvz_session or die "auth problem";
		$longest_name_length = $mech->longest_name_length_on_killboard;
		$mech->get('/chat/');
		for my $faction (sort keys %$chatlines) {
			$mech->post(URI->new_abs('_update.php', $mech->uri), {aud=>$faction});
			my $tree = HTML::TreeBuilder->new;
			$tree->parse_content($mech->content);
			map { $_->replace_with_content } $tree->look_down(_tag=>'a', href=>qr/\?gtname=/);
			my @additions = map { $_->[2] } grep {$_->[0] eq '+'} concat(diff($chatlines->{$faction}, [map {ChatLine->from_tr($faction, $_)} $tree->look_down(_tag=>'tr',class=>qr/chat_line/)], sub { defined $_ ? $_->hash : "" } ));
			push @{$chatlines->{$faction}}, @additions;
			push @outlines, @additions;
		}
		ChatLine->print_all($longest_name_length, \&run_cmd, @outlines);
		if (@outlines) {
			print "\a";
			pp($chatlines) > io($data_file);
		}
	};
}

my $timer_repeated = AE::timer 0, 3, make_chattracker;

my $stdin_ready = AE::io *STDIN, 0, sub {
	chomp( my $input = <STDIN> );
	$input =~ /(all|hum|zomb): *(.+)/ or die 'usage: (*all*|*hum*|*zomb*)*:* message';
	$mech->post(URI->new_abs('_post.php', $mech->uri), {aud=>$1, content=>$2});
};

AE::cv->recv;
