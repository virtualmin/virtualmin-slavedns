use strict;
use warnings;
our $module_name;

do 'virtualmin-slavedns-lib.pl';

sub cgi_args
{
my ($cgi) = @_;
my ($d) = grep { &virtual_server::can_edit_domain($_) &&
	         $_->{$module_name} } &virtual_server::list_domains();
if ($cgi eq 'edit.cgi') {
	return $d ? 'dom='.&urlize($d->{'dom'}) : 'none';
	}
return undef;
}
