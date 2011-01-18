#!/usr/local/bin/perl

=head1 modify-slavedns.pl

Change the master DNS server for some slave domain.

This command updates the list of master DNS servers for some slave DNS
domain that is hosted on this Virtualmin system. The domain is selected
with the C<--domain> flag, followed by a virtual server name. The new list
of masters is set with the C<--master> flag, followed by an IP address. This
flag can be given multiple times to set more than one master.

=cut

package virtualmin_slavedns;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*)\/[^\/]+$/) {
		chdir($pwd = $1);
		}
	else {
		chop($pwd = `pwd`);
		}
	$0 = "$pwd/modify-slavedns.pl";
	require './virtualmin-slavedns-lib.pl';
	$< == 0 || die "$0 must be run as root";
	}
@OLDARGV = @ARGV;
&virtual_server::set_all_null_print();

# Parse command-line args
$type = "fsfs";
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$dname = shift(@ARGV);
		}
	elsif ($a eq "--master") {
		$mip = shift(@ARGV);
		&check_ipaddress($mip) ||
			&usage("--master must be followed by an IP address");
		push(@mips, $mip);
		}
	else {
		&usage();
		}
	}

# Validate parameters
$dname || &usage("Missing --domain parameter");
@mips || &usage("Missing --master parameter");

# Get the domain
$d = &virtual_server::get_domain_by("dom", $dname);
$d || &usage("No domain named $dname found");
$d->{'virtualmin-slavedns'} ||
	&usage("Slave DNS is not enabled for this domain");
&virtual_server::obtain_lock_dns($d, 1);
$z = &virtual_server::get_bind_zone($d->{'dom'});
$z || &usage("No DNS zone found for $d->{'dom'}");
&virtual_server::require_bind();

# Run the before command
&virtual_server::set_domain_envs($d, "MODIFY_DOMAIN", $d);
$merr = &virtual_server::making_changes();
&virtual_server::reset_domain_envs($d);
&usage(&virtual_server::text('save_emaking', "<tt>$merr</tt>"))
	if (defined($merr));

# Update the .conf file
$masters = &bind8::find('masters', $z->{'members'});
$oldmasters = { %$masters };
$masters->{'members'} = [ map { { 'name' => $_ } } @mips ];
&bind8::save_directive($z, [ $oldmasters ], [ $masters ], 1);
$allow = &bind8::find('allow-update', $z->{'members'});
if ($allow) {
	$oldallow = { %$allow };
	$allow->{'members'} = [ map { { 'name' => $_ } } @mips ];
	&bind8::save_directive($z, [ $oldallow ], [ $allow ], 1);
	}
&flush_file_lines($z->{'file'});
&virtual_server::restart_bind($d);

# Run the after command
&virtual_server::set_domain_envs($d, "MODIFY_DOMAIN", undef, $d);
$merr = &virtual_server::made_changes();
print &virtual_server::text('setup_emade', "<tt>$merr</tt>")
	if (defined($merr));
&virtual_server::reset_domain_envs($d);

&virtual_server::release_lock_dns($d, 1);
&virtual_server::virtualmin_api_log(\@OLDARGV, $d);
print "Changed master IP addresses for $d->{'dom'}\n";

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Change the master DNS server for some slave domain.\n";
print "\n";
print "virtualmin modify-slavedns --domain name\n";
print "                          [--master ip]+\n";
exit(1);
}

