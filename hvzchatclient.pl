#!/usr/bin/env perl

use strict;
use warnings;
use feature ':5.20';
use utf8;
BEGIN { use File::Spec::Functions qw/rel2abs/; use File::Basename qw/dirname/;  }
use lib dirname rel2abs $0;
## no critic (SubroutinePrototypes)

use WWW::Mechanize;
use URI;
use MechanizeCAS qw/get_hvz_session/;
use HTML::TreeBuilder 5 -weak;
use IO::All;
use AnyEvent;
use AnyEvent::Strict;
use AnyEvent::Util qw/run_cmd/;
use Algorithm::Diff qw/diff/;
use List::AllUtils qw/max min/;
use Class::Struct;
use Text::Wrap qw/wrap/;
use Data::Dump qw/pp dd/;
use Date::Format;
use Term::ReadKey;

my $mech = WWW::Mechanize->new();

my ($user, $pass, $failed_yet) = ('','',0);
until ((length $user) and (length $pass) and get_hvz_session($mech,$user,$pass)) {
	print "Authentication failure; please try again.\n" if $failed_yet;
	print STDERR "Username for login.gatech.edu: ";
	chomp($user = <STDIN>);
	ReadMode 'noecho';
	print STDERR "Password for login.gatech.edu: ";
	chomp($pass = <STDIN>);
	ReadMode 'restore';
	print "\n";
	$failed_yet = 1;
}

$mech->get('/chat/');

sub concat(@) { map {@$_} @_ }

sub get_killboard() {
	$mech->get('/killboard');
	my $tree = HTML::TreeBuilder->new;
	$tree->parse_content($mech->content);
	my $factions = {}; $factions->{$_} = [] for qw/human zombie/;
	for my $faction (keys %$factions) {
		my @killboard = $tree->look_down(id=>"$faction-killboard");
		$factions->{$faction} = [map {$_->as_text} $killboard[0]->look_down(_tag=>'a',href=>qr/\?gtname=/)];
		$factions->{$faction} = ['The OZ'] unless scalar @{$factions->{$faction}};
	}
	return $factions;
}

my $longest_name_length = max map { length } concat values get_killboard;

$Text::Wrap::columns = min ($ENV{COLUMNS}, 140);

struct(ChatLine => {faction=>'$',sender=>'$',timestamp=>'$',message=>'$'});

sub chatline_format($) {
	my $self = shift;
	my $header = sprintf("[%s] %-${longest_name_length}s -> %s: ", $self->timestamp, $self->sender, $self->faction);
	my $subsequent_tab = " " x (length $header);
	return wrap($header, $subsequent_tab, $self->message) . "\n";
}
sub chatline_hash($) { return 0 if not $_; return join "\t", @{shift()}; }
sub chatline_new($$) {
	my ($faction, $tr) = @_;
	return ChatLine->new(
		faction=>$faction,
		sender=>($tr->content_list)[0]->as_trimmed_text,
		timestamp=>([$tr->content_list]->[1]->as_trimmed_text =~ s/ ([0-9][^0-9])/ 0$1/r),
		message=>[$tr->content_list]->[2]->as_trimmed_text,
	);
}
sub chatline_alert($) {
	my $self = shift;
	run_cmd [qw/notify-send -a/,'HvZ Chat',$self->sender.' -> '.$self->faction,$self->message];
}

sub make_chattracker() {
	my $chatlines = {};
	$chatlines->{$_} = [] for qw/all hum zomb/;
	my $data_file = $0 =~ s/\.pl$/.data.pl/r;
	if (-f $data_file) {
		$chatlines = do $data_file;
		#for my $faction (sort keys %$chatlines) {
		#    dd $faction;
		#    $chatlines->{$faction} = [map { dd $_; ChatLine->new(%$_) } @{$chatlines->{$faction}}];
		#}
		#dd $chatlines;
	}

	print map { chatline_format $_ } sort { $a->timestamp cmp $b->timestamp } concat values %$chatlines;
	#chatline_alert [reverse concat values %$chatlines]->[0];
	my $newfunc = sub {
		use sort 'stable';
		my @outlines = ();
		get_hvz_session($mech,$user,$pass) or die "auth problem"; $mech->get('/chat/');
		for my $faction (sort keys $chatlines) {
			$mech->post(URI->new_abs('_update.php', $mech->uri), {aud=>$faction});
			my $tree = HTML::TreeBuilder->new;
			$tree->parse_content($mech->content);
			map { $_->replace_with_content } $tree->look_down(_tag=>'a', href=>qr/\?gtname=/);
			my @additions = map { $_->[2] } grep {$_->[0] eq '+'} concat(diff($chatlines->{$faction}, [map {chatline_new($faction, $_)} $tree->look_down(_tag=>'tr',class=>qr/chat_line/)], \&chatline_hash));
			push $chatlines->{$faction}, @additions;
			#print join "", map { join "", ("$faction: ", join "\t", @$_, "\n") } @additions;
			push @outlines, @additions;
		}
		print map {chatline_alert $_;chatline_format $_} sort { $a->timestamp cmp $b->timestamp } @outlines;
		if (@outlines) {
			print "\a";
			pp($chatlines) > io($data_file);
		}
	};
	return $newfunc;
}

my $timer_repeated = AE::timer 0, 3, make_chattracker;

my $stdin_ready = AE::io *STDIN, 0, sub {
	chomp( my $input = <STDIN> );
	$input =~ /(all|hum|zomb): *(.+)/ or die 'usage: (*all*|*hum*|*zomb*)*:* message';
	$mech->post(URI->new_abs('_post.php', $mech->uri), {aud=>$1, content=>$2});
};

AE::cv->recv;
