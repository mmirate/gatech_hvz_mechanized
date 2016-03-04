package MechanizeCAS;

use strict;
use warnings;
use feature ':5.20';
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
use WWW::Mechanize;

$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = ();
@EXPORT_OK   = qw(get_hvz_session);

## no critic (SubroutinePrototypes)
sub get_hvz_session($$$) {
	my ($mech, $un, $pass) = @_;
	$mech->get('https://hvz.gatech.edu/killboard/');
	if ('login.gatech.edu' eq $mech->uri->host) {
		$mech->submit_form(with_fields=>{username=>$un,password=>$pass});
	}
	return 'hvz.gatech.edu' eq $mech->uri->host;
}

1;
